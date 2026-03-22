//
//  ContentBlockerManager.swift
//  Nook
//
//  Orchestrator for native ad blocking. Replaces TrackingProtectionManager.
//  Manages enable/disable, per-domain whitelist, per-tab disable, OAuth exemption.
//  Coordinates filter download, compilation, and injection via three layers:
//  - Network blocking (WKContentRuleList)
//  - Cosmetic filtering (CSS injection via WKUserScript)
//  - Scriptlet injection (JS main-world WKUserScript)
//

import Foundation
import WebKit
import OSLog

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
final class ContentBlockerManager {
    weak var browserManager: BrowserManager?
    private(set) var isEnabled: Bool = false
    private(set) var isCompiling: Bool = false

    let filterListManager = FilterListManager()
    private let scriptletEngine = ScriptletEngine()
    private let redirectResourceManager = RedirectResourceManager()
    private var removeParamRules: [RemoveParamRule] = []

    private var compiledRuleLists: [WKContentRuleList] = []
    private var updateTimer: Timer?
    private static let updateInterval: TimeInterval = 24 * 60 * 60  // 24 hours
    private var thirdPartyCookieScript: WKUserScript {
        let js = """
        (function() {
          try {
            if (window.top === window) return;
            var ref = document.referrer || "";
            var thirdParty = false;
            try {
              var refHost = ref ? new URL(ref).hostname : null;
              thirdParty = !!refHost && refHost !== window.location.hostname;
            } catch (e) { thirdParty = false; }
            if (!thirdParty) return;
            Object.defineProperty(document, 'cookie', {
              configurable: false, enumerable: false,
              get: function() { return ''; },
              set: function(_) { return true; }
            });
            try {
              document.requestStorageAccess = function() { return Promise.reject(new DOMException('Blocked by Nook', 'NotAllowedError')); };
            } catch (e) {}
          } catch (e) {}
        })();
        """
        return WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    // MARK: - Exceptions

    private var temporarilyDisabledTabs: [UUID: Date] = [:]
    private var allowedDomains: Set<String> = []

    func isTemporarilyDisabled(tabId: UUID) -> Bool {
        if let until = temporarilyDisabledTabs[tabId] {
            if until > Date() { return true }
            temporarilyDisabledTabs.removeValue(forKey: tabId)
        }
        return false
    }

    func disableTemporarily(for tab: Tab, duration: TimeInterval) {
        let until = Date().addingTimeInterval(duration)
        temporarilyDisabledTabs[tab.id] = until
        if let wv = tab.existingWebView {
            removeBlocking(from: wv)
            wv.reloadFromOrigin()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak tab] in
            guard let self, let tab else { return }
            if let exp = self.temporarilyDisabledTabs[tab.id], exp <= Date() {
                self.temporarilyDisabledTabs.removeValue(forKey: tab.id)
                if self.shouldApplyBlocking(to: tab), let wv = tab.existingWebView {
                    self.applyBlocking(to: wv)
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    func allowDomain(_ host: String, allowed: Bool = true) {
        let norm = host.lowercased()
        if allowed { allowedDomains.insert(norm) } else { allowedDomains.remove(norm) }

        // Persist to settings
        browserManager?.nookSettings?.adBlockerWhitelist = Array(allowedDomains)

        if let bm = browserManager {
            for tab in bm.tabManager.allTabs() {
                if tab.existingWebView?.url?.host?.lowercased() == norm, let wv = tab.existingWebView {
                    if allowed { removeBlocking(from: wv) } else { applyBlocking(to: wv) }
                    wv.reloadFromOrigin()
                }
            }
        }
    }

    func isDomainAllowed(_ host: String?) -> Bool {
        guard let h = host?.lowercased() else { return false }
        return allowedDomains.contains(h)
    }

    // MARK: - Lifecycle

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager

        // Hydrate whitelist from persisted settings
        if let whitelist = browserManager.nookSettings?.adBlockerWhitelist {
            allowedDomains = Set(whitelist.map { $0.lowercased() })
        }

        // Hydrate enabled optional filter lists
        if let enabled = browserManager.nookSettings?.enabledOptionalFilterLists {
            filterListManager.enabledOptionalFilterListFilenames = Set(enabled)
        }
    }

    func setEnabled(_ enabled: Bool) {
        cbLog.info("setEnabled(\(enabled)) — current isEnabled=\(self.isEnabled)")
        guard enabled != isEnabled else { return }
        if !enabled {
            // Disable immediately
            isEnabled = false
            deactivateBlocking()
        } else {
            // Enable: don't set isEnabled until activation completes
            // so setupContentBlockerScripts won't run with empty rules
            Task { @MainActor in
                await activateBlocking()
                isEnabled = true
                cbLog.info("Content blocker fully activated")
            }
        }
    }

    // MARK: - Activation

    private func activateBlocking() async {
        isCompiling = true

        // Download filter lists if we have none cached
        if !filterListManager.hasCachedLists {
            await filterListManager.downloadAllLists()
        }

        // Parse all lists on a background thread to avoid blocking UI
        let parsed = await Task.detached(priority: .userInitiated) {
            await self.filterListManager.parseAllCachedLists()
        }.value

        // Compile network rules + global cosmetic rules into WKContentRuleLists
        compiledRuleLists = await ContentRuleListCompiler.compile(
            networkRules: parsed.networkRules,
            cosmeticRules: parsed.cosmeticRules,
            redirectResourceManager: redirectResourceManager
        )

        // Configure scriptlet engine with scriptlet and domain-specific cosmetic rules
        scriptletEngine.configure(
            scriptletRules: parsed.scriptletRules,
            cosmeticRules: parsed.cosmeticRules,
            proceduralCosmeticRules: parsed.proceduralCosmeticRules
        )

        // Store removeparam rules for Swift-layer enforcement
        removeParamRules = parsed.removeParamRules

        // Log YouTube-specific rule counts for debugging
        let ytScriptlets = parsed.scriptletRules.filter { $0.domains.contains(where: { $0.contains("youtube") }) }
        let ytCosmetics = parsed.cosmeticRules.filter { $0.domains.contains(where: { $0.contains("youtube") }) }
        let fbScriptlets = parsed.scriptletRules.filter { $0.domains.contains(where: { $0.contains("facebook") }) }
        cbLog.info("YouTube: \(ytScriptlets.count) scriptlet rules, \(ytCosmetics.count) cosmetic rules")
        cbLog.info("Facebook: \(fbScriptlets.count) scriptlet rules")
        cbLog.info("Total: \(parsed.scriptletRules.count) scriptlets, \(parsed.networkRules.count) network, \(parsed.cosmeticRules.count) cosmetic")

        isCompiling = false

        // Register applicator for new tab controllers
        BrowserConfiguration.shared.contentRuleListApplicator = { [weak self] controller in
            self?.applyRuleLists(to: controller)
        }

        // Apply to shared configuration and existing webviews
        applyToSharedConfiguration()
        applyToExistingWebViews()

        // Post update notification
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)

        // Record initial download timestamp
        if browserManager?.nookSettings?.adBlockerLastUpdate == nil {
            browserManager?.nookSettings?.adBlockerLastUpdate = Date()
        }

        // Schedule periodic filter list updates
        scheduleAutoUpdate()

        cbLog.info("Activated with \(self.compiledRuleLists.count) rule list(s)")
    }

    private func deactivateBlocking() {
        updateTimer?.invalidate()
        updateTimer = nil

        BrowserConfiguration.shared.contentRuleListApplicator = nil

        removeFromSharedConfiguration()
        removeFromExistingWebViews()

        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)

        print("[ContentBlocker] Deactivated")
    }

    // MARK: - Filter List Updates

    /// Update filter lists from remote sources. Returns true if lists were updated and recompiled.
    func updateFilterLists() async -> Bool {
        guard isEnabled else { return false }

        isCompiling = true
        let updated = await filterListManager.downloadAllLists()

        if updated {
            let parsed = filterListManager.parseAllCachedLists()

            compiledRuleLists = await ContentRuleListCompiler.compile(
                networkRules: parsed.networkRules,
                cosmeticRules: parsed.cosmeticRules,
                redirectResourceManager: redirectResourceManager
            )

            scriptletEngine.configure(
                scriptletRules: parsed.scriptletRules,
                cosmeticRules: parsed.cosmeticRules,
                proceduralCosmeticRules: parsed.proceduralCosmeticRules
            )

            removeParamRules = parsed.removeParamRules

            applyToSharedConfiguration()
            applyToExistingWebViews()

            // Record update timestamp
            browserManager?.nookSettings?.adBlockerLastUpdate = Date()

            print("[ContentBlocker] Filter lists updated and recompiled")
        }

        isCompiling = false
        return updated
    }

    /// Force recompile all filter lists (e.g. after enabling/disabling an optional list).
    /// Downloads any missing lists first, then recompiles regardless of whether downloads changed.
    func recompileFilterLists() async {
        guard isEnabled else { return }

        isCompiling = true

        // Download any lists we don't have cached yet (e.g. newly enabled optional list)
        await filterListManager.downloadAllLists()

        // Always recompile
        let parsed = await Task.detached(priority: .userInitiated) {
            self.filterListManager.parseAllCachedLists()
        }.value

        compiledRuleLists = await ContentRuleListCompiler.compile(
            networkRules: parsed.networkRules,
            cosmeticRules: parsed.cosmeticRules,
            redirectResourceManager: redirectResourceManager
        )

        scriptletEngine.configure(
            scriptletRules: parsed.scriptletRules,
            cosmeticRules: parsed.cosmeticRules,
            proceduralCosmeticRules: parsed.proceduralCosmeticRules
        )

        removeParamRules = parsed.removeParamRules

        applyToSharedConfiguration()
        applyToExistingWebViews()

        browserManager?.nookSettings?.adBlockerLastUpdate = Date()
        NotificationCenter.default.post(name: .adBlockerStateChanged, object: nil)

        isCompiling = false
        print("[ContentBlocker] Filter lists recompiled")
    }

    // MARK: - Auto-Update

    private func scheduleAutoUpdate() {
        updateTimer?.invalidate()

        // Check if an update is due now (>24h since last update)
        if let lastUpdate = browserManager?.nookSettings?.adBlockerLastUpdate {
            let elapsed = Date().timeIntervalSince(lastUpdate)
            if elapsed >= Self.updateInterval {
                Task { await updateFilterLists() }
            }
        }

        // Schedule repeating timer for daily checks
        updateTimer = Timer.scheduledTimer(withTimeInterval: Self.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.updateFilterLists()
            }
        }
        updateTimer?.tolerance = 60 * 60  // 1 hour tolerance for energy efficiency
    }

