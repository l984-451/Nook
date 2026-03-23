//
//  TabOrganizerPreviewSheet.swift
//  Nook
//
//  SwiftUI sheet showing the LLM organization plan with checkboxes
//  to accept or reject each suggestion before applying.
//

import SwiftUI

// MARK: - TabOrganizerPreviewSheet

struct TabOrganizerPreviewSheet: View {

    // MARK: - Environment

    @Environment(TabOrganizerManager.self) private var organizer
    @Environment(\.dismiss) private var dismiss

    // MARK: - Parameters

    let spaceId: UUID
    @ObservedObject var tabManager: TabManager

    // MARK: - State

    @State private var acceptedGroupIds: Set<UUID> = []
    @State private var acceptedRenameIds: Set<UUID> = []
    @State private var acceptedDuplicateIds: Set<UUID> = []
    @State private var applySortOrder: Bool = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            scrollContent
            Divider()
            footer
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 400, idealHeight: 600)
        .onAppear {
            defaultAllAccepted()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Organize Tabs")
                    .font(.title3)
                    .fontWeight(.semibold)

                if let plan = organizer.plan {
                    let count = plan.groups.count + plan.renames.count + plan.duplicates.count + (plan.sort != nil ? 1 : 0)
                    Text("\(count) suggestion\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding()
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let plan = organizer.plan {
                    if !plan.groups.isEmpty {
                        groupsSection(plan.groups)
                    }
                    if !plan.renames.isEmpty {
                        renamesSection(plan.renames)
                    }
                    if !plan.duplicates.isEmpty {
                        duplicatesSection(plan.duplicates)
                    }
                    if plan.sort != nil {
                        sortSection
                    }
                    if !organizer.ungroupedTabs.isEmpty {
                        ungroupedSection
                    }
                } else {
                    Text("No plan available.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                }
            }
            .padding()
        }
    }

    // MARK: - Groups Section

    private func groupsSection(_ groups: [TabOrganizationPlan.Group]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Groups", systemImage: "folder")

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: binding(for: group.id, in: $acceptedGroupIds)) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(group.name)
                                .fontWeight(.medium)
                            Text("(\(group.tabs.count) tab\(group.tabs.count == 1 ? "" : "s"))")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.checkbox)

                    // List of tab names in this group
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(group.tabs, id: \.self) { tabIndex in
                            if let tab = organizer.tabMapping[tabIndex] {
                                HStack(spacing: 4) {
                                    Text("\u{2022}")
                                        .foregroundStyle(.tertiary)
                                    Text(tab.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .padding(.leading, 24)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Renames Section

    private func renamesSection(_ renames: [TabOrganizationPlan.Rename]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Renames", systemImage: "pencil")

            ForEach(renames) { rename in
                Toggle(isOn: binding(for: rename.id, in: $acceptedRenameIds)) {
                    HStack(spacing: 6) {
                        if let tab = organizer.tabMapping[rename.tab] {
                            Text(tab.displayName)
                                .font(.caption)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                        }
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(rename.name)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Duplicates Section

    private func duplicatesSection(_ duplicates: [TabOrganizationPlan.DuplicateSet]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Duplicates", systemImage: "doc.on.doc")

            ForEach(duplicates) { dupSet in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: binding(for: dupSet.id, in: $acceptedDuplicateIds)) {
                        HStack(spacing: 6) {
                            Text("Close duplicates")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .toggleStyle(.checkbox)

                    VStack(alignment: .leading, spacing: 2) {
                        // Keep tab
                        if let keepTab = organizer.tabMapping[dupSet.keep] {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption2)
                                Text("Keep:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(keepTab.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }

                        // Close tabs
                        ForEach(dupSet.close, id: \.self) { tabIndex in
                            if let tab = organizer.tabMapping[tabIndex] {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption2)
                                    Text("Close:")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(tab.displayName)
                                        .font(.caption)
                                        .lineLimit(1)

                                    if tab.isPinned || tab.isSpacePinned {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.yellow)
                                            .font(.caption2)
                                            .help("This tab is pinned and will be unpinned before closing")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.leading, 24)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Sort Section

    private var sortSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Sort Order", systemImage: "arrow.up.arrow.down")

            Toggle(isOn: $applySortOrder) {
                Text("Apply suggested tab ordering")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .toggleStyle(.checkbox)
        }
    }

    // MARK: - Ungrouped Section

    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Ungrouped", systemImage: "tray")

            VStack(alignment: .leading, spacing: 2) {
                ForEach(organizer.ungroupedTabs, id: \.index) { input in
                    HStack(spacing: 4) {
                        Text("\u{2022}")
                            .foregroundStyle(.tertiary)
                        Text(input.tab.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.leading, 4)

            Text("These tabs were not assigned to any group.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button("Cancel") {
                organizer.dismissPlan()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Apply Selected") {
                let changes = AcceptedChanges(
                    acceptedGroupIds: acceptedGroupIds,
                    acceptedRenameIds: acceptedRenameIds,
                    acceptedDuplicateIds: acceptedDuplicateIds,
                    applySortOrder: applySortOrder
                )
                organizer.applyPlan(accepted: changes, spaceId: spaceId, tabManager: tabManager)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!hasAnyAccepted)
        }
        .padding()
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.primary)
    }

    private func defaultAllAccepted() {
        guard let plan = organizer.plan else { return }
        acceptedGroupIds = Set(plan.groups.map(\.id))
        acceptedRenameIds = Set(plan.renames.map(\.id))
        acceptedDuplicateIds = Set(plan.duplicates.map(\.id))
        applySortOrder = plan.sort != nil
    }

    private var hasAnyAccepted: Bool {
        !acceptedGroupIds.isEmpty
            || !acceptedRenameIds.isEmpty
            || !acceptedDuplicateIds.isEmpty
            || applySortOrder
    }

    private func binding(for id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { if $0 { set.wrappedValue.insert(id) } else { set.wrappedValue.remove(id) } }
        )
    }
}
