//
//  ContentRuleListCompiler.swift
//  Nook
//
//  Uses SafariConverterLib to convert AdGuard/uBlock filter rules into
//  WKContentRuleList JSON and advanced rules text for scriptlet/CSS injection.
//  Compiles JSON via WKContentRuleListStore in chunks.
//

import Foundation
import WebKit
import OSLog
import ContentBlockerConverter

private let cbLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

@MainActor
final class ContentRuleListCompiler {

    private static let chunkSize = 30_000
    private static let storeIdentifierPrefix = "NookAdBlocker"

    struct CompilationResult {
        let ruleLists: [WKContentRuleList]
        let advancedRulesText: String?
    }

    // MARK: - Public API

    /// Compile filter rules via SafariConverterLib.
    /// Returns WKContentRuleLists for network blocking + advancedRulesText for scriptlet/CSS injection.
    static func compile(rules: [String]) async -> CompilationResult {
        guard let store = WKContentRuleListStore.default() else {
            cbLog.error("No WKContentRuleListStore available")
            return CompilationResult(ruleLists: [], advancedRulesText: nil)
        }

        let converter = ContentBlockerConverter()
        let conversionResult = converter.convertArray(
            rules: rules,
            safariVersion: SafariVersion.autodetect(),
            advancedBlocking: true
        )

        cbLog.info("SafariConverterLib: \(conversionResult.sourceRulesCount) source, \(conversionResult.safariRulesCount) safari, \(conversionResult.advancedRulesCount) advanced, \(conversionResult.errorsCount) errors")

        // Parse SafariConverterLib JSON output back into array for chunking
        var jsonEntries: [[String: Any]] = []

        if let data = conversionResult.safariRulesJSON.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            jsonEntries = parsed
        } else {
            cbLog.error("Failed to parse SafariConverterLib JSON output")
        }

        // Prepend built-in YouTube rules
        jsonEntries.insert(contentsOf: youTubeNetworkRules(), at: 0)

        // Remove old rule lists
        await removeOldRuleLists(store: store)

        // Compile in chunks
        let chunks = stride(from: 0, to: jsonEntries.count, by: chunkSize).map { start in
            Array(jsonEntries[start..<min(start + chunkSize, jsonEntries.count)])
        }

        var compiled: [WKContentRuleList] = []
        for (index, chunk) in chunks.enumerated() {
            let identifier = "\(storeIdentifierPrefix)_\(index)"
            if let list = await compileChunk(chunk, identifier: identifier, store: store) {
                compiled.append(list)
            } else {
                cbLog.info("Retrying chunk \(index) as two halves")
                let half = chunk.count / 2
                if let r1 = await compileChunk(Array(chunk[0..<half]), identifier: "\(identifier)a", store: store) {
                    compiled.append(r1)
                }
                if let r2 = await compileChunk(Array(chunk[half...]), identifier: "\(identifier)b", store: store) {
                    compiled.append(r2)
                }
            }
        }

        cbLog.info("Compiled \(compiled.count) rule list(s) from \(jsonEntries.count) entries")

        return CompilationResult(
            ruleLists: compiled,
            advancedRulesText: conversionResult.advancedRulesText
        )
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

    private static func compileChunk(
        _ rules: [[String: Any]],
        identifier: String,
        store: WKContentRuleListStore
    ) async -> WKContentRuleList? {
        guard let data = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let json = String(data: data, encoding: .utf8) else {
            cbLog.error("Failed to serialize chunk \(identifier, privacy: .public)")
            return nil
        }

        return await withCheckedContinuation { (cont: CheckedContinuation<WKContentRuleList?, Never>) in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let error {
                    cbLog.error("Compile error for \(identifier, privacy: .public) (\(rules.count) rules): \(error.localizedDescription, privacy: .public)")
                }
                cont.resume(returning: list)
            }
        }
    }

    // MARK: - Built-in YouTube Rules

    private static func youTubeNetworkRules() -> [[String: Any]] {
        let ytDomain = ["*youtube.com", "*youtu.be"]
        return [
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
            ["trigger": ["url-filter": ".*", "if-domain": ytDomain] as [String: Any],
             "action": ["type": "css-display-none",
                        "selector": "ytd-ad-slot-renderer, ytd-in-feed-ad-layout-renderer, ytd-banner-promo-renderer, ytd-promoted-sparkles-web-renderer, ytd-promoted-video-renderer, #masthead-ad, #player-ads, .video-ads, ytd-rich-item-renderer:has(ytd-ad-slot-renderer)"] as [String: Any]],
        ]
    }
}