    // MARK: - Per-Navigation Injection

    /// Set up content blocker scripts for a navigation. Called from Tab's decidePolicyFor.
    func setupContentBlockerScripts(for url: URL, in webView: WKWebView, tab: Tab) {
        guard isEnabled else {
            cbLog.warning("setupScripts: SKIPPED — not enabled")
            return
        }
        guard !isDomainAllowed(url.host) else {
            cbLog.warning("setupScripts: SKIPPED — domain \(url.host ?? "nil", privacy: .public) is whitelisted")
            return
        }
        guard !isTemporarilyDisabled(tabId: tab.id) else { return }
        guard !tab.isOAuthFlow else { return }

        let ucc = webView.configuration.userContentController

        // Remove previous content blocker scripts (identified by marker comment)
        let marker = "// Nook Content Blocker"
        let remaining = ucc.userScripts.filter { !$0.source.hasPrefix(marker) }
        if remaining.count != ucc.userScripts.count {
            ucc.removeAllUserScripts()
            remaining.forEach { ucc.addUserScript($0) }
        }

        // Inject scriptlets for this domain (domain-specific + generic/subframe)
        let scriptlets = scriptletEngine.scriptletUserScripts(for: url)
        for script in scriptlets {
            ucc.addUserScript(script)
        }

        // Inject domain-specific cosmetic CSS
        let cosmeticScript = scriptletEngine.cosmeticUserScript(for: url)
        if let cosmeticScript {
            ucc.addUserScript(cosmeticScript)
        }

        // Inject procedural cosmetic filters
        let proceduralScript = scriptletEngine.proceduralCosmeticUserScript(for: url)
        if let proceduralScript {
            ucc.addUserScript(proceduralScript)
        }

        let host = url.host ?? "unknown"
        cbLog.info("setupScripts for \(host, privacy: .public): \(scriptlets.count) scriptlet scripts, cosmetic=\(cosmeticScript != nil), procedural=\(proceduralScript != nil), ruleLists=\(self.compiledRuleLists.count)")
    }

