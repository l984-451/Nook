//
//  ContentRuleListCompiler.swift
//  Nook
//
//  Converts parsed NetworkRule and global CosmeticRule arrays into
//  WKContentRuleList JSON, compiles via WKContentRuleListStore in chunks.
//

import Foundation
import WebKit
import OSLog

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
final class ContentRuleListCompiler {

    private static let chunkSize = 30_000
    private static let storeIdentifierPrefix = "NookAdBlocker"

    // MARK: - Public API

    /// Compile network rules + global cosmetic rules into WKContentRuleLists.
    /// Returns compiled rule lists ready for installation.
    static func compile(
        networkRules: [NetworkRule],
        cosmeticRules: [CosmeticRule]
    ) async -> [WKContentRuleList] {
        guard let store = WKContentRuleListStore.default() else {
            print("[ContentBlocker] No WKContentRuleListStore available")
            return []
        }

        // Build JSON entries
        var jsonEntries: [[String: Any]] = []

        // Built-in YouTube ad network blocking rules
        jsonEntries.append(contentsOf: youTubeNetworkRules())

        // $badfilter reconciliation: remove rules that are negated by $badfilter rules
        let (activeRules, _) = reconcileBadFilters(networkRules)

        // Separate rules by priority for $important ordering
        var normalRules: [[String: Any]] = []
        var exceptionRules: [[String: Any]] = []
        var importantRules: [[String: Any]] = []

        for rule in activeRules {
            // Skip removeparam rules (handled separately)
            if rule.removeparam != nil { continue }
            // Skip $redirect rules — WKContentRuleList doesn't support redirect action.
            // Blocking these requests breaks pages that expect the scripts to exist.
            // Redirect surrogates are handled by scriptlet injection instead.
            if rule.redirectResource != nil { continue }

            if let entry = networkRuleToJSON(rule) {
                if rule.isImportant && !rule.isException {
                    importantRules.append(entry)
                } else if rule.isException {
                    exceptionRules.append(entry)
                } else {
                    normalRules.append(entry)
                }
            }
        }

        // WKContentRuleList applies last-match-wins.
        // Order: normal blocking → exceptions → $important (so $important overrides exceptions)
        jsonEntries.append(contentsOf: normalRules)
        jsonEntries.append(contentsOf: exceptionRules)
        jsonEntries.append(contentsOf: importantRules)

        // Global cosmetic rules (domain-specific cosmetics are handled by AdvancedBlockingEngine)
        let globalCosmetics = cosmeticRules.filter { $0.domains.isEmpty && !$0.isException }
        let cosmeticBatches = batchCosmeticSelectors(globalCosmetics, batchSize: 500)
        for batch in cosmeticBatches {
            jsonEntries.append([
                "trigger": ["url-filter": ".*"] as [String: Any],
                "action": [
                    "type": "css-display-none",
                    "selector": batch
                ] as [String: Any]
            ])
        }

        // Pre-validate: strip rules with url-filters that WebKit will reject
        let validEntries = jsonEntries.filter { entry in
            guard let trigger = entry["trigger"] as? [String: Any],
                  let urlFilter = trigger["url-filter"] as? String else { return false }
            return isRegexSupportedByWebKit(urlFilter)
        }

        let skipped = jsonEntries.count - validEntries.count
        cbLog.info("Total JSON entries: \(jsonEntries.count), valid: \(validEntries.count), skipped: \(skipped)")

        // Remove old rule lists
        await removeOldRuleLists(store: store)

        // Compile in chunks — no binary search, bad rules already removed
        let chunks = stride(from: 0, to: validEntries.count, by: chunkSize).map { start in
            Array(validEntries[start..<min(start + chunkSize, validEntries.count)])
        }

        var compiled: [WKContentRuleList] = []
        for (index, chunk) in chunks.enumerated() {
            let identifier = "\(storeIdentifierPrefix)_\(index)"
            if let list = await compileChunkSimple(chunk, identifier: identifier, store: store) {
                compiled.append(list)
            } else {
                // Chunk failed — split in half and try each half (one level only, no recursion)
                cbLog.info("Retrying chunk \(index) as two halves")
                let half = chunk.count / 2
                if let r1 = await compileChunkSimple(Array(chunk[0..<half]), identifier: "\(identifier)a", store: store) {
                    compiled.append(r1)
                }
                if let r2 = await compileChunkSimple(Array(chunk[half...]), identifier: "\(identifier)b", store: store) {
                    compiled.append(r2)
                }
            }
        }

        cbLog.info("Compiled \(compiled.count) rule list(s) from \(chunks.count) chunks")
        return compiled
    }

