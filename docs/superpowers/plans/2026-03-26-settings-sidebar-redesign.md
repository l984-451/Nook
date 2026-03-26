# Settings Sidebar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Safari-style top-tab Settings with macOS 26 sidebar navigation, extract SponsorBlock and Ad Blocker into standalone sections, and convert all checkmarks to toggles.

**Architecture:** New `SettingsWindow` uses `NavigationSplitView` with a sidebar for section selection and a detail pane using `Form` + `.formStyle(.grouped)`. The existing `Settings { }` scene in `NookApp` is replaced with a `Window` scene. Content is migrated from existing views with minimal logic changes.

**Tech Stack:** SwiftUI, NavigationSplitView, Form (.grouped), macOS 15.5+ (Tahoe/macOS 26 Liquid Glass)

---

### Task 1: Update SettingsTabs Enum

**Files:**
- Modify: `Nook/Components/Settings/SettingsUtils.swift`

- [ ] **Step 1: Add new enum cases and update properties**

Replace the entire contents of `SettingsUtils.swift` with:

```swift
//
//  SettingsUtils.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//
import Foundation
import SwiftUI

enum SettingsTabs: String, Hashable, CaseIterable {
    case general
    case appearance
    case ai
    case privacy
    case adBlocker
    case sponsorBlock
    case profiles
    case shortcuts
    case extensions
    case advanced

    var name: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .ai: return "AI"
        case .privacy: return "Privacy"
        case .adBlocker: return "Ad Blocker"
        case .sponsorBlock: return "SponsorBlock"
        case .profiles: return "Profiles"
        case .shortcuts: return "Shortcuts"
        case .extensions: return "Extensions"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .ai: return "sparkles"
        case .privacy: return "lock.shield"
        case .adBlocker: return "shield.lefthalf.filled"
        case .sponsorBlock: return "forward.end.alt"
        case .profiles: return "person.crop.circle"
        case .shortcuts: return "keyboard"
        case .extensions: return "puzzlepiece.extension"
        case .advanced: return "wrench.and.screwdriver"
        }
    }

    var iconColor: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .pink
        case .ai: return .purple
        case .privacy: return .blue
        case .adBlocker: return .green
        case .sponsorBlock: return .orange
        case .profiles: return .cyan
        case .shortcuts: return .indigo
        case .extensions: return .teal
        case .advanced: return .secondary
        }
    }

    /// Sidebar groups, separated by visual spacing. Each inner array is one group.
    static var sidebarGroups: [[SettingsTabs]] {
        var groups: [[SettingsTabs]] = [
            [.general, .appearance],
            [.ai],
            [.privacy, .adBlocker, .sponsorBlock],
            [.profiles, .shortcuts, .extensions],
        ]
        #if DEBUG
        groups.append([.advanced])
        #endif
        return groups
    }
}
```

- [ ] **Step 2: Verify build compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -20`

Expected: Build errors from existing code referencing removed `ordered` property and changed conformance — that's expected, will be fixed in subsequent tasks.

- [ ] **Step 3: Commit**

```bash
git add Nook/Components/Settings/SettingsUtils.swift
git commit -m "update SettingsTabs enum with adBlocker, sponsorBlock cases and sidebar groups"
```

---

### Task 2: Create SettingsWindow with NavigationSplitView

**Files:**
- Create: `Nook/Components/Settings/SettingsWindow.swift`

- [ ] **Step 1: Create the sidebar + detail container**

Create `Nook/Components/Settings/SettingsWindow.swift`:

```swift
//
//  SettingsWindow.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        NavigationSplitView {
            SettingsSidebar(selection: $settings.currentSettingsTab)
        } detail: {
            SettingsDetailPane(tab: nookSettings.currentSettingsTab)
                .environmentObject(browserManager)
                .environmentObject(gradientColorManager)
        }
        .frame(width: 780, height: 540)
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTabs
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(SettingsTabs.sidebarGroups.enumerated()), id: \.offset) { index, group in
                Section {
                    ForEach(group, id: \.self) { tab in
                        if tab == .extensions {
                            if #available(macOS 15.5, *),
                               browserManager.extensionManager != nil {
                                sidebarRow(tab)
                            }
                        } else {
                            sidebarRow(tab)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 240)
    }

    private func sidebarRow(_ tab: SettingsTabs) -> some View {
        Label {
            Text(tab.name)
        } icon: {
            Image(systemName: tab.icon)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tab.iconColor.gradient)
                )
        }
        .tag(tab)
    }
}

