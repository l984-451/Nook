# Air Traffic Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically route URLs to designated spaces based on user-defined domain + path prefix rules.

**Architecture:** A standalone `SiteRoutingManager` owns rule storage (via `NookSettingsService`) and matching logic. It exposes `applyRoute(url:from:)` which returns `true` synchronously and executes the actual route (profile switch, space switch, tab creation) in an async `Task`. Three guard clauses in existing navigation code call this method.

**Tech Stack:** Swift 5, SwiftUI, UserDefaults (JSON-encoded `Codable` array), OSLog

**Spec:** `docs/superpowers/specs/2026-03-26-air-traffic-control-design.md`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|---------------|
| Create | `Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift` | Rule matching, route execution, CRUD, OSLog |
| Create | `Nook/Managers/SiteRoutingManager/SiteRoutingRule.swift` | Data model (`Codable`, `Identifiable`) |
| Create | `Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift` | Settings UI — rule list, add/edit sheet |
| Modify | `Settings/NookSettingsService.swift` | Add `siteRoutingRules` property + persistence key |
| Modify | `Nook/Components/Settings/SettingsUtils.swift` | Add `.airTrafficControl` case to `SettingsTabs` enum |
| Modify | `Nook/Components/Settings/SettingsWindow.swift` | Add routing case to `SettingsDetailPane` switch |
| Modify | `Nook/Managers/BrowserManager/BrowserManager.swift` | Add `siteRoutingManager` property, wire in init |
| Modify | `App/NookApp.swift` | Create and inject `SiteRoutingManager` |
| Modify | `Nook/Models/Tab/Tab.swift` | Guard clause in `decidePolicyFor` and `createWebViewWith` |
| Modify | `App/AppDelegate.swift` | Guard clause in `handleIncoming(url:)` |

---

## Task 1: Data Model — `SiteRoutingRule`

**Files:**
- Create: `Nook/Managers/SiteRoutingManager/SiteRoutingRule.swift`

- [ ] **Step 1: Create the model file**

```swift
//
//  SiteRoutingRule.swift
//  Nook
//

import Foundation

struct SiteRoutingRule: Codable, Identifiable, Equatable {
    let id: UUID
    var domain: String
    var pathPrefix: String?
    var targetSpaceId: UUID
    var targetProfileId: UUID
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        domain: String,
        pathPrefix: String? = nil,
        targetSpaceId: UUID,
        targetProfileId: UUID,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.domain = SiteRoutingRule.normalizeDomain(domain)
        self.pathPrefix = pathPrefix
        self.targetSpaceId = targetSpaceId
        self.targetProfileId = targetProfileId
        self.isEnabled = isEnabled
    }

    /// Strips scheme, www., trailing slashes from a domain string.
    static func normalizeDomain(_ input: String) -> String {
        var d = input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip scheme
        for prefix in ["https://", "http://"] {
            if d.hasPrefix(prefix) { d = String(d.dropFirst(prefix.count)) }
        }
        // Strip www.
        if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
        // Strip trailing slash and path
        if let slashIndex = d.firstIndex(of: "/") { d = String(d[..<slashIndex]) }
        return d
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/SiteRoutingManager/SiteRoutingRule.swift
git commit -m "feat(atc): add SiteRoutingRule data model"
```

---

## Task 2: Settings Storage — `NookSettingsService`

**Files:**
- Modify: `Settings/NookSettingsService.swift`

- [ ] **Step 1: Add the key constant**

In `NookSettingsService`, alongside the other `private let ...Key` constants (around line 45–50), add:

```swift
private let siteRoutingRulesKey = "settings.siteRoutingRules"
```

- [ ] **Step 2: Add the property with didSet**

Alongside the other `Codable` array properties (near `customSearchEngines` around line 79), add:

```swift
var siteRoutingRules: [SiteRoutingRule] = [] {
    didSet {
        if let data = try? JSONEncoder().encode(siteRoutingRules) {
            userDefaults.set(data, forKey: siteRoutingRulesKey)
        }
    }
}
```