    /// Remove all previously compiled rule lists from the store.
    static func removeAll() async {
        guard let store = WKContentRuleListStore.default() else { return }
        await removeOldRuleLists(store: store)
    }

    // MARK: - Private

    private static func removeOldRuleLists(store: WKContentRuleListStore) async {
        let identifiers = await withCheckedContinuation { (cont: CheckedContinuation<[String]?, Never>) in
            store.getAvailableContentRuleListIdentifiers { ids in
                cont.resume(returning: ids)
            }
        }

        guard let ids = identifiers else { return }

        for id in ids where id.hasPrefix(storeIdentifierPrefix) {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                store.removeContentRuleList(forIdentifier: id) { _ in
                    cont.resume()
                }
            }
        }
    }

    /// Simple chunk compilation — no binary search. Rules are pre-validated.
    private static func compileChunkSimple(
        _ rules: [[String: Any]],
        identifier: String,
        store: WKContentRuleListStore
    ) async -> WKContentRuleList? {
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            cbLog.error("Failed to serialize chunk \(identifier, privacy: .public)")
            return nil
        }

        let result = await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let error {
                    cbLog.error("Compile error for \(identifier, privacy: .public) (\(rules.count) rules): \(error.localizedDescription, privacy: .public)")
                }
                cont.resume(returning: list)
            }
        }

        return result
    }

    // MARK: - Regex Validation

    /// Check if a url-filter regex is supported by WebKit's content rule list compiler.
    /// WebKit supports: character classes [], groups (), quantifiers ?, *, +, anchors ^$
    /// WebKit does NOT support: alternation |, backreferences \1, lookahead/behind (?=
    /// quantifier braces {n,m}, or non-capturing groups (?:
    private static func isRegexSupportedByWebKit(_ regex: String) -> Bool {
        // Empty or trivially matching-everything patterns
        if regex.isEmpty { return false }

        // Walk the string respecting character classes [...]
        var inCharClass = false
        var prevChar: Character = "\0"
        for ch in regex {
            if ch == "[" && prevChar != "\\" {
                inCharClass = true
            } else if ch == "]" && prevChar != "\\" {
                inCharClass = false
            } else if !inCharClass {
                // Alternation not supported outside character classes
                if ch == "|" { return false }
                // Quantifier braces {n,m} not supported
                if ch == "{" && prevChar != "\\" { return false }
            }
            prevChar = ch
        }

        // Reject lookahead/lookbehind (?= (?! (?<= (?<!
        // But allow non-capturing groups (?:  — actually WebKit doesn't support those either
        if regex.contains("(?") { return false }

        // Reject backreferences \1 through \9
        for i in 1...9 {
            if regex.contains("\\\(i)") { return false }
        }

        // Reject patterns that are too long (WebKit has internal limits)
        if regex.count > 1024 { return false }

        // Safety: reject patterns that contain leaked filter options
        // (indicates a parser bug where $options weren't separated from the pattern)
        let leakedOptions = ["$script", "$image", "$stylesheet", "$xmlhttprequest",
                             "$third-party", "$domain=", "$redirect", "$important",
                             "$1p", "$3p", "$media", "$popup"]
        for opt in leakedOptions {
            if regex.contains(opt) { return false }
        }

        return true
    }

    // MARK: - JSON Conversion

    private static func networkRuleToJSON(_ rule: NetworkRule) -> [String: Any]? {
        // Skip rules with regex patterns unsupported by WebKit's compiler
        if !isRegexSupportedByWebKit(rule.regex) { return nil }

        // Double-check: verify the regex is actually valid
        if (try? NSRegularExpression(pattern: rule.regex)) == nil { return nil }

        var trigger: [String: Any] = ["url-filter": rule.regex]

        if rule.isThirdParty {
            trigger["load-type"] = ["third-party"]
        } else if rule.isFirstParty {
            trigger["load-type"] = ["first-party"]
        }

        if let types = rule.resourceTypes, !types.isEmpty {
            trigger["resource-type"] = types
        }

        if let domains = rule.domains {
            if !domains.ifDomains.isEmpty {
                trigger["if-domain"] = domains.ifDomains.map { "*\($0)" }
            }
            var unlessDomains = domains.unlessDomains
            // Incorporate $denyallow domains as unless-domain
            if let denyallow = rule.denyallowDomains {
                unlessDomains.append(contentsOf: denyallow)
            }
            if !unlessDomains.isEmpty {
                trigger["unless-domain"] = unlessDomains.map { "*\($0)" }
            }
        } else if let denyallow = rule.denyallowDomains, !denyallow.isEmpty {
            trigger["unless-domain"] = denyallow.map { "*\($0)" }
        }

        let action: [String: Any]
        if rule.isException {
            action = ["type": "ignore-previous-rules"]
        } else {
            // Note: WKContentRuleList doesn't support "redirect" action type.
            // $redirect rules are handled via scriptlet injection instead.
            // Here we just block the request; the redirect resource manager provides
            // surrogate scripts that are injected separately.
            action = ["type": "block"]
        }

        return ["trigger": trigger, "action": action]
    }

    // MARK: - $badfilter Reconciliation

    /// Remove rules negated by $badfilter rules. Returns active rules and count of removed.
    private static func reconcileBadFilters(_ rules: [NetworkRule]) -> ([NetworkRule], Int) {
        let badFilters = rules.filter { $0.isBadFilter }
        guard !badFilters.isEmpty else { return (rules.filter { !$0.isBadFilter }, 0) }

        // Build a set of patterns to negate
        let badPatterns = Set(badFilters.map { $0.pattern })

        var active: [NetworkRule] = []
        var removedCount = 0
        for rule in rules {
            if rule.isBadFilter { continue }
            if badPatterns.contains(rule.pattern) {
                removedCount += 1
                continue
            }
            active.append(rule)
        }
        return (active, removedCount)
    }

    // MARK: - Built-in YouTube Rules

    private static func youTubeNetworkRules() -> [[String: Any]] {
        let ytDomain = ["*youtube.com", "*youtu.be"]
        return [
            // Block YouTube ad-serving endpoints
            ["trigger": ["url-filter": "googlevideo\\.com/initplayback.*adsp", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/pagead/", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/api/stats/ads", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/get_midroll_info", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "doubleclick\\.net", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "googleadservices\\.com", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "/youtubei/v1/player/ad_break", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            ["trigger": ["url-filter": "youtube\\.com/ptracking", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "block"] as [String: Any]],
            // Hide ad elements via CSS
            ["trigger": ["url-filter": ".*", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "css-display-none",
                        "selector": "ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, ytd-promoted-sparkles-web-renderer, ytd-promoted-video-renderer, #masthead-ad, #player-ads, .video-ads, ytd-rich-item-renderer:has(ytd-ad-slot-renderer)"] as [String: Any]],
        ]
    }

    /// Batch cosmetic selectors into comma-separated groups for efficiency.
    private static func batchCosmeticSelectors(_ rules: [CosmeticRule], batchSize: Int) -> [String] {
        var batches: [String] = []
        var current: [String] = []

        for rule in rules {
            current.append(rule.selector)
            if current.count >= batchSize {
                batches.append(current.joined(separator: ", "))
                current.removeAll()
            }
        }

        if !current.isEmpty {
            batches.append(current.joined(separator: ", "))
        }

        return batches
    }
}
