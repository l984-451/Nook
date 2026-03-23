//
//  TabOrganizationPrompt.swift
//  Nook
//
//  Builds structured prompts from tab metadata for LLM-based tab organization.
//  Uses integer indices so the model output maps directly back to tabs.
//

import Foundation

// MARK: - TabInput

/// Pairs a tab with a stable integer index for prompt construction and result mapping.
struct TabInput {
    let index: Int
    let tab: Tab
}

// MARK: - TabOrganizationPrompt

/// Builds system + user prompts that instruct a local LLM to organize browser tabs.
enum TabOrganizationPrompt {

    /// Maximum number of tabs we send in a single prompt to stay within context limits.
    static let maxTabs = 60

    /// A prompt pair suitable for chat-template usage (separate system and user messages).
    struct Prompt {
        let system: String
        let user: String
    }

    // MARK: - Public

    /// Build a prompt pair from the given tabs, space name, and any existing folder names.
    ///
    /// - Parameters:
    ///   - tabs: The tabs to organize, each paired with a stable integer index.
    ///   - spaceName: Name of the space the tabs belong to.
    ///   - existingFolderNames: Names of folders that already exist in this space (used as context).
    /// - Returns: A ``Prompt`` with separate system and user strings.
    @MainActor
    static func build(
        tabs: [TabInput],
        spaceName: String,
        existingFolderNames: [String]
    ) -> Prompt {
        let system = buildSystem()
        let user = buildUser(tabs: tabs, spaceName: spaceName, existingFolderNames: existingFolderNames)
        return Prompt(system: system, user: user)
    }

    // MARK: - Private

    private static func buildSystem() -> String {
        """
        You organize browser tabs. Given a numbered list of tabs, output JSON with this exact schema:
        {"groups":[{"name":"short name","tabs":[1,2,5]}],"renames":[{"tab":1,"name":"shorter name"}],"sort":[3,1,2,5,4],"duplicates":[{"keep":1,"close":[3]}]}

        Rules:
        - Group by topic/purpose, not by domain
        - Group names: 1-3 words
        - Only rename tabs with cluttered titles (ads, long product names, repeated site names)
        - Only flag true duplicates (same page or same content, different URL)
        - Output ONLY valid JSON, nothing else
        """
    }

    @MainActor
    private static func buildUser(
        tabs: [TabInput],
        spaceName: String,
        existingFolderNames: [String]
    ) -> String {
        let capped = Array(tabs.prefix(maxTabs))
        let count = capped.count

        // Header line
        var header = "Space \"\(spaceName)\", \(count) unfiled tab\(count == 1 ? "" : "s")"
        if !existingFolderNames.isEmpty {
            let names = existingFolderNames.joined(separator: ", ")
            header += ", \(existingFolderNames.count) existing folder\(existingFolderNames.count == 1 ? "" : "s") (\(names))"
        }
        header += ":"

        // Tab lines
        let lines = capped.map { input in
            let title = input.tab.displayName
            let shortURL = shortenURL(input.tab.url)
            return "\(input.index). \"\(title)\" | \(shortURL)"
        }

        return ([header] + lines).joined(separator: "\n")
    }

    /// Shorten a URL to `host + path prefix` with a max of 60 characters of path to save tokens.
    private static func shortenURL(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        let path = url.path  // e.g. "/dp/B08X1234/ref=..."

        if path.isEmpty || path == "/" {
            return host
        }

        let maxPathLength = 60
        if path.count <= maxPathLength {
            return host + path
        }

        let truncated = String(path.prefix(maxPathLength))
        return host + truncated + "..."
    }
}
