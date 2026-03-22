//
//  ScriptletEngine.swift
//  Nook
//
//  Maps domains to matching scriptlet rules. Builds per-navigation JavaScript
//  payloads and creates WKUserScript instances for main-world injection.
//  Also handles domain-specific cosmetic CSS injection.
//

import Foundation
import WebKit
import OSLog

private let seLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ScriptletEngine")

@MainActor
final class ScriptletEngine {

    private var scriptletRules: [ScriptletRule] = []
    private var cosmeticRules: [CosmeticRule] = []
    private var proceduralCosmeticRules: [ProceduralCosmeticRule] = []
    private var scriptletTemplates: [String: String] = [:]

    init() {
        loadScriptletTemplates()
    }

    // MARK: - Configuration

    func configure(scriptletRules: [ScriptletRule], cosmeticRules: [CosmeticRule], proceduralCosmeticRules: [ProceduralCosmeticRule] = []) {
        self.scriptletRules = scriptletRules
        self.cosmeticRules = cosmeticRules
        self.proceduralCosmeticRules = proceduralCosmeticRules
    }

    // MARK: - Per-Navigation Script Generation

    /// Build WKUserScripts for scriptlet injection on the given URL.
    /// Returns up to two scripts:
    /// - Domain-specific scriptlets: main frame only (heavier, performance-sensitive)
    /// - Generic scriptlets (no domain constraint): all frames (catches iframe ads)
    func scriptletUserScripts(for url: URL) -> [WKUserScript] {
        guard let host = url.host?.lowercased() else { return [] }

        // Filter-list scriptlet rules
        let matching = scriptletRules.filter { rule in
            !rule.isException && domainMatches(host: host, domains: rule.domains)
        }

        let exceptions = scriptletRules.filter { rule in
            rule.isException && domainMatches(host: host, domains: rule.domains)
        }

        let active = matching.filter { rule in
            !exceptions.contains { exc in
                exc.name == rule.name && exc.args == rule.args
            }
        }

        // Split into domain-specific (has positive domain constraints) vs generic (empty domains = global)
        let domainSpecific = active.filter { !$0.domains.isEmpty }
        let generic = active.filter { $0.domains.isEmpty }

        var scripts: [WKUserScript] = []

        // Domain-specific: main frame only for performance
        var domainJS = "// Nook Content Blocker Scriptlets for \(host)\n"
        var hasDomainContent = false
        for rule in domainSpecific {
            if let script = buildScriptlet(rule) {
                domainJS += script + "\n"
                hasDomainContent = true
            }
        }
        if hasDomainContent {
            scripts.append(WKUserScript(
                source: domainJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true,
                in: .page
            ))
        }

        // Generic: inject into all frames to catch iframe ads
        var genericJS = "// Nook Content Blocker Generic Scriptlets\n"
        var hasGenericContent = false
        for rule in generic {
            if let script = buildScriptlet(rule) {
                genericJS += script + "\n"
                hasGenericContent = true
            }
        }
        if hasGenericContent {
            scripts.append(WKUserScript(
                source: genericJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false,
                in: .page
            ))
        }

        return scripts
    }