// MARK: - Detail Pane

private struct SettingsDetailPane: View {
    let tab: SettingsTabs
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Group {
            switch tab {
            case .general:
                SettingsGeneralTab()
            case .appearance:
                SettingsAppearanceTab()
            case .ai:
                SettingsAITab()
            case .privacy:
                PrivacySettingsView()
            case .adBlocker:
                SettingsAdBlockerTab()
            case .sponsorBlock:
                SettingsSponsorBlockTab()
            case .profiles:
                ProfilesSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .extensions:
                if #available(macOS 15.5, *),
                   let extensionManager = browserManager.extensionManager {
                    ExtensionsSettingsView(extensionManager: extensionManager)
                }
            case .advanced:
                AdvancedSettingsView()
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Nook/Components/Settings/SettingsWindow.swift
git commit -m "add SettingsWindow with NavigationSplitView sidebar layout"
```

---

### Task 3: Create SponsorBlock Standalone Tab

**Files:**
- Create: `Nook/Components/Settings/Tabs/SponsorBlock.swift`

- [ ] **Step 1: Create the SponsorBlock settings tab**

Create `Nook/Components/Settings/Tabs/SponsorBlock.swift`:

```swift
//
//  SponsorBlock.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI

struct SettingsSponsorBlockTab: View {
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Skip YouTube Sponsors", isOn: $settings.sponsorBlockEnabled)
            } footer: {
                Text("Skip sponsored segments, intros, and other non-content on YouTube using community data from SponsorBlock.")
            }

            if nookSettings.sponsorBlockEnabled {
                Section("Behavior") {
                    Toggle("Auto-skip segments", isOn: $settings.sponsorBlockAutoSkip)
                }

                Section("Categories") {
                    ForEach(SponsorBlockCategory.allCases) { category in
                        Toggle(isOn: Binding(
                            get: { nookSettings.sponsorBlockCategories.contains(category.rawValue) },
                            set: { enabled in
                                if enabled {
                                    nookSettings.sponsorBlockCategories.append(category.rawValue)
                                } else {
                                    nookSettings.sponsorBlockCategories.removeAll { $0 == category.rawValue }
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(sponsorBlockCategoryColor(category))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.displayName)
                                    Text(category.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sponsorBlockCategoryColor(_ category: SponsorBlockCategory) -> Color {
        switch category {
        case .sponsor: return .green
        case .selfpromo: return .yellow
        case .exclusive_access: return Color(red: 0, green: 0.54, blue: 0.36)
        case .interaction: return .purple
        case .intro: return .cyan
        case .outro: return .blue
        case .preview: return .teal
        case .filler: return .indigo
        case .music_offtopic: return .orange
        case .poi_highlight: return .pink
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Nook/Components/Settings/Tabs/SponsorBlock.swift
git commit -m "add standalone SponsorBlock settings tab"
```

---

### Task 4: Create Ad Blocker Standalone Tab

**Files:**
- Create: `Nook/Components/Settings/Tabs/AdBlocker.swift`

- [ ] **Step 1: Create the Ad Blocker settings tab**

Create `Nook/Components/Settings/Tabs/AdBlocker.swift`:

```swift
//
//  AdBlocker.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI

struct SettingsAdBlockerTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @State private var isUpdatingFilters = false

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Ad & Tracker Blocker", isOn: $settings.adBlockerEnabled)
                    .onChange(of: nookSettings.adBlockerEnabled) { _, enabled in
                        browserManager.contentBlockerManager.setEnabled(enabled)
                    }
            } footer: {
                Text("Filter lists update automatically every 24 hours.")
            }

            if nookSettings.adBlockerEnabled {
                Section("Status") {
                    HStack {
                        if isUpdatingFilters {
                            ProgressView()
                                .controlSize(.small)
                            Text("Updating filter lists...")
                                .foregroundStyle(.secondary)
                        } else {
                            if let lastUpdate = nookSettings.adBlockerLastUpdate {
                                Text("Last updated: \(lastUpdate, style: .relative) ago")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Update Filters") {
                                isUpdatingFilters = true
                                Task {
                                    await browserManager.contentBlockerManager.recompileFilterLists()
                                    isUpdatingFilters = false
                                }
                            }
                        }
                    }
                }

                Section("Default Filter Lists") {
                    ForEach(FilterListManager.defaultLists, id: \.filename) { list in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text(list.name)
                            Spacer()
                            Text(list.category.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }

                if !FilterListManager.optionalLists.isEmpty {
                    ForEach(FilterListManager.FilterListCategory.allCases, id: \.rawValue) { category in
                        let listsInCategory = FilterListManager.optionalLists.filter { $0.category == category }
                        if !listsInCategory.isEmpty {
                            Section(category.rawValue) {
                                ForEach(listsInCategory, id: \.filename) { list in
                                    Toggle(list.name, isOn: Binding(
                                        get: { nookSettings.enabledOptionalFilterLists.contains(list.filename) },
                                        set: { enabled in
                                            if enabled {
                                                nookSettings.enabledOptionalFilterLists.append(list.filename)
                                            } else {
                                                nookSettings.enabledOptionalFilterLists.removeAll { $0 == list.filename }
                                            }
                                            browserManager.contentBlockerManager.filterListManager.enabledOptionalFilterListFilenames = Set(nookSettings.enabledOptionalFilterLists)
                                            Task {
                                                await browserManager.contentBlockerManager.recompileFilterLists()
                                            }
                                        }
                                    ))
                                }
                            }
                        }
                    }

                    Section {
                        Text("Enabling additional lists improves blocking but increases memory usage.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add Nook/Components/Settings/Tabs/AdBlocker.swift
git commit -m "add standalone Ad Blocker settings tab"
```

---

### Task 5: Refactor General Tab — Remove SponsorBlock, Convert to Form+Grouped

**Files:**
- Modify: `Nook/Components/Settings/Tabs/General.swift`

- [ ] **Step 1: Rewrite General.swift without SponsorBlock section and MemberCard**

Replace the `SettingsGeneralTab` struct (keep `CustomSearchEngineEditor` as-is) in `General.swift`. Remove the entire SponsorBlock `Section`, the `sponsorBlockCategoryColor` helper, and the `MemberCard()` / `HStack` wrapper. The body should now be just a `Form` with `.formStyle(.grouped)`:

```swift
struct SettingsGeneralTab: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(\.nookSettings) var nookSettings
    @State private var showingAddSite = false
    @State private var showingAddEngine = false

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("Warn before quitting Nook", isOn: $settings.askBeforeQuit)
                Toggle("Automatically update Nook", isOn: .constant(true))
                    .disabled(true)
            }

            Section("Performance") {
                Picker("Tab Management", selection: Binding(
                    get: { nookSettings.tabManagementMode },
                    set: { nookSettings.tabManagementMode = $0 }
                )) {
                    ForEach(TabManagementMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: nookSettings.tabManagementMode.icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(nookSettings.tabManagementMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("On Startup", selection: Binding(
                    get: { nookSettings.startupLoadMode },
                    set: { nookSettings.startupLoadMode = $0 }
                )) {
                    ForEach(StartupLoadMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "power")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(nookSettings.startupLoadMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Unload All Inactive Tabs") {
                    tabManager.unloadAllInactiveTabs()
                }
            }

            Section(header: Text("Search")) {
                HStack {
                    Picker(
                        "Default search engine",
                        selection: $settings.searchEngineId
                    ) {
                        ForEach(SearchProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider.rawValue)
                        }
                        ForEach(nookSettings.customSearchEngines) { engine in
                            Text(engine.name).tag(engine.id.uuidString)
                        }
                    }

                    Button {
                        showingAddEngine = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if let selected = nookSettings.customSearchEngines.first(where: { $0.id.uuidString == nookSettings.searchEngineId }) {
                    HStack {
                        Text(selected.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Remove") {
                            nookSettings.customSearchEngines.removeAll { $0.id == selected.id }
                            nookSettings.searchEngineId = SearchProvider.google.rawValue
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                ForEach(nookSettings.siteSearchEntries) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.color)
                            .frame(width: 10, height: 10)
                        Text(entry.name)
                        Spacer()
                        Text(entry.domain)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Button {
                            nookSettings.siteSearchEntries.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showingAddSite = true
                } label: {
                    Label("Add Site", systemImage: "plus")
                }

                Button("Reset to Defaults") {
                    nookSettings.siteSearchEntries = SiteSearchEntry.defaultSites
                }
            } header: {
                Text("Site Search")
            } footer: {
                Text("Type a prefix in the command palette and press Tab to search a site directly.")
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSite) {
            SiteSearchEntryEditor(entry: nil) { newEntry in
                nookSettings.siteSearchEntries.append(newEntry)
            }
        }
        .sheet(isPresented: $showingAddEngine) {
            CustomSearchEngineEditor { newEngine in
                nookSettings.customSearchEngines.append(newEngine)
            }
        }
    }
}
```

Keep `CustomSearchEngineEditor` unchanged below this struct.

- [ ] **Step 2: Commit**

```bash
git add Nook/Components/Settings/Tabs/General.swift
git commit -m "refactor General tab: remove SponsorBlock, use Form+grouped"
```

---

### Task 6: Refactor Privacy Tab — Remove Ad Blocker Section, Convert to Form+Grouped

**Files:**
- Modify: `Nook/Components/Settings/PrivacySettingsView.swift`

- [ ] **Step 1: Rewrite PrivacySettingsView to use Form+grouped without Ad Blocker**

Remove the "Ad & Tracker Blocking" section (lines ~143-196 — the `Content Blocking Section` VStack) and the `filterListManagementSection` computed property. Convert the remaining VStack layout to `Form` with `.formStyle(.grouped)`. Keep all cookie/cache/privacy methods as-is.

The new `body` should be:

```swift
var body: some View {
    @Bindable var settings = nookSettings

    Form {
        Section("Cookie Management") {
            cookieStatsView

            HStack {
                Button("Manage Cookies") {
                    showingCookieManager = true
                }
                .buttonStyle(.bordered)

                Menu("Clear Data") {
                    Button("Clear Expired Cookies") {
                        clearExpiredCookies()
                    }
                    Button("Clear Third-Party Cookies") {
                        clearThirdPartyCookies()
                    }
                    Button("Clear High-Risk Cookies") {
                        clearHighRiskCookies()
                    }
                    Divider()
                    Button("Clear All Cookies") {
                        clearAllCookies()
                    }
                    Button("Privacy Cleanup") {
                        performCookiePrivacyCleanup()
                    }
                    Divider()
                    Button("Clear All Website Data", role: .destructive) {
                        clearAllWebsiteData()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isClearing)

                if isClearing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }

        Section("Cache Management") {
            cacheStatsView

            HStack {
                Button("Manage Cache") {
                    showingCacheManager = true
                }
                .buttonStyle(.bordered)

                Menu("Clear Cache") {
                    Button("Clear Stale Cache") {
                        clearStaleCache()
                    }
                    Button("Clear Personal Data Cache") {
                        clearPersonalDataCache()
                    }
                    Button("Clear Disk Cache") {
                        clearDiskCache()
                    }
                    Button("Clear Memory Cache") {
                        clearMemoryCache()
                    }
                    Divider()
                    Button("Privacy Cleanup") {
                        performCachePrivacyCleanup()
                    }
                    Divider()
                    Button("Clear All Cache", role: .destructive) {
                        clearAllCache()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isClearing)

                if isClearing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }

        Section("Privacy Controls") {
            Toggle("Block Cross-Site Tracking", isOn: $settings.blockCrossSiteTracking)
                .onChange(of: nookSettings.blockCrossSiteTracking) { _, enabled in
                    browserManager.contentBlockerManager.setEnabled(enabled)
                }
        }

        Section("Website Data") {
            Button("Clear Browsing History") {
                clearBrowsingHistory()
            }
            Button("Clear Cache") {
                clearCache()
            }
        }
    }
    .formStyle(.grouped)
    .onAppear {
        Task {
            await cookieManager.loadCookies()
            await cacheManager.loadCacheData()
        }
    }
    .sheet(isPresented: $showingCookieManager) {
        CookieManagementView()
    }
    .sheet(isPresented: $showingCacheManager) {
        CacheManagementView()
    }
}
```

Remove the `isUpdatingFilters` state variable and the `filterListManagementSection` computed property. Keep all other methods and computed properties (`cookieStatsView`, `cacheStatsView`, all clearing functions, `formatSize` helpers) unchanged.

- [ ] **Step 2: Commit**

```bash
git add Nook/Components/Settings/PrivacySettingsView.swift
git commit -m "refactor Privacy tab: remove Ad Blocker section, use Form+grouped"
```

---

### Task 7: Convert Profiles, Shortcuts, Extensions, Advanced to Form+Grouped

**Files:**
- Modify: `Nook/Components/Settings/SettingsView.swift`

- [ ] **Step 1: Convert ProfilesSettingsView to Form+grouped**

Replace the outer `VStack` + `SettingsSectionCard` pattern in `ProfilesSettingsView.body` with `Form` + `.formStyle(.grouped)` + `Section`. The content of each card becomes a `Section`. Remove `.padding()` at the bottom since Form handles its own padding.

Replace the body (lines ~432-568) with:

```swift
var body: some View {
    Form {
        Section("Profiles") {
            HStack {
                Button(action: showCreateDialog) {
                    Label("Create Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }

            if browserManager.profileManager.profiles.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                        .foregroundColor(.secondary)
                    Text("No profiles yet. Create one to get started.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(
                    browserManager.profileManager.profiles,
                    id: \.id
                ) { profile in
                    ProfileRowView(
                        profile: profile,
                        isCurrent: browserManager.currentProfile?.id == profile.id,
                        spacesCount: spacesCount(for: profile),
                        tabsCount: tabsCount(for: profile),
                        dataSizeDescription: "Shared store",
                        pinnedCount: pinnedCount(for: profile),
                        onMakeCurrent: {
                            Task {
                                await browserManager.switchToProfile(profile)
                            }
                        },
                        onRename: { startRename(profile) },
                        onDelete: { startDelete(profile) },
                        onManageData: {
                            showDataManagement(for: profile)
                        }
                    )
                }
            }

            MigrationControls()
                .environmentObject(browserManager)
        }

        Section("Space Assignments") {
            HStack(spacing: 8) {
                Button(action: assignAllSpacesToCurrentProfile) {
                    Label("Assign All to Current Profile", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)

                Button(action: resetAllSpaceAssignments) {
                    Label("Reset to Default Profile", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.bordered)

                Spacer()
            }

            if browserManager.tabManager.spaces.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group")
                        .foregroundStyle(.secondary)
                    Text("No spaces yet. Create a space to assign profiles.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(browserManager.tabManager.spaces, id: \.id) { space in
                    SpaceAssignmentRowView(space: space)
                }
            }
        }
    }
    .formStyle(.grouped)
}
```

- [ ] **Step 2: Convert ShortcutsSettingsView to Form+grouped**

Replace the `ShortcutsSettingsView.body` (lines ~1096-1184). Wrap the content in `Form` + `.formStyle(.grouped)`. The search/filter bar and shortcut list go into sections:

```swift
var body: some View {
    Form {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Detect Website Shortcuts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("When a website uses the same shortcut, press once for website, twice for Nook")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { WebsiteShortcutProfile.isFeatureEnabled },
                    set: { WebsiteShortcutProfile.isFeatureEnabled = $0 }
                ))
                .labelsHidden()
            }
        }

        Section {
            HStack(spacing: 12) {
                TextField("Search shortcuts...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        CategoryFilterChip(
                            title: "All",
                            icon: nil,
                            isSelected: selectedCategory == nil,
                            onTap: { selectedCategory = nil }
                        )
                        ForEach(ShortcutCategory.allCases, id: \.self) { category in
                            CategoryFilterChip(
                                title: category.displayName,
                                icon: category.icon,
                                isSelected: selectedCategory == category,
                                onTap: { selectedCategory = category }
                            )
                        }
                    }
                }

                Spacer()

                Button("Reset to Defaults") {
                    keyboardShortcutManager.resetToDefaults()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }

        ForEach(ShortcutCategory.allCases, id: \.self) { category in
            if let categoryShortcuts = shortcutsByCategory[category], !categoryShortcuts.isEmpty {
                Section(category.displayName) {
                    ForEach(categoryShortcuts, id: \.id) { shortcut in
                        ShortcutRowView(shortcut: shortcut)
                    }
                }
            }
        }
    }
    .formStyle(.grouped)
}
```

- [ ] **Step 3: Convert ExtensionsSettingsView to Form+grouped**

Replace `ExtensionsSettingsView.body` (lines ~1316-1421). Wrap content in `Form` + `.formStyle(.grouped)`:

```swift
var body: some View {
    Form {
        if #available(macOS 15.5, *) {
            Section {
                HStack {
                    Spacer()
                    Button("Install Extension...") {
                        browserManager.showExtensionInstallDialog()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if extensionManager.installedExtensions.isEmpty && !showSafariSection {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No Extensions Installed")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Install browser extensions to enhance your browsing experience")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section("Installed Extensions") {
                    ForEach(extensionManager.installedExtensions, id: \.id) { ext in
                        ExtensionRowView(extension: ext)
                            .environmentObject(browserManager)
                    }
                }
            }

            Section("Safari Extensions") {
                HStack {
                    if isScanningSafari {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning...")
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Scan for Safari Extensions") {
                            scanForSafariExtensions()
                        }
                    }
                    Spacer()
                }

                if showSafariSection {
                    if safariExtensions.isEmpty {
                        Text("No Safari Web Extensions found on this Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(safariExtensions) { ext in
                            SafariExtensionRowView(
                                info: ext,
                                isAlreadyInstalled: extensionManager.installedExtensions.contains(where: {
                                    $0.name == ext.name
                                }),
                                onInstall: {
                                    installSafariExtension(ext)
                                }
                            )
                        }
                    }
                }
            }
        } else {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Extensions Not Supported")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Extensions require macOS 15.5 or later")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
    .formStyle(.grouped)
    .onAppear {
        if safariExtensions.isEmpty && !isScanningSafari {
            scanForSafariExtensions()
        }
    }
}
```

- [ ] **Step 4: Convert AdvancedSettingsView to Form+grouped**

Replace `AdvancedSettingsView.body` (lines ~1578-1602):

```swift
var body: some View {
    @Bindable var settings = nookSettings
    Form {
        #if DEBUG
        Section("Debug Options") {
            Toggle(isOn: $settings.debugToggleUpdateNotification) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Update Notification")
                    Text("Force display the sidebar update notification for appearance debugging")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        #endif
    }
    .formStyle(.grouped)
}
```

- [ ] **Step 5: Remove unused components from SettingsView.swift**

Remove the following from `SettingsView.swift`:
- `SettingsView` struct (lines ~12-20)
- `SettingsContent` struct (lines ~22-124)
- `SettingsPane` struct (lines ~127-151)
- `SettingsTabStrip` and `SettingsTabItem` (lines ~153-164)
- `GeneralSettingsView` struct (lines ~166-422) — the old card-based general view
- `SettingsSectionCard` struct (lines ~1607-1643)
- `SettingsHeroCard` struct (lines ~1645-1693)
- `SettingsPlaceholderView` struct (if present, ~1695+)

Keep: `ProfilesSettingsView`, `MigrationControls`, `ShortcutsSettingsView`, `CategorySection`, `ShortcutRowView`, `CategoryFilterChip`, `ExtensionsSettingsView`, `SafariExtensionRowView`, `ExtensionRowView`, `AdvancedSettingsView`.

- [ ] **Step 6: Commit**

```bash
git add Nook/Components/Settings/SettingsView.swift
git commit -m "convert Profiles, Shortcuts, Extensions, Advanced to Form+grouped; remove legacy components"
```

---

### Task 8: Wire Up NookApp to Use New SettingsWindow

**Files:**
- Modify: `App/NookApp.swift`

- [ ] **Step 1: Replace the `Settings { }` scene**

In `NookApp.swift`, find the `Settings` scene block (around line 80):

```swift
        // Native macOS Settings window
        Settings {
            SettingsView()
                .environmentObject(browserManager)
                .environmentObject(browserManager.tabManager)
                .environmentObject(browserManager.gradientColorManager)
                .environment(\.nookSettings, settingsManager)
                .environment(keyboardShortcutManager)
                .environment(aiConfigService)
                .environment(mcpManager)
                .environment(tabOrganizerManager)
        }
```

Replace with:

```swift
        // macOS 26 style sidebar settings window
        Window("Nook Settings", id: "nook-settings") {
            SettingsWindow()
                .environmentObject(browserManager)
                .environmentObject(browserManager.tabManager)
                .environmentObject(browserManager.gradientColorManager)
                .environment(\.nookSettings, settingsManager)
                .environment(keyboardShortcutManager)
                .environment(aiConfigService)
                .environment(mcpManager)
                .environment(tabOrganizerManager)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
```

- [ ] **Step 2: Update Cmd+, to open the new settings window**

The native `Settings { }` scene automatically responds to Cmd+,. With a custom `Window`, we need to handle this. In `NookCommands.swift` (or wherever the settings menu command is defined), check if there's already a command for opening settings. If the app relies on the built-in Settings behavior, add an `openWindow` call.

Search for how settings is opened:

```bash
grep -rn "showSettingsWindow\|openSettings\|settingsWindow\|showPreferencesWindow\|SettingsLink\|Settings(" App/ --include="*.swift"
```

If `NookCommands.swift` has a settings command, update it to use `@Environment(\.openWindow) var openWindow` and call `openWindow(id: "nook-settings")`. If it relies on the native `Settings` behavior, add a `CommandGroup(replacing: .appSettings)` that opens the window.

In `NookCommands.swift`, add or update the settings command:

```swift
CommandGroup(replacing: .appSettings) {
    Button("Settings...") {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "nook-settings" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
    .keyboardShortcut(",", modifiers: .command)
}
```

Note: The exact approach depends on how `NookCommands` is structured. An alternative is to use `@Environment(\.openWindow)` inside the commands body. Read the file first to determine the right approach.

- [ ] **Step 3: Commit**

```bash
git add App/NookApp.swift App/NookCommands.swift
git commit -m "wire NookApp to use new sidebar SettingsWindow"
```

---

### Task 9: Build, Test, and Fix Compilation Errors

**Files:**
- All modified files from previous tasks

- [ ] **Step 1: Attempt a full build**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | grep -E "error:|warning:" | head -40`

- [ ] **Step 2: Fix any compilation errors**

Common expected issues:
- References to deleted `SettingsView` — search and update any remaining references
- `SettingsTabs` now conforms to `RawRepresentable` (String) — check `NookSettingsService` persists correctly. The `currentSettingsTab` property may need updating since the old enum wasn't `RawRepresentable`. If `NookSettingsService` uses `UserDefaults` to store it via a raw integer or string, update accordingly.
- Any views that reference `SettingsSectionCard` or `SettingsHeroCard` outside SettingsView.swift — search with `grep -rn "SettingsSectionCard\|SettingsHeroCard\|SettingsPane\b" --include="*.swift"`

- [ ] **Step 3: Fix any remaining toggle conversion misses**

Search for checkbox-style toggles that should now be standard toggles:

```bash
grep -rn "toggleStyle(.checkbox)" --include="*.swift"
```

Remove any `.toggleStyle(.checkbox)` found in settings-related files.

- [ ] **Step 4: Verify the app launches and settings window opens**

Run the app from Xcode, press Cmd+, and verify:
- Sidebar appears with all 10 sections in correct groups
- Clicking each section shows the correct content
- Toggles appear instead of checkmarks
- Content scrolls properly in the fixed-height pane

- [ ] **Step 5: Commit fixes**

```bash
git add -A
git commit -m "fix compilation errors from settings sidebar migration"
```

---

### Task 10: Clean Up Unused Code

**Files:**
- Modify: `Nook/Components/Settings/SettingsView.swift`
- Potentially modify: other files with stale references

- [ ] **Step 1: Remove any dead code**

Search for references to removed types:

```bash
grep -rn "GeneralSettingsView\|SettingsHeroCard\|SettingsSectionCard\|SettingsTabStrip\|SettingsTabItem\|SettingsPlaceholderView" --include="*.swift"
```

Remove any found references. Also check for the `MemberCard` view — if it's only used in the old `GeneralSettingsView` (which we removed), delete `Nook/Components/Settings/Tabs/MemberCard.swift`.

- [ ] **Step 2: Verify SettingsView.swift is clean**

The file should now contain only:
- `ProfilesSettingsView` (+ its helpers and `SpaceAssignmentRowView`)
- `MigrationControls`
- `ShortcutsSettingsView` (+ `CategorySection`, `ShortcutRowView`, `CategoryFilterChip`)
- `ExtensionsSettingsView` (+ `SafariExtensionRowView`, `ExtensionRowView`)
- `AdvancedSettingsView`

- [ ] **Step 3: Final build verification**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | grep "error:" | head -10`

Expected: BUILD SUCCEEDED with no errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "clean up unused settings components after sidebar migration"
```