    /// Fallback injection after didFinish — re-inject if scripts didn't take.
    func injectFallbackScripts(for url: URL, in webView: WKWebView, tab: Tab) {
        guard isEnabled else { return }
        guard !isDomainAllowed(url.host) else { return }
        guard !isTemporarilyDisabled(tabId: tab.id) else { return }
        guard !tab.isOAuthFlow else { return }

        // Re-inject cosmetic CSS via evaluateJavaScript as fallback
        if let cosmeticScript = scriptletEngine.cosmeticUserScript(for: url) {
            webView.evaluateJavaScript(cosmeticScript.source) { _, error in
                if let error {
                    print("[ContentBlocker] Fallback cosmetic injection error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Rule List Application (for BrowserConfig)

    /// Apply compiled rule lists to a WKUserContentController.
    /// Called from BrowserConfig.freshUserContentController().
    func applyRuleLists(to controller: WKUserContentController) {
        guard isEnabled else { return }
        for list in compiledRuleLists {
            controller.add(list)
        }
        // Add third-party cookie script
        if !controller.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            controller.addUserScript(thirdPartyCookieScript)
        }
    }

    // MARK: - Shared Configuration

    private func applyToSharedConfiguration() {
        let config = BrowserConfiguration.shared.webViewConfiguration
        let ucc = config.userContentController
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists {
            ucc.add(list)
        }
        if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            ucc.addUserScript(thirdPartyCookieScript)
        }
    }

    private func removeFromSharedConfiguration() {
        let config = BrowserConfiguration.shared.webViewConfiguration
        let ucc = config.userContentController
        ucc.removeAllContentRuleLists()
        let marker = "// Nook Content Blocker"
        let remaining = ucc.userScripts.filter {
            !$0.source.contains("document.referrer") && !$0.source.hasPrefix(marker)
        }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    // MARK: - Per-WebView Helpers

    func shouldApplyBlocking(to tab: Tab) -> Bool {
        if !isEnabled { return false }
        if isTemporarilyDisabled(tabId: tab.id) { return false }
        if isDomainAllowed(tab.existingWebView?.url?.host) { return false }
        if tab.isOAuthFlow { return false }
        return true
    }

    private func applyBlocking(to webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        for list in compiledRuleLists {
            ucc.add(list)
        }
        if !ucc.userScripts.contains(where: { $0.source.contains("document.referrer") }) {
            ucc.addUserScript(thirdPartyCookieScript)
        }
    }

    private func removeBlocking(from webView: WKWebView) {
        let ucc = webView.configuration.userContentController
        ucc.removeAllContentRuleLists()
        let marker = "// Nook Content Blocker"
        let remaining = ucc.userScripts.filter {
            !$0.source.contains("document.referrer") && !$0.source.hasPrefix(marker)
        }
        ucc.removeAllUserScripts()
        remaining.forEach { ucc.addUserScript($0) }
    }

    private func applyToExistingWebViews() {
        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let wv = tab.existingWebView else { continue }
            if shouldApplyBlocking(to: tab) {
                applyBlocking(to: wv)
            } else {
                removeBlocking(from: wv)
            }
        }
    }

    private func removeFromExistingWebViews() {
        guard let bm = browserManager else { return }
        for tab in bm.tabManager.allTabs() {
            guard let wv = tab.existingWebView else { continue }
            removeBlocking(from: wv)
        }
    }

    // MARK: - $removeparam Support

    /// Check if URL has params that should be stripped. Returns cleaned URL if params were removed, nil otherwise.
    func cleanedURL(for url: URL) -> URL? {
        guard !removeParamRules.isEmpty else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else { return nil }

        let urlString = url.absoluteString
        var paramsToRemove: Set<String> = []

        for rule in removeParamRules {
            guard !rule.isException else { continue }

            // Check if URL matches the rule pattern
            if let regex = try? NSRegularExpression(pattern: rule.regex),
               regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
                // This rule applies to this URL
                if rule.paramPattern == "*" {
                    // Remove all params
                    paramsToRemove = Set(queryItems.map { $0.name })
                    break
                }
                // Check each param against the pattern
                if let paramRegex = try? NSRegularExpression(pattern: rule.paramPattern) {
                    for item in queryItems {
                        if paramRegex.firstMatch(in: item.name, range: NSRange(item.name.startIndex..., in: item.name)) != nil {
                            paramsToRemove.insert(item.name)
                        }
                    }
                } else {
                    // Exact match
                    for item in queryItems {
                        if item.name == rule.paramPattern {
                            paramsToRemove.insert(item.name)
                        }
                    }
                }
            }
        }

        // Check exception rules
        for rule in removeParamRules where rule.isException {
            if let regex = try? NSRegularExpression(pattern: rule.regex),
               regex.firstMatch(in: urlString, range: NSRange(urlString.startIndex..., in: urlString)) != nil {
                if rule.paramPattern == "*" {
                    return nil  // Exception for all params
                }
                paramsToRemove.remove(rule.paramPattern)
            }
        }

        guard !paramsToRemove.isEmpty else { return nil }

        let cleaned = queryItems.filter { !paramsToRemove.contains($0.name) }
        components.queryItems = cleaned.isEmpty ? nil : cleaned
        return components.url
    }

    func refreshFor(tab: Tab) {
        guard let wv = tab.existingWebView else { return }
        if shouldApplyBlocking(to: tab) {
            applyBlocking(to: wv)
        } else {
            removeBlocking(from: wv)
        }
        wv.reloadFromOrigin()
    }
}