    /// Build a WKUserScript for domain-specific cosmetic CSS hiding.
    /// Returns nil if no cosmetic rules match.
    func cosmeticUserScript(for url: URL) -> WKUserScript? {
        guard let host = url.host?.lowercased() else { return nil }

        // Find domain-specific cosmetic rules
        let matching = cosmeticRules.filter { rule in
            !rule.domains.isEmpty && !rule.isException && domainMatches(host: host, domains: rule.domains)
        }

        // Find exceptions
        let exceptions = cosmeticRules.filter { rule in
            rule.isException && domainMatches(host: host, domains: rule.domains)
        }

        let active = matching.filter { rule in
            !exceptions.contains { exc in exc.selector == rule.selector }
        }

        guard !active.isEmpty else { return nil }

        let selectors = active.map { $0.selector }.joined(separator: ", ")
        let escapedSelectors = selectors
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = """
        // Nook Content Blocker Cosmetics for \(host)
        (function() {
            'use strict';
            const style = document.createElement('style');
            style.textContent = '\(escapedSelectors) { display: none !important; }';
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        return WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    // MARK: - Procedural Cosmetic Injection

    /// Build a WKUserScript for procedural cosmetic filtering on the given URL.
    /// Returns nil if no procedural rules match.
    func proceduralCosmeticUserScript(for url: URL) -> WKUserScript? {
        guard let host = url.host?.lowercased() else { return nil }

        let matching = proceduralCosmeticRules.filter { rule in
            !rule.isException && domainMatches(host: host, domains: rule.domains)
        }

        let exceptions = proceduralCosmeticRules.filter { rule in
            rule.isException && domainMatches(host: host, domains: rule.domains)
        }

        let active = matching.filter { rule in
            !exceptions.contains { exc in exc.selector == rule.selector }
        }

        guard !active.isEmpty else { return nil }

        // Serialize rules to JSON for the runtime
        var rulesJSON: [[String: Any]] = []
        for rule in active {
            var ops: [[String: String]] = []
            for op in rule.operations {
                ops.append(["type": op.type, "arg": op.arg])
            }
            rulesJSON.append([
                "selector": rule.selector,
                "operations": ops
            ])
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rulesJSON, options: []),
              let jsonStr = String(data: data, encoding: .utf8) else { return nil }

        let escapedJSON = jsonStr
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        // Load the procedural cosmetic runtime template
        guard let runtimeTemplate = scriptletTemplates["procedural-cosmetic-runtime"] else {
            // Inline a minimal runtime if the template isn't loaded
            let js = buildInlineProceduralRuntime(rulesJSON: escapedJSON, host: host)
            return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page)
        }

        let js = runtimeTemplate.replacingOccurrences(of: "{{RULES}}", with: escapedJSON)
        return WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page)
    }

    private func buildInlineProceduralRuntime(rulesJSON: String, host: String) -> String {
        return """
        // Nook Content Blocker Procedural Cosmetics for \(host)
        (function() {
            'use strict';
            const rules = JSON.parse('\(rulesJSON)');
            function processRules() {
                for (const rule of rules) {
                    try {
                        let elements = rule.selector === '*' ? [document.documentElement] : Array.from(document.querySelectorAll(rule.selector));
                        for (const op of rule.operations) {
                            elements = applyOp(elements, op);
                        }
                    } catch(e) {}
                }
            }
            function applyOp(elements, op) {
                const result = [];
                for (const el of elements) {
                    try {
                        switch(op.type) {
                            case 'has-text': {
                                let re; try { re = new RegExp(op.arg); } catch(e) { re = { test: s => s.includes(op.arg) }; }
                                if (re.test(el.textContent || '')) { el.style.setProperty('display', 'none', 'important'); }
                                break;
                            }
                            case 'xpath': {
                                const xr = document.evaluate(op.arg, el, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
                                for (let i = 0; i < xr.snapshotLength; i++) {
                                    const n = xr.snapshotItem(i);
                                    if (n instanceof HTMLElement) { n.style.setProperty('display', 'none', 'important'); result.push(n); }
                                }
                                continue;
                            }
                            case 'style': {
                                const decls = op.arg.split(';');
                                for (const d of decls) { const [p,v] = d.split(':').map(s=>s.trim()); if (p && v) el.style.setProperty(p, v, 'important'); }
                                break;
                            }
                            case 'upward': {
                                const n = parseInt(op.arg, 10);
                                let target = el;
                                if (!isNaN(n)) { for (let i = 0; i < n && target; i++) target = target.parentElement; }
                                else { target = el.closest(op.arg); }
                                if (target) { target.style.setProperty('display', 'none', 'important'); result.push(target); }
                                continue;
                            }
                            case 'remove': { el.remove(); continue; }
                            case 'remove-attr': { el.removeAttribute(op.arg); break; }
                            case 'remove-class': { el.classList.remove(op.arg); break; }
                            case 'matches-css': {
                                const [prop, val] = op.arg.split(':').map(s => s.trim());
                                const computed = getComputedStyle(el)[prop];
                                let valRe; try { valRe = new RegExp(val); } catch(e) { valRe = { test: s => s === val }; }
                                if (valRe.test(computed)) { el.style.setProperty('display', 'none', 'important'); }
                                break;
                            }
                            case 'min-text-length': {
                                if ((el.textContent || '').length >= parseInt(op.arg, 10)) { el.style.setProperty('display', 'none', 'important'); }
                                break;
                            }
                            case 'matches-attr': {
                                const [attr, val] = op.arg.split('=');
                                const attrVal = el.getAttribute(attr);
                                if (attrVal !== null) {
                                    if (!val || attrVal === val) { el.style.setProperty('display', 'none', 'important'); }
                                    else { try { if (new RegExp(val).test(attrVal)) el.style.setProperty('display', 'none', 'important'); } catch(e) {} }
                                }
                                break;
                            }
                            case 'matches-path': {
                                let re; try { re = new RegExp(op.arg); } catch(e) { re = { test: s => s.includes(op.arg) }; }
                                if (!re.test(location.pathname)) continue;
                                el.style.setProperty('display', 'none', 'important');
                                break;
                            }
                            case 'others': {
                                const parent = el.parentElement;
                                if (parent) { for (const sibling of parent.children) { if (sibling !== el) sibling.style.setProperty('display', 'none', 'important'); } }
                                break;
                            }
                            default: break;
                        }
                        result.push(el);
                    } catch(e) {}
                }
                return result;
            }
            processRules();
            const observer = new MutationObserver(processRules);
            observer.observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
    }

    // MARK: - Private

    /// uBlock Origin alias → full scriptlet name mapping (all known aliases)
    private static let aliasMap: [String: String] = [
        // Core blocking
        "aopr": "abort-on-property-read",
        "abort-on-property-read": "abort-on-property-read",
        "aopw": "abort-on-property-write",
        "abort-on-property-write": "abort-on-property-write",
        "acs": "abort-current-script",
        "abort-current-script": "abort-current-script",
        "aost": "abort-on-stack-trace",
        "abort-on-stack-trace": "abort-on-stack-trace",
        // Constants & properties
        "set": "set-constant",
        "set-constant": "set-constant",
        "trusted-set": "trusted-set",
        "set-attr": "set-attr",
        // DOM manipulation
        "ra": "remove-attr",
        "remove-attr": "remove-attr",
        "rc": "remove-class",
        "remove-class": "remove-class",
        "rmnt": "remove-node-text",
        "remove-node-text": "remove-node-text",
        "rpnt": "replace-node-text",
        "replace-node-text": "replace-node-text",
        "trusted-rpnt": "replace-node-text",
        "trusted-replace-node-text": "replace-node-text",
        // Timer defusers
        "nostif": "no-setTimeout-if",
        "no-setTimeout-if": "no-setTimeout-if",
        "nosiif": "no-setInterval-if",
        "no-setInterval-if": "no-setInterval-if",
        "nano-stb": "nano-stb",
        "nano-sib": "nano-stb",
        // Event/window defusers
        "nowoif": "no-window-open-if",
        "no-window-open-if": "no-window-open-if",
        "aeld": "addEventListener-defuser",
        "addEventListener-defuser": "addEventListener-defuser",
        "norafif": "no-requestAnimationFrame-if",
        "no-requestAnimationFrame-if": "no-requestAnimationFrame-if",
        // Network interception
        "json-prune": "json-prune",
        "no-fetch-if": "no-fetch-if",
        "no-xhr-if": "no-xhr-if",
        "json-prune-fetch-response": "json-prune-fetch-response",
        "json-prune-xhr-response": "json-prune-xhr-response",
        "json-edit-fetch-response": "json-edit-fetch-response",
        // Phase 0: YouTube-critical
        "m3u-prune": "m3u-prune",
        "xml-prune": "xml-prune",
        "trusted-prevent-dom-bypass": "trusted-prevent-dom-bypass",
        "trusted-suppress-native-method": "trusted-suppress-native-method",
        "trusted-json-edit-xhr-request": "trusted-json-edit-xhr-request",
        "trusted-json-edit-xhr-response": "trusted-json-edit-xhr-response",
        "trusted-replace-fetch-response": "trusted-replace-fetch-response",
        "trusted-replace-xhr-response": "trusted-replace-xhr-response",
        "trusted-replace-argument": "trusted-replace-argument",
        // URL/link manipulation
        "href-sanitizer": "href-sanitizer",
        "disable-newtab-links": "disable-newtab-links",
        "refresh-defuser": "refresh-defuser",
        // Cookies & storage
        "remove-cookie": "remove-cookie",
        "cookie-remover": "remove-cookie",
        "set-cookie": "set-cookie",
        "set-local-storage-item": "set-local-storage-item",
        "set-session-storage-item": "set-session-storage-item",
        // Eval/script blocking
        "noeval": "noeval-if",
        "noeval-if": "noeval-if",
        // Anti-adblock neutralizers
        "popads-dummy": "popads-dummy",
        "popads.net": "popads-dummy",
        "nobab": "nobab",
        "nofab": "nofab",
        "fingerprint2": "fingerprint2",
        // WebRTC
        "nowebrtc": "nowebrtc",
        // Beacon blocking
        "no-beacon-if": "no-beacon-if",
        // MutationObserver auto-clicker
        "observer-click": "observer-click",
        // Property interception + pruning
        "define-property-prune": "define-property-prune",
        // Phase 1: General-purpose
        "alert-buster": "alert-buster",
        "call-nothrow": "call-nothrow",
        "close-window": "close-window",
        "evaldata-prune": "evaldata-prune",
        "noeval-silent": "noeval-silent",
        "silent-noeval": "noeval-silent",
        "prevent-eval-if": "noeval-if",
        "no-floc": "no-floc",
        "overlay-buster": "overlay-buster",
        "prevent-canvas": "prevent-canvas",
        "no-canvas": "prevent-canvas",
        "prevent-dialog": "prevent-dialog",
        "prevent-innerHTML": "prevent-innerHTML",
        "prevent-navigation": "prevent-navigation",
        "prevent-textContent": "prevent-textContent",
        "remove-cache-storage-item": "remove-cache-storage-item",
        "set-cookie-reload": "set-cookie-reload",
        "spoof-css": "spoof-css",
        "webrtc-if": "webrtc-if",
        "window-name-defuser": "window-name-defuser",
        "window.name-defuser": "window-name-defuser",
        "prevent-fetch": "no-fetch-if",
        "prevent-xhr": "no-xhr-if",
        // Phase 2: Trusted + JSON-edit
        "trusted-click-element": "trusted-click-element",
        "trusted-create-html": "trusted-create-html",
        "trusted-edit-inbound-object": "trusted-edit-inbound-object",
        "trusted-edit-outbound-object": "trusted-edit-outbound-object",
        "trusted-json-edit": "trusted-json-edit",
        "trusted-json-edit-fetch-request": "trusted-json-edit-fetch-request",
        "trusted-json-edit-fetch-response": "trusted-json-edit-fetch-response",
        "trusted-jsonl-edit-fetch-response": "trusted-jsonl-edit-fetch-response",
        "trusted-jsonl-edit-xhr-response": "trusted-jsonl-edit-xhr-response",
        "trusted-override-element-method": "trusted-override-element-method",
        "trusted-prevent-fetch": "trusted-prevent-fetch",
        "trusted-prevent-xhr": "trusted-prevent-xhr",
        "trusted-prune-inbound-object": "trusted-prune-inbound-object",
        "trusted-prune-outbound-object": "trusted-prune-outbound-object",
        "trusted-replace-outbound-text": "trusted-replace-outbound-text",
        "trusted-rpot": "trusted-replace-outbound-text",
        "trusted-set-attr": "trusted-set-attr",
        "trusted-set-cookie": "trusted-set-cookie",
        "trusted-set-cookie-reload": "trusted-set-cookie-reload",
        "trusted-set-local-storage-item": "trusted-set-local-storage-item",
        "trusted-set-session-storage-item": "trusted-set-session-storage-item",
        "trusted-rpfr": "trusted-replace-fetch-response",
        "edit-outbound-object": "edit-outbound-object",
        "edit-inbound-object": "edit-inbound-object",
        "json-edit": "json-edit",
        "json-edit-xhr-response": "json-edit-xhr-response",
        "json-edit-xhr-request": "json-edit-xhr-request",
        "json-edit-fetch-request": "json-edit-fetch-request",
        "jsonl-edit-xhr-response": "jsonl-edit-xhr-response",
        "jsonl-edit-fetch-response": "jsonl-edit-fetch-response",
    ]

    private func loadScriptletTemplates() {
        let scriptletNames = [
            "json-prune", "no-fetch-if", "set-constant",
            "abort-on-property-read", "abort-on-property-write", "abort-current-script",
            "abort-on-stack-trace", "remove-attr", "remove-class", "remove-node-text",
            "replace-node-text", "no-xhr-if", "nano-stb",
            "no-setTimeout-if", "no-setInterval-if", "no-window-open-if",
            "addEventListener-defuser", "no-requestAnimationFrame-if",
            "json-prune-fetch-response", "trusted-replace-fetch-response",
            "trusted-replace-xhr-response", "trusted-replace-argument",
            "href-sanitizer", "disable-newtab-links", "refresh-defuser",
            "remove-cookie", "set-cookie", "set-local-storage-item",
            "set-session-storage-item", "noeval-if", "set-attr", "trusted-set",
            "popads-dummy", "nobab", "nofab", "fingerprint2", "nowebrtc",
            "no-beacon-if", "observer-click", "define-property-prune",
            // Phase 0: YouTube-critical
            "json-prune-xhr-response", "m3u-prune", "xml-prune",
            "trusted-prevent-dom-bypass", "trusted-suppress-native-method",
            "trusted-json-edit-xhr-request", "trusted-json-edit-xhr-response",
            // Phase 1: General-purpose
            "alert-buster", "call-nothrow", "close-window", "evaldata-prune",
            "noeval-silent", "no-floc", "overlay-buster", "prevent-canvas",
            "prevent-dialog", "prevent-innerHTML", "prevent-navigation",
            "prevent-textContent", "remove-cache-storage-item", "set-cookie-reload",
            "spoof-css", "webrtc-if", "window-name-defuser",
            // Phase 2: Trusted scriptlets
            "trusted-click-element", "trusted-create-html",
            "trusted-edit-inbound-object", "trusted-edit-outbound-object",
            "trusted-json-edit", "trusted-json-edit-fetch-request",
            "trusted-json-edit-fetch-response", "trusted-jsonl-edit-fetch-response",
            "trusted-jsonl-edit-xhr-response", "trusted-override-element-method",
            "trusted-prevent-fetch", "trusted-prevent-xhr",
            "trusted-prune-inbound-object", "trusted-prune-outbound-object",
            "trusted-replace-outbound-text", "trusted-set-attr",
            "trusted-set-cookie", "trusted-set-cookie-reload",
            "trusted-set-local-storage-item", "trusted-set-session-storage-item",
            // Phase 2: Non-trusted JSON/object edit scriptlets
            "edit-outbound-object", "edit-inbound-object", "json-edit",
            "json-edit-xhr-response", "json-edit-xhr-request",
            "json-edit-fetch-response", "json-edit-fetch-request",
            "jsonl-edit-xhr-response", "jsonl-edit-fetch-response",
            // Phase 5: removeparam engine + procedural cosmetic runtime
            "removeparam-engine", "procedural-cosmetic-runtime",
        ]

        for name in scriptletNames {
            if let path = Bundle.main.path(forResource: name, ofType: "js"),
               let content = try? String(contentsOfFile: path, encoding: .utf8) {
                scriptletTemplates[name] = content
            } else {
                seLog.warning("Missing scriptlet template: \(name, privacy: .public).js")
            }
        }

        seLog.info("Loaded \(self.scriptletTemplates.count)/\(scriptletNames.count) scriptlet templates")
    }

    private func buildScriptlet(_ rule: ScriptletRule) -> String? {
        // Resolve alias to canonical name
        let canonicalName = Self.aliasMap[rule.name] ?? rule.name
        guard let template = scriptletTemplates[canonicalName] else {
            seLog.warning("Missing template for '\(rule.name, privacy: .public)' (resolved: '\(canonicalName, privacy: .public)')")
            return nil
        }

        // Encode args as JSON array for safe injection
        guard let argsData = try? JSONSerialization.data(withJSONObject: rule.args, options: []),
              let argsJSON = String(data: argsData, encoding: .utf8) else {
            return nil
        }

        // Escape for embedding in a JS single-quoted string that feeds JSON.parse().
        // Backslashes must be doubled so they survive: JS string literal → JSON.parse.
        let escapedArgs = argsJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")

        return template.replacingOccurrences(of: "{{ARGS}}", with: escapedArgs)
    }

    private func domainMatches(host: String, domains: [String]) -> Bool {
        // Empty domains means "all domains"
        if domains.isEmpty { return true }

        for domain in domains {
            let d = domain.lowercased()
            if d.hasPrefix("~") {
                // Negated domain — if host matches, rule does NOT apply
                let negated = String(d.dropFirst())
                if host == negated || host.hasSuffix("." + negated) {
                    return false
                }
            }
        }

        // Check positive domains
        let positiveDomains = domains.filter { !$0.hasPrefix("~") }
        if positiveDomains.isEmpty { return true } // Only negations → applies everywhere except negated

        for domain in positiveDomains {
            let d = domain.lowercased()
            if host == d || host.hasSuffix("." + d) {
                return true
            }
        }

        return false
    }
}
