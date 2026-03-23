//
//  TabOrganizerManager.swift
//  Nook
//
//  Public coordinator for LLM-based tab organization.
//  Orchestrates the full flow: collect tabs, build prompt, run inference,
//  parse plan, and present results to the UI for review.
//

import Foundation
import OSLog

// MARK: - TabOrganizerManager

@Observable
@MainActor
final class TabOrganizerManager {

    // MARK: - Properties

    private static let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Nook",
        category: "TabOrganizerManager"
    )

    /// The local LLM engine used for inference.
    let engine: LocalLLMEngine

    /// The parsed organization plan from the last run, if any.
    private(set) var plan: TabOrganizationPlan?

    /// Maps 1-based prompt indices to actual Tab objects for the current plan.
    private(set) var tabMapping: [Int: Tab] = [:]

    /// Tabs that were not assigned to any group in the current plan.
    private(set) var ungroupedTabs: [TabInput] = []

    /// Whether an organization run is currently in progress.
    private(set) var isOrganizing: Bool = false

    /// Whether the preview sheet should be shown.
    private(set) var showPreview: Bool = false

    /// The last error message, if any.
    private(set) var error: String?

    /// Whether a previous organization can be undone.
    private(set) var canUndo: Bool = false

    /// Snapshot for undo support.
    private var undoSnapshot: TabSnapshot?

    /// The space ID that was last organized (needed for undo).
    private var undoSpaceId: UUID?

    // MARK: - Init

    init(engine: LocalLLMEngine) {
        self.engine = engine
    }

    /// Convenience initializer that creates its own engine.
    init() {
        self.engine = LocalLLMEngine()
    }

    // MARK: - Organize

    /// Run the full tab organization flow for a given space.
    ///
    /// 1. Collects unfiled tabs from the space.
    /// 2. Builds a prompt with tab metadata and existing folder names.
    /// 3. Runs local LLM inference.
    /// 4. Parses the result into a ``TabOrganizationPlan``.
    /// 5. Sets state for the preview UI.
    ///
    /// - Parameters:
    ///   - space: The space whose tabs should be organized.
    ///   - tabManager: The tab manager to query for tabs and folders.
    func organizeTabs(in space: Space, using tabManager: TabManager) async {
        // Guard: not already organizing
        guard !isOrganizing else {
            Self.log.warning("Organization already in progress, ignoring request")
            return
        }

        // Clear any previous error
        error = nil

        // Get unfiled tabs
        let tabs = tabManager.tabs(in: space)

        // Guard: need at least 3 tabs
        guard tabs.count >= 3 else {
            error = "Need at least 3 unfiled tabs to organize (found \(tabs.count))."
            Self.log.info("Too few tabs to organize: \(tabs.count)")
            return
        }

        // Guard: not more than maxTabs
        guard tabs.count <= TabOrganizationPrompt.maxTabs else {
            error = "Too many tabs (\(tabs.count)). Maximum is \(TabOrganizationPrompt.maxTabs)."
            Self.log.info("Too many tabs to organize: \(tabs.count)")
            return
        }

        isOrganizing = true
        Self.log.info("Starting tab organization for space '\(space.name)' with \(tabs.count) tabs")

        do {
            // Build index mapping (1-based) and TabInput array
            var mapping: [Int: Tab] = [:]
            var inputs: [TabInput] = []
            for (offset, tab) in tabs.enumerated() {
                let index = offset + 1
                mapping[index] = tab
                inputs.append(TabInput(index: index, tab: tab))
            }

            // Get existing folder names for context
            let existingFolderNames = tabManager.folders(for: space.id).map(\.name)

            // Build prompt
            let prompt = TabOrganizationPrompt.build(
                tabs: inputs,
                spaceName: space.name,
                existingFolderNames: existingFolderNames
            )

            // Run inference
            let output = try await engine.generate(
                systemPrompt: prompt.system,
                userPrompt: prompt.user,
                maxTokens: 1024
            )

            Self.log.debug("LLM output: \(output)")

            // Parse the plan
            let validRange = 1...tabs.count
            let parsedPlan = try TabOrganizationPlanParser.parse(output, validRange: validRange)

            // Compute ungrouped tabs (tabs not mentioned in any group)
            let groupedIndices = Set(parsedPlan.groups.flatMap(\.tabs))
            let ungrouped = inputs.filter { !groupedIndices.contains($0.index) }

            // Update state for the preview UI
            self.plan = parsedPlan
            self.tabMapping = mapping
            self.ungroupedTabs = ungrouped
            self.showPreview = true

            Self.log.info("Organization plan ready: \(parsedPlan.groups.count) groups, \(parsedPlan.renames.count) renames, \(parsedPlan.duplicates.count) duplicate sets")

        } catch {
            let message = error.localizedDescription
            self.error = message
            Self.log.error("Organization failed: \(message)")
        }

        isOrganizing = false
    }

    // MARK: - Apply

    /// Apply the accepted changes from the current plan.
    ///
    /// - Parameters:
    ///   - accepted: Which plan items the user accepted in the preview sheet.
    ///   - spaceId: The space these tabs belong to.
    ///   - tabManager: The tab manager to mutate.
    func applyPlan(accepted: AcceptedChanges, spaceId: UUID, tabManager: TabManager) {
        guard let plan else {
            Self.log.warning("applyPlan called with no plan")
            return
        }

        Self.log.info("Applying organization plan")

        let snapshot = TabOrganizationApplier.apply(
            plan: plan,
            accepted: accepted,
            tabMapping: tabMapping,
            spaceId: spaceId,
            tabManager: tabManager
        )

        // Store undo state
        undoSnapshot = snapshot
        undoSpaceId = spaceId
        canUndo = true

        // Clear plan state
        clearPlanState()

        Self.log.info("Organization plan applied successfully")
    }

    // MARK: - Undo

    /// Undo the last organization operation.
    ///
    /// - Parameter tabManager: The tab manager to mutate.
    func undoLastOrganization(using tabManager: TabManager) {
        guard let snapshot = undoSnapshot, let spaceId = undoSpaceId else {
            Self.log.warning("undoLastOrganization called with no snapshot")
            return
        }

        Self.log.info("Undoing last organization")

        TabOrganizationApplier.undo(
            snapshot: snapshot,
            spaceId: spaceId,
            tabManager: tabManager
        )

        // Clear undo state
        undoSnapshot = nil
        undoSpaceId = nil
        canUndo = false

        Self.log.info("Undo complete")
    }

    // MARK: - Dismiss

    /// Dismiss the current plan without applying it.
    func dismissPlan() {
        clearPlanState()
        Self.log.info("Plan dismissed")
    }

    // MARK: - Private

    private func clearPlanState() {
        plan = nil
        tabMapping = [:]
        ungroupedTabs = []
        showPreview = false
        error = nil
    }
}