- [ ] **Step 3: Load from UserDefaults in init()**

In `init()`, after the `customSearchEngines` loading block (around line 370–375), add:

```swift
if let srData = userDefaults.data(forKey: siteRoutingRulesKey),
   let decoded = try? JSONDecoder().decode([SiteRoutingRule].self, from: srData) {
    self.siteRoutingRules = decoded
} else {
    self.siteRoutingRules = []
}
```

- [ ] **Step 4: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add Settings/NookSettingsService.swift
git commit -m "feat(atc): add siteRoutingRules to NookSettingsService"
```

---

## Task 3: Core Manager — `SiteRoutingManager`

**Files:**
- Create: `Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift`

- [ ] **Step 1: Create the manager**

```swift
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

    /// Returns the best matching enabled rule for a URL, or nil.
    /// Most-specific rule wins (domain+pathPrefix beats domain-only).
    func resolve(url: URL) -> SiteRoutingRule? {
        guard let settingsService,
              let host = url.host?.lowercased().replacingOccurrences(of: "www.", with: "")
        else { return nil }

        let rules = settingsService.siteRoutingRules.filter { $0.isEnabled && $0.domain == host }
        guard !rules.isEmpty else { return nil }

        let path = url.path
        // Prefer rules with a pathPrefix that matches
        if let specific = rules.first(where: { prefix in
            guard let pp = prefix.pathPrefix, !pp.isEmpty else { return false }
            return path.hasPrefix(pp)
        }) {
            return specific
        }
        // Fall back to domain-only rule (no pathPrefix)
        return rules.first(where: { $0.pathPrefix == nil || $0.pathPrefix?.isEmpty == true })
    }

    /// Checks if the URL matches a routing rule. If so, schedules the route
    /// asynchronously and returns true (caller should cancel original navigation).
    /// Returns false if no rule matched or routing is not applicable.
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

        // Validate target space and profile still exist
        guard let targetSpace = tabManager.spaces.first(where: { $0.id == rule.targetSpaceId }),
              browserManager.profileManager.profiles.first(where: { $0.id == rule.targetProfileId }) != nil
        else {
            logger.debug("Route skipped: target space or profile no longer exists for rule \(rule.id)")
            return false
        }

        // Don't route if already on the target space
        if tabManager.currentSpace?.id == targetSpace.id {
            return false
        }

        logger.info("Route matched: \(url.absoluteString, privacy: .public) → space '\(targetSpace.name, privacy: .public)'")

        // Execute asynchronously — profile switch is async
        Task { @MainActor in
            // Switch profile if needed
            if let currentProfile = browserManager.currentProfile,
               currentProfile.id != rule.targetProfileId,
               let targetProfile = browserManager.profileManager.profiles.first(where: { $0.id == rule.targetProfileId }) {
                await browserManager.switchToProfile(targetProfile, context: .spaceChange)
            }

            // Switch to target space
            tabManager.setActiveSpace(targetSpace)

            // Create new tab in target space
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
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift
git commit -m "feat(atc): add SiteRoutingManager with matching and routing logic"
```

---

## Task 4: Wire Manager into BrowserManager and NookApp

**Files:**
- Modify: `Nook/Managers/BrowserManager/BrowserManager.swift`
- Modify: `App/NookApp.swift`

- [ ] **Step 1: Add property to BrowserManager**

In `BrowserManager`, alongside the other manager properties (around lines 395–425, near `externalMiniWindowManager`), add:

```swift
var siteRoutingManager = SiteRoutingManager()
```

- [ ] **Step 2: Wire dependencies in BrowserManager setup**

Find where `BrowserManager` wires up its managers' back-references. This is in `NookApp.swift` `setupApplicationLifecycle()` (around line 136) where `browserManager.nookSettings = settingsManager` is set. Add nearby:

```swift
browserManager.siteRoutingManager.settingsService = settingsManager
browserManager.siteRoutingManager.browserManager = browserManager
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Nook/Managers/BrowserManager/BrowserManager.swift App/NookApp.swift
git commit -m "feat(atc): wire SiteRoutingManager into BrowserManager and NookApp"
```

---

## Task 5: Integration Point 1 — `Tab.decidePolicyFor`

**Files:**
- Modify: `Nook/Models/Tab/Tab.swift` (around line 2751)

- [ ] **Step 1: Add the guard clause**

In `Tab.swift`, in the `decidePolicyFor navigationAction` method (line ~2710–2752), just before the final `decisionHandler(.allow)` at line ~2751, add:

```swift
// Air Traffic Control — route cross-domain navigations to designated spaces
if let url = navigationAction.request.url,
   let currentHost = self.url.host?.lowercased().replacingOccurrences(of: "www.", with: ""),
   let destHost = url.host?.lowercased().replacingOccurrences(of: "www.", with: ""),
   currentHost != destHost,
   browserManager?.siteRoutingManager.applyRoute(url: url, from: self) == true {
    decisionHandler(.cancel)
    return
}
```

This checks:
1. The navigation has a URL
2. The destination domain differs from the current tab's domain (cross-domain only)
3. A routing rule matches and was applied

If all true, navigation is cancelled — the tab was opened in the target space.

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Nook/Models/Tab/Tab.swift
git commit -m "feat(atc): add routing guard in decidePolicyFor navigation"
```

---

## Task 6: Integration Point 2 — `AppDelegate.handleIncoming`

**Files:**
- Modify: `App/AppDelegate.swift` (around line 301–308)

- [ ] **Step 1: Add the guard clause**

In `AppDelegate.swift`, in `handleIncoming(url:)` (line ~301), before `manager.presentExternalURL(url)`, add a check. The method currently looks like:

```swift
private func handleIncoming(url: URL) {
    guard let manager = browserManager else { return }
    Task { @MainActor in
        manager.presentExternalURL(url)
    }
}
```

Change it to:

```swift
private func handleIncoming(url: URL) {
    guard let manager = browserManager else { return }
    Task { @MainActor in
        // Air Traffic Control — route to designated space if a rule matches
        if manager.siteRoutingManager.applyRoute(url: url, from: nil) {
            return
        }
        manager.presentExternalURL(url)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add App/AppDelegate.swift
git commit -m "feat(atc): add routing guard for external URLs in AppDelegate"
```

---

## Task 7: Integration Point 3 — `Tab.createWebViewWith`

**Files:**
- Modify: `Nook/Models/Tab/Tab.swift` (around line 3163–3288)

- [ ] **Step 1: Add the guard clause**

In `Tab.swift`, in `createWebViewWith(configuration:for:windowFeatures:)` (line ~3163), after the OAuth check (line ~3201) and peek check (line ~3217), before the popup creation block (line ~3219), add:

```swift
// Air Traffic Control — route popup URLs to designated spaces
if let url = navigationAction.request.url,
   browserManager?.siteRoutingManager.applyRoute(url: url, from: self) == true {
    return nil
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Nook/Models/Tab/Tab.swift
git commit -m "feat(atc): add routing guard for popups in createWebViewWith"
```

---

## Task 8: Settings UI — SettingsTabs Enum

**Files:**
- Modify: `Nook/Components/Settings/SettingsUtils.swift`
- Modify: `Nook/Components/Settings/SettingsWindow.swift`

- [ ] **Step 1: Add enum case**

In `SettingsUtils.swift`, add `case airTrafficControl` to the `SettingsTabs` enum (after `sponsorBlock`, line ~16):

```swift
case airTrafficControl
```

- [ ] **Step 2: Add name, icon, iconColor**

In the `name` computed property, add:
```swift
case .airTrafficControl: return "Air Traffic Control"
```

In the `icon` computed property, add:
```swift
case .airTrafficControl: return "arrow.triangle.branch"
```

In the `iconColor` computed property, add:
```swift
case .airTrafficControl: return .mint
```

- [ ] **Step 3: Add to sidebar group**

In `sidebarGroups`, add `.airTrafficControl` to the privacy group (line ~72):

```swift
[.privacy, .adBlocker, .sponsorBlock, .airTrafficControl],
```

- [ ] **Step 4: Add detail pane routing**

In `SettingsWindow.swift`, in `SettingsDetailPane` body switch (line ~81), add before `case .profiles`:

```swift
case .airTrafficControl:
    AirTrafficControlSettingsView()
```

- [ ] **Step 5: Verify it compiles**

This will fail until the settings view exists (Task 9). That's expected — proceed to Task 9 immediately.

- [ ] **Step 6: Commit (combined with Task 9)**

---

## Task 9: Settings UI — AirTrafficControlSettingsView

**Files:**
- Create: `Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift`

- [ ] **Step 1: Create the settings view**

```swift
//
//  AirTrafficControlSettingsView.swift
//  Nook
//

import SwiftUI

struct AirTrafficControlSettingsView: View {
    @Environment(\.nookSettings) var nookSettings
    @EnvironmentObject var browserManager: BrowserManager

    @State private var showingAddSheet = false
    @State private var editingRule: SiteRoutingRule?

    var body: some View {
        Form {
            Section {
                Text("Automatically route websites to specific spaces. When you navigate to a matching domain, a new tab opens in the designated space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Rules") {
                if nookSettings.siteRoutingRules.isEmpty {
                    Text("No routing rules configured.")
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(nookSettings.siteRoutingRules) { rule in
                        ruleRow(rule)
                    }
                    .onDelete(perform: deleteRules)
                }
            }

            Section {
                HStack {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingAddSheet) {
            RuleEditSheet(
                browserManager: browserManager,
                onSave: { rule in
                    browserManager.siteRoutingManager.addRule(rule)
                }
            )
        }
        .sheet(item: $editingRule) { rule in
            RuleEditSheet(
                browserManager: browserManager,
                existingRule: rule,
                onSave: { updated in
                    browserManager.siteRoutingManager.updateRule(updated)
                }
            )
        }
    }

    private func ruleRow(_ rule: SiteRoutingRule) -> some View {
        let space = browserManager.tabManager.spaces.first(where: { $0.id == rule.targetSpaceId })
        let profile = browserManager.profileManager.profiles.first(where: { $0.id == rule.targetProfileId })

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(rule.domain)
                        .fontWeight(.medium)
                    if let pp = rule.pathPrefix, !pp.isEmpty {
                        Text(pp)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 4) {
                    if let space {
                        Image(systemName: space.icon)
                            .font(.caption)
                        Text(space.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Space deleted")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    if browserManager.profileManager.profiles.count > 1, let profile {
                        Text("(\(profile.name))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    var updated = rule
                    updated.isEnabled = newValue
                    browserManager.siteRoutingManager.updateRule(updated)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editingRule = rule
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            let rule = nookSettings.siteRoutingRules[index]
            browserManager.siteRoutingManager.deleteRule(id: rule.id)
        }
    }
}

// MARK: - Add/Edit Sheet

private struct RuleEditSheet: View {
    let browserManager: BrowserManager
    var existingRule: SiteRoutingRule?
    let onSave: (SiteRoutingRule) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nookSettings) var nookSettings

    @State private var domain: String = ""
    @State private var pathPrefix: String = ""
    @State private var selectedSpaceId: UUID?
    @State private var selectedProfileId: UUID?
    @State private var isEnabled: Bool = true
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Website") {
                    TextField("Domain (e.g. github.com)", text: $domain)
                        .textFieldStyle(.roundedBorder)
                    TextField("Path prefix (optional, e.g. /myorg)", text: $pathPrefix)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Destination") {
                    Picker("Space", selection: $selectedSpaceId) {
                        Text("Select a space").tag(nil as UUID?)
                        ForEach(groupedSpaces, id: \.profileName) { group in
                            Section(group.profileName) {
                                ForEach(group.spaces) { space in
                                    Label(space.name, systemImage: space.icon)
                                        .tag(space.id as UUID?)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }

                if let error = validationError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(existingRule != nil ? "Save" : "Add Rule") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(domain.trimmingCharacters(in: .whitespaces).isEmpty || selectedSpaceId == nil)
            }
            .padding()
        }
        .frame(width: 400, height: 360)
        .onAppear {
            if let rule = existingRule {
                domain = rule.domain
                pathPrefix = rule.pathPrefix ?? ""
                selectedSpaceId = rule.targetSpaceId
                selectedProfileId = rule.targetProfileId
                isEnabled = rule.isEnabled
            }
        }
        .onChange(of: selectedSpaceId) { _, newValue in
            // Auto-set profileId when space is selected
            if let spaceId = newValue,
               let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) {
                // Use space's profile, or fall back to default profile for unassigned spaces
                selectedProfileId = space.profileId ?? browserManager.profileManager.profiles.first?.id
            }
        }
    }

    private var groupedSpaces: [(profileName: String, spaces: [Space])] {
        let profiles = browserManager.profileManager.profiles.filter { !$0.isEphemeral }
        var result = profiles.map { profile in
            let spaces = browserManager.tabManager.spaces.filter { $0.profileId == profile.id }
            return (profileName: profile.name, spaces: spaces)
        }
        let unassigned = browserManager.tabManager.spaces.filter { $0.profileId == nil && !$0.isEphemeral }
        if !unassigned.isEmpty {
            result.append((profileName: "Unassigned", spaces: unassigned))
        }
        return result
    }

    private func save() {
        let normalized = SiteRoutingRule.normalizeDomain(domain)
        guard !normalized.isEmpty else {
            validationError = "Domain is required."
            return
        }

        let pp = pathPrefix.trimmingCharacters(in: .whitespaces)
        let effectivePathPrefix: String? = pp.isEmpty ? nil : pp

        // Check for duplicates (exclude current rule if editing)
        let isDuplicate = nookSettings.siteRoutingRules.contains { existing in
            existing.id != existingRule?.id &&
            existing.domain == normalized &&
            existing.pathPrefix == effectivePathPrefix
        }
        if isDuplicate {
            validationError = "A rule for this domain and path already exists."
            return
        }

        guard let spaceId = selectedSpaceId,
              let profileId = selectedProfileId else {
            validationError = "Please select a target space."
            return
        }

        let rule = SiteRoutingRule(
            id: existingRule?.id ?? UUID(),
            domain: normalized,
            pathPrefix: effectivePathPrefix,
            targetSpaceId: spaceId,
            targetProfileId: profileId,
            isEnabled: isEnabled
        )
        onSave(rule)
        dismiss()
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit (combined with Task 8)**

```bash
git add Nook/Components/Settings/SettingsUtils.swift Nook/Components/Settings/SettingsWindow.swift Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift
git commit -m "feat(atc): add Air Traffic Control settings page"
```

---

## Task 10: Smoke Test — Full Build and Manual Verification

- [ ] **Step 1: Clean build**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build clean build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED with no warnings related to SiteRouting/AirTrafficControl

- [ ] **Step 2: Manual verification checklist**

Launch the app and verify:
1. Settings → Air Traffic Control page appears in sidebar
2. Can add a rule (e.g., `github.com` → a space)
3. Rule persists after app restart
4. Can toggle rule enabled/disabled
5. Can delete a rule
6. Can edit a rule (double-click)

- [ ] **Step 3: Test routing behavior**

1. Add a rule: `github.com` → Space "Dev"
2. From a different space, navigate to `github.com` via a link
3. Verify: new tab opens in "Dev" space, original tab stays put
4. Verify: navigating within `github.com` (same domain) does NOT re-trigger routing

- [ ] **Step 4: Test external URL routing**

1. With a rule for `github.com` → Space "Dev"
2. Open a `github.com` URL from Terminal: `open https://github.com`
3. Verify: opens directly in "Dev" space, no mini window

- [ ] **Step 5: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix(atc): address issues found during smoke test"
```
