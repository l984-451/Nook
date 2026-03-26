//
//  SiteRoutingManager.swift
//  Nook
//

import Foundation
import OSLog

@MainActor
class SiteRoutingManager {
    private let logger = Logger(subsystem: "com.baingurley.nook", category: "SiteRouting")

    weak var settingsService: NookSettingsService?
    weak var browserManager: BrowserManager?

    // MARK: - Matching

    func resolve(url: URL) -> SiteRoutingRule? {
        guard let settingsService,
              let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        else { return nil }

        let rules = settingsService.siteRoutingRules.filter { $0.isEnabled && $0.domain == host }
        guard !rules.isEmpty else { return nil }

        let path = url.path
        if let specific = rules.first(where: { prefix in
            guard let pp = prefix.pathPrefix, !pp.isEmpty else { return false }
            return path.hasPrefix(pp)
        }) {
            return specific
        }
        return rules.first(where: { $0.pathPrefix == nil || $0.pathPrefix?.isEmpty == true })
    }

    func applyRoute(url: URL, from sourceTab: Tab?) -> Bool {
        guard let browserManager else { return false }

        // Don't route in incognito/ephemeral windows
        if let tab = sourceTab, tab.resolveProfile()?.isEphemeral == true {
            return false
        }
        // For external URLs (no source tab), check if active window is incognito
        if sourceTab == nil,
           let activeWindow = browserManager.windowRegistry?.activeWindow,
           activeWindow.isIncognito {
            return false
        }

        guard let rule = resolve(url: url) else { return false }

        let tabManager = browserManager.tabManager

        guard let targetSpace = tabManager.spaces.first(where: { $0.id == rule.targetSpaceId }),
              browserManager.profileManager.profiles.first(where: { $0.id == rule.targetProfileId }) != nil
        else {
            logger.debug("Route skipped: target space or profile no longer exists for rule \(rule.id)")
            return false
        }

        if tabManager.currentSpace?.id == targetSpace.id {
            return false
        }

        logger.info("Route matched: \(url.absoluteString, privacy: .public) → space '\(targetSpace.name, privacy: .public)'")

        Task { @MainActor in
            if let currentProfile = browserManager.currentProfile,
               currentProfile.id != rule.targetProfileId,
               let targetProfile = browserManager.profileManager.profiles.first(where: { $0.id == rule.targetProfileId }) {
                await browserManager.switchToProfile(targetProfile, context: .spaceChange)
            }

            tabManager.setActiveSpace(targetSpace)
            let _ = tabManager.createNewTab(url: url.absoluteString, in: targetSpace)
        }

        return true
    }

    // MARK: - CRUD

    func addRule(_ rule: SiteRoutingRule) {
        settingsService?.siteRoutingRules.append(rule)
    }

    func updateRule(_ rule: SiteRoutingRule) {
        guard let index = settingsService?.siteRoutingRules.firstIndex(where: { $0.id == rule.id }) else { return }
        settingsService?.siteRoutingRules[index] = rule
    }

    func deleteRule(id: UUID) {
        settingsService?.siteRoutingRules.removeAll(where: { $0.id == id })
    }

    func rules() -> [SiteRoutingRule] {
        settingsService?.siteRoutingRules ?? []
    }
}
