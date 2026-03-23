# Local LLM Tab Organizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an on-device LLM (Qwen2.5-0.5B via MLX Swift) that organizes tabs into folders, renames cluttered titles, sorts by topic, and detects duplicates — all triggered on-demand with a preview-and-accept flow.

**Architecture:** New `TabOrganizerManager` module with 5 files: engine (MLX lifecycle), prompt builder, plan parser, applier (calls TabManager APIs), and coordinator. Requires a `displayNameOverride` property added to the Tab model and both persistence paths. MLX Swift added via SPM.

**Tech Stack:** Swift 5, SwiftUI, MLX Swift (`mlx-swift-lm`), Qwen2.5-0.5B-Instruct-4bit

**Spec:** `docs/superpowers/specs/2026-03-22-local-llm-tab-organizer-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift` | Public coordinator: orchestrates organize flow, holds plan state, undo |
| `Nook/Managers/TabOrganizerManager/LocalLLMEngine.swift` | MLX model lifecycle: download, load, generate, unload |
| `Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift` | Builds structured prompt from tab metadata |
| `Nook/Managers/TabOrganizerManager/TabOrganizationPlan.swift` | Codable structs for parsed model output + JSON parsing |
| `Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift` | Maps plan actions to TabManager API calls, snapshot/undo |
| `Nook/Components/TabOrganizer/TabOrganizerPreviewSheet.swift` | SwiftUI preview sheet with checkboxes for accept/reject |

### Modified Files

| File | Change |
|------|--------|
| `Nook/Models/Tab/Tab.swift:47` | Add `displayNameOverride: String?` property and `displayName` computed property |
| `Nook/Models/Tab/TabsModel.swift:12-58` | Add `displayNameOverride` to `TabEntity` |
| `Nook/Managers/TabManager/TabManager.swift:33-50` | Add `displayNameOverride` to `SnapshotTab` |
| `Nook/Managers/TabManager/TabManager.swift:206-236` | Update `upsertTab()` to persist `displayNameOverride` |
| `Nook/Managers/TabManager/TabManager.swift:2025-2047` | Update `toRuntime()` to restore `displayNameOverride` |
| `Nook/Managers/TabManager/TabManager.swift:2342-2396` | Update `_buildSnapshot()` to include `displayNameOverride` |
| `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift:95` | Use `tab.displayName` instead of `tab.name` |
| `App/NookApp.swift:18-57` | Create and inject `TabOrganizerManager` |
| `App/NookCommands.swift` | Add "Organize Tabs" command |
| `Navigation/Sidebar/SpaceContextMenu.swift` | Add "Organize Tabs" menu item |
| `Settings/NookSettingsService.swift` | Add `tabOrganizerEnabled`, `tabOrganizerIdleTimeout`, `tabOrganizerModelDownloaded` |

---

## Task 1: Add `displayNameOverride` to Tab Model

This is a prerequisite for the entire feature — the Tab model needs a user-settable display name that survives page title updates.

**Files:**
- Modify: `Nook/Models/Tab/Tab.swift:47` (add property)
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift:95` (use displayName)

### Steps

- [ ] **Step 1: Add `displayNameOverride` property to Tab**

In `Nook/Models/Tab/Tab.swift`, near line 47 where `name` is declared, add:

```swift
var displayNameOverride: String? = nil

/// Display name for sidebar. Prefers user/AI override, falls back to page title.
var displayName: String {
    displayNameOverride ?? name
}
```

- [ ] **Step 2: Update sidebar to use `displayName`**

In `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift` at line 95, change:

```swift
// Before:
Text(tab.name)
// After:
Text(tab.displayName)
```

Search for any other places that render `tab.name` in the sidebar and update them too. Check `EssentialTab.swift`, `FolderTab.swift`, and similar sidebar components.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Tab names still display normally since `displayNameOverride` is nil by default.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: add displayNameOverride to Tab model for AI tab renaming"
```

---

## Task 2: Persist `displayNameOverride` in Both Persistence Paths

The Tab model has dual persistence: SwiftData (`TabEntity`) and atomic snapshots (`SnapshotTab`). Both must include the new field.

**Files:**
- Modify: `Nook/Models/Tab/TabsModel.swift:12-58` (TabEntity)
- Modify: `Nook/Managers/TabManager/TabManager.swift:33-50` (SnapshotTab)
- Modify: `Nook/Managers/TabManager/TabManager.swift:206-236` (upsertTab)
- Modify: `Nook/Managers/TabManager/TabManager.swift:2025-2047` (toRuntime)
- Modify: `Nook/Managers/TabManager/TabManager.swift:2342-2396` (_buildSnapshot)

### Steps

- [ ] **Step 1: Add to TabEntity (SwiftData)**

In `Nook/Models/Tab/TabsModel.swift`, inside the `TabEntity` class (around line 27), add:

```swift
var displayNameOverride: String?
```

- [ ] **Step 2: Add to SnapshotTab (Codable)**

In `Nook/Managers/TabManager/TabManager.swift`, inside the `SnapshotTab` struct (around line 33-50), add:

```swift
let displayNameOverride: String?
```

- [ ] **Step 3: Update `_buildSnapshot()` to include field**

In `_buildSnapshot()` (around line 2342), wherever `SnapshotTab` is constructed (there are 3 places: global pinned, space-pinned, regular tabs), add `displayNameOverride: tab.displayNameOverride` to each constructor call.

- [ ] **Step 4: Update `upsertTab()` to persist field**

In `upsertTab()` (around line 206), add to both the update path and the insert path:

```swift
// Update path (around line 210-220):
existing.displayNameOverride = snapshot.displayNameOverride

// Insert path (around line 222-236):
// Add displayNameOverride to the TabEntity constructor
```

- [ ] **Step 5: Update `toRuntime()` to restore field**

In the method that converts `SnapshotTab` or `TabEntity` back to a runtime `Tab` (around line 2025), add:

```swift
tab.displayNameOverride = snapshot.displayNameOverride  // or entity.displayNameOverride
```

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Existing tabs load normally (nil override = no change).

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: persist displayNameOverride in TabEntity and SnapshotTab"
```

---

## Task 3: Add MLX Swift SPM Dependencies

Add the MLX LLM package to the Xcode project. The package `mlx-swift-lm` (formerly `mlx-swift-transformers`) includes `mlx-swift` as a transitive dependency.

**Files:**
- Modify: `Nook.xcodeproj/project.pbxproj` (add package dependencies)

### Steps

- [ ] **Step 1: Add MLX Swift LM package via Xcode**

Open Xcode and add this SPM package:
- `https://github.com/ml-explore/mlx-swift-lm` (pin to latest stable release)

Link the `MLXLLM` product to the Nook target. The `mlx-swift` core library is pulled in transitively.

Alternatively, from the command line, edit the project to add package dependencies. The Xcode GUI is easier for SPM additions.

- [ ] **Step 2: Verify resolution**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build -resolvePackageDependencies 2>&1 | tail -10
```

Expected: Packages resolve successfully.

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED with new dependencies.

- [ ] **Step 4: Commit**

```bash
git add Nook.xcodeproj/project.pbxproj Nook.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved && git commit -m "deps: add mlx-swift-lm SPM package for local LLM inference"
```

---

## Task 4: Implement `LocalLLMEngine`

The engine manages model download, loading, inference, and unloading. Uses `mlx-swift-lm` APIs: `LLMModelFactory` for loading, `MLXLMCommon.generate` for inference.

**Files:**
- Create: `Nook/Managers/TabOrganizerManager/LocalLLMEngine.swift`

### Steps

- [ ] **Step 1: Create the file**

Create `Nook/Managers/TabOrganizerManager/LocalLLMEngine.swift`:

```swift
import Foundation
import MLX
import MLXLLM
import MLXLMCommon

@Observable
@MainActor
final class LocalLLMEngine {

    // MARK: - Types

    enum Status: Sendable, Equatable {
        case notDownloaded
        case downloading(Double)
        case ready
        case loading
        case loaded
        case generating
        case error(String)
    }

    // MARK: - Properties

    private(set) var status: Status = .notDownloaded

    private var modelContainer: ModelContainer?
    private var idleTimer: Timer?
    private let idleTimeout: TimeInterval
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private static let modelId = "mlx-community/Qwen2.5-0.5B-Instruct-4bit"

    // MARK: - Init

    init(idleTimeout: TimeInterval = 300) {
        self.idleTimeout = idleTimeout
        checkModelAvailability()
        setupMemoryPressureMonitoring()
    }

    deinit {
        memoryPressureSource?.cancel()
    }

    // MARK: - Public

    func ensureDownloaded() async throws {
        guard status == .notDownloaded || {
            if case .error = status { return true }
            return false
        }() else { return }

        status = .downloading(0.0)

        do {
            // LLMModelFactory.shared.loadContainer downloads if needed
            // We do a pre-download by loading the model configuration
            let config = ModelConfiguration(id: Self.modelId)
            _ = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    self.status = .downloading(progress.fractionCompleted)
                }
            }
            // Model is now downloaded and loaded; store it
            status = .ready
        } catch {
            status = .error("Download failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Generate text from a system prompt + user prompt using chat template.
    func generate(
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 1024
    ) async throws -> String {
        if modelContainer == nil {
            try await loadModel()
        }

        status = .generating
        resetIdleTimer()

        defer { status = .loaded }

        guard let container = modelContainer else {
            throw LocalLLMError.modelNotLoaded
        }

        let result = try await container.perform { context in
            let messages: [[String: String]] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ]
            let input = try await context.processor.prepare(
                input: .init(messages: messages)
            )
            let params = GenerateParameters(temperature: 0.3)

            var output = [Int]()
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: params,
                context: context
            ) { tokens in
                output.append(contentsOf: tokens)
                if output.count >= maxTokens {
                    return .stop
                }
                return .more
            }
            return result.output
        }

        return result
    }

    func unload() {
        modelContainer = nil
        idleTimer?.invalidate()
        idleTimer = nil
        status = .ready
    }

    // MARK: - Private

    private func loadModel() async throws {
        status = .loading

        do {
            let config = ModelConfiguration(id: Self.modelId)
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { progress in
                Task { @MainActor in
                    if case .loading = self.status {
                        self.status = .downloading(progress.fractionCompleted)
                    }
                }
            }
            self.modelContainer = container
            status = .loaded
            resetIdleTimer()
        } catch {
            status = .error("Failed to load model: \(error.localizedDescription)")
            throw error
        }
    }

    private func checkModelAvailability() {
        // On init, assume not downloaded. The actual check happens when user triggers organize.
        // LLMModelFactory handles caching internally.
        status = .notDownloaded
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.unload()
            }
        }
    }

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.unload()
            }
        }
        source.resume()
        self.memoryPressureSource = source
    }
}

// MARK: - Errors

enum LocalLLMError: LocalizedError {
    case modelNotLoaded
    case downloadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Model is not loaded"
        case .downloadFailed(let msg): return "Download failed: \(msg)"
        case .generationFailed(let msg): return "Generation failed: \(msg)"
        }
    }
}
```

**Important:** The exact `mlx-swift-lm` API evolves. The key pattern is:
1. `LLMModelFactory.shared.loadContainer(configuration:)` — downloads + loads
2. `container.perform { context in ... }` — inference in context
3. `context.processor.prepare(input:)` — tokenize with chat template
4. `MLXLMCommon.generate(input:parameters:context:)` — generate tokens

If the API has changed, consult `mlx-swift-lm` examples (e.g., `mlx-swift-chat`) for the current correct pattern. The lifecycle management (idle timer, memory pressure, status tracking) is stable regardless of API details.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED. Fix any MLX API mismatches based on actual library version.

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/TabOrganizerManager/LocalLLMEngine.swift && git commit -m "feat: add LocalLLMEngine for MLX model lifecycle"
```

---

## Task 5: Implement `TabOrganizationPrompt`

Builds the structured prompt from tab metadata using integer indices. Returns separate system and user prompts for proper chat template usage.

**Files:**
- Create: `Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift`

### Steps

- [ ] **Step 1: Create the file**

```swift
import Foundation

struct TabInput {
    let index: Int
    let tab: Tab
}

enum TabOrganizationPrompt {

    static let maxTabs = 60

    struct Prompt {
        let system: String
        let user: String
    }

    static func build(
        tabs: [TabInput],
        spaceName: String,
        existingFolderNames: [String]
    ) -> Prompt {
        let systemPrompt = """
        You organize browser tabs. Given a numbered list of tabs, output JSON with this exact schema:
        {"groups":[{"name":"short name","tabs":[1,2,5]}],"renames":[{"tab":1,"name":"shorter name"}],"sort":[3,1,2,5,4],"duplicates":[{"keep":1,"close":[3]}]}

        Rules:
        - Group by topic/purpose, not by domain
        - Group names: 1-3 words
        - Only rename tabs with cluttered titles (ads, long product names, repeated site names)
        - Only flag true duplicates (same page or same content, different URL)
        - Output ONLY valid JSON, nothing else
        """

        let folderContext = existingFolderNames.isEmpty
            ? ""
            : ", \(existingFolderNames.count) existing folders (\(existingFolderNames.joined(separator: ", ")))"

        var userPrompt = "Space \"\(spaceName)\", \(tabs.count) unfiled tabs\(folderContext):\n"

        for input in tabs {
            let title = input.tab.displayName
            let url = input.tab.url
            // Use host + path prefix to keep URLs short
            let shortURL: String
            if let host = url.host {
                let path = String(url.path.prefix(60))
                shortURL = "\(host)\(path)"
            } else {
                shortURL = url.absoluteString.prefix(80).description
            }
            userPrompt += "\(input.index). \"\(title)\" | \(shortURL)\n"
        }

        return Prompt(system: systemPrompt, user: userPrompt)
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift && git commit -m "feat: add TabOrganizationPrompt for building LLM prompts from tabs"
```

---

## Task 6: Implement `TabOrganizationPlan`

Codable structs for model output + resilient JSON parsing. Uses stored `let id` properties (not computed) for stable `Identifiable` conformance.

**Files:**
- Create: `Nook/Managers/TabOrganizerManager/TabOrganizationPlan.swift`

### Steps

- [ ] **Step 1: Create the file**

```swift
import Foundation

struct TabOrganizationPlan: Codable {
    struct Group: Codable, Identifiable {
        let id: UUID
        let name: String
        let tabs: [Int]

        private enum CodingKeys: String, CodingKey {
            case name, tabs
        }

        init(name: String, tabs: [Int]) {
            self.id = UUID()
            self.name = name
            self.tabs = tabs
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.name = try container.decode(String.self, forKey: .name)
            self.tabs = try container.decode([Int].self, forKey: .tabs)
        }
    }

    struct Rename: Codable, Identifiable {
        let id: UUID
        let tab: Int
        let name: String

        private enum CodingKeys: String, CodingKey {
            case tab, name
        }

        init(tab: Int, name: String) {
            self.id = UUID()
            self.tab = tab
            self.name = name
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.tab = try container.decode(Int.self, forKey: .tab)
            self.name = try container.decode(String.self, forKey: .name)
        }
    }

    struct DuplicateSet: Codable, Identifiable {
        let id: UUID
        let keep: Int
        let close: [Int]

        private enum CodingKeys: String, CodingKey {
            case keep, close
        }

        init(keep: Int, close: [Int]) {
            self.id = UUID()
            self.keep = keep
            self.close = close
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = UUID()
            self.keep = try container.decode(Int.self, forKey: .keep)
            self.close = try container.decode([Int].self, forKey: .close)
        }
    }

    let groups: [Group]
    let renames: [Rename]
    let sort: [Int]?
    let duplicates: [DuplicateSet]
}

// MARK: - Parsing

enum TabOrganizationPlanParser {

    enum ParseError: LocalizedError {
        case noJSON
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .noJSON: return "No JSON found in model output"
            case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
            }
        }
    }

    /// Parse model output into a plan, with fallback strategies for malformed JSON.
    static func parse(_ output: String, validRange: ClosedRange<Int>) throws -> TabOrganizationPlan {
        let cleaned = output.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strategy 1: Direct decode
        if let plan = try? decode(cleaned) {
            return validate(plan, validRange: validRange)
        }

        // Strategy 2: Strip markdown fences
        let stripped = stripMarkdownFences(cleaned)
        if let plan = try? decode(stripped) {
            return validate(plan, validRange: validRange)
        }

        // Strategy 3: Extract first balanced JSON object
        if let jsonBlock = extractFirstJSONObject(cleaned),
           let plan = try? decode(jsonBlock) {
            return validate(plan, validRange: validRange)
        }

        throw ParseError.noJSON
    }

    private static func decode(_ string: String) throws -> TabOrganizationPlan {
        let data = Data(string.utf8)
        let decoder = JSONDecoder()
        return try decoder.decode(TabOrganizationPlan.self, from: data)
    }

    private static func stripMarkdownFences(_ string: String) -> String {
        var result = string
        if let startRange = result.range(of: "```json") ?? result.range(of: "```") {
            result = String(result[startRange.upperBound...])
        }
        if let endRange = result.range(of: "```", options: .backwards) {
            result = String(result[..<endRange.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFirstJSONObject(_ string: String) -> String? {
        guard let start = string.firstIndex(of: "{") else { return nil }
        var depth = 0
        for (i, char) in string[start...].enumerated() {
            if char == "{" { depth += 1 }
            if char == "}" { depth -= 1 }
            if depth == 0 {
                let endIndex = string.index(start, offsetBy: i)
                return String(string[start...endIndex])
            }
        }
        return nil
    }

    /// Remove entries with out-of-range indices
    private static func validate(_ plan: TabOrganizationPlan, validRange: ClosedRange<Int>) -> TabOrganizationPlan {
        let groups = plan.groups.map { group in
            TabOrganizationPlan.Group(
                name: group.name,
                tabs: group.tabs.filter { validRange.contains($0) }
            )
        }.filter { !$0.tabs.isEmpty }

        let renames = plan.renames.filter { validRange.contains($0.tab) }

        let sort = plan.sort?.filter { validRange.contains($0) }

        let duplicates = plan.duplicates.compactMap { dup -> TabOrganizationPlan.DuplicateSet? in
            guard validRange.contains(dup.keep) else { return nil }
            let validClose = dup.close.filter { validRange.contains($0) }
            guard !validClose.isEmpty else { return nil }
            return TabOrganizationPlan.DuplicateSet(keep: dup.keep, close: validClose)
        }

        return TabOrganizationPlan(
            groups: groups,
            renames: renames,
            sort: sort,
            duplicates: duplicates
        )
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/TabOrganizerManager/TabOrganizationPlan.swift && git commit -m "feat: add TabOrganizationPlan with resilient JSON parsing"
```

---

## Task 7: Implement `TabOrganizationApplier`

Maps plan actions to TabManager API calls. Handles snapshotting for undo.

**Key API notes from `TabManager.swift`:**
- `createFolder(for spaceId: UUID, name: String = "New Folder")` — line 829, returns the folder
- `moveTabToFolder(tab: Tab, folderId: UUID)` — line 907, requires `tab.spaceId != nil`, sets `isSpacePinned = true`
- `removeTab(_ id: UUID)` — line 950, takes UUID not Tab, deactivates pinned tabs instead of closing
- `unpinTab(_ tab: Tab)` — line 1862, unpins global pinned tabs
- `unpinTabFromSpace(_ tab: Tab)` — line 1950, unpins space-pinned tabs (including folder members)
- `deleteFolder(_ folderId: UUID)` — deletes a folder
- `persistSnapshot()` — line 2286, triggers atomic persistence
- `tabs(in space: Space) -> [Tab]` — line 2509, returns regular (unfiled) tabs for a space

**Files:**
- Create: `Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift`

### Steps

- [ ] **Step 1: Create the file**

```swift
import Foundation

// MARK: - Snapshot for Undo

struct TabSnapshot {
    struct TabState {
        let tabId: UUID
        let spaceId: UUID?
        let folderId: UUID?
        let index: Int
        let isPinned: Bool
        let isSpacePinned: Bool
        let displayNameOverride: String?
    }
    struct ClosedTabState {
        let tabId: UUID
        let url: URL
        let name: String
        let spaceId: UUID?
        let folderId: UUID?
        let index: Int
        let isPinned: Bool
        let isSpacePinned: Bool
        let displayNameOverride: String?
    }
    let tabStates: [TabState]
    let createdFolderIds: [UUID]
    let closedTabs: [ClosedTabState]
}

// MARK: - Accepted Changes

struct AcceptedChanges {
    var acceptedGroupIds: Set<UUID>
    var acceptedRenameIds: Set<UUID>
    var acceptedDuplicateIds: Set<UUID>
    var applySortOrder: Bool
}

// MARK: - Applier

@MainActor
enum TabOrganizationApplier {

    /// Take a snapshot of current tab state before applying changes.
    static func snapshot(tabs: [Tab]) -> [TabSnapshot.TabState] {
        tabs.map { tab in
            TabSnapshot.TabState(
                tabId: tab.id,
                spaceId: tab.spaceId,
                folderId: tab.folderId,
                index: tab.index,
                isPinned: tab.isPinned,
                isSpacePinned: tab.isSpacePinned,
                displayNameOverride: tab.displayNameOverride
            )
        }
    }

    /// Apply accepted changes from the plan.
    /// Returns a TabSnapshot that can be used to undo.
    static func apply(
        plan: TabOrganizationPlan,
        accepted: AcceptedChanges,
        tabMapping: [Int: Tab],
        spaceId: UUID,
        tabManager: TabManager
    ) -> TabSnapshot {
        // Snapshot before changes
        let allAffectedTabs = Array(tabMapping.values)
        let preStates = snapshot(tabs: allAffectedTabs)
        var createdFolderIds: [UUID] = []
        var closedTabs: [TabSnapshot.ClosedTabState] = []

        // 1. Apply groups — create folders and move tabs
        for group in plan.groups where accepted.acceptedGroupIds.contains(group.id) {
            let folder = tabManager.createFolder(for: spaceId, name: group.name)
            createdFolderIds.append(folder.id)

            for tabIndex in group.tabs {
                guard let tab = tabMapping[tabIndex] else { continue }
                guard tab.spaceId != nil else { continue }
                tabManager.moveTabToFolder(tab: tab, folderId: folder.id)
            }
        }

        // 2. Apply renames
        for rename in plan.renames where accepted.acceptedRenameIds.contains(rename.id) {
            guard let tab = tabMapping[rename.tab] else { continue }
            tab.displayNameOverride = rename.name
        }

        // 3. Close duplicates
        for dupSet in plan.duplicates where accepted.acceptedDuplicateIds.contains(dupSet.id) {
            for tabIndex in dupSet.close {
                guard let tab = tabMapping[tabIndex] else { continue }

                // Snapshot full state before closing
                closedTabs.append(TabSnapshot.ClosedTabState(
                    tabId: tab.id,
                    url: tab.url,
                    name: tab.name,
                    spaceId: tab.spaceId,
                    folderId: tab.folderId,
                    index: tab.index,
                    isPinned: tab.isPinned,
                    isSpacePinned: tab.isSpacePinned,
                    displayNameOverride: tab.displayNameOverride
                ))

                // Unpin if needed before removing
                if tab.isPinned {
                    tabManager.unpinTab(tab)
                } else if tab.isSpacePinned {
                    tabManager.unpinTabFromSpace(tab)
                }

                tabManager.removeTab(tab.id)
            }
        }

        // 4. Apply sort order — set indices directly, persist once
        if accepted.applySortOrder, let sortOrder = plan.sort {
            for (newIndex, tabIndex) in sortOrder.enumerated() {
                guard let tab = tabMapping[tabIndex] else { continue }
                tab.index = newIndex
            }
            tabManager.persistSnapshot()
        }

        return TabSnapshot(
            tabStates: preStates,
            createdFolderIds: createdFolderIds,
            closedTabs: closedTabs
        )
    }

    /// Undo a previous organization by restoring the snapshot.
    static func undo(
        snapshot: TabSnapshot,
        spaceId: UUID,
        tabManager: TabManager
    ) {
        // 1. Delete folders that were created
        for folderId in snapshot.createdFolderIds {
            tabManager.deleteFolder(folderId)
        }

        // 2. Restore tab states (for tabs that still exist)
        for state in snapshot.tabStates {
            guard let tab = tabManager.allTabs.first(where: { $0.id == state.tabId }) else { continue }
            tab.spaceId = state.spaceId
            tab.folderId = state.folderId
            tab.index = state.index
            tab.isPinned = state.isPinned
            tab.isSpacePinned = state.isSpacePinned
            tab.displayNameOverride = state.displayNameOverride
        }

        // 3. Recreate closed tabs from stored state
        for closed in snapshot.closedTabs {
            // Construct a new Tab with the saved state and add it
            let tab = Tab(
                url: closed.url,
                name: closed.name,
                spaceId: closed.spaceId ?? spaceId,
                index: closed.index
            )
            tab.displayNameOverride = closed.displayNameOverride
            tab.folderId = closed.folderId
            tab.isPinned = closed.isPinned
            tab.isSpacePinned = closed.isSpacePinned
            tabManager.addTab(tab)
        }

        tabManager.persistSnapshot()
    }
}
```

**Note:** The `Tab` initializer and `tabManager.addTab(_:)` signatures should be verified against the actual codebase. `Tab(url:name:spaceId:index:)` may require additional parameters (e.g., `browserManager`). Check `Tab.swift` for the init signature and adjust the undo code accordingly.

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

Fix any API signature mismatches based on actual `TabManager` and `Tab` methods.

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift && git commit -m "feat: add TabOrganizationApplier with undo support"
```

---

## Task 8: Implement `TabOrganizerManager`

The public coordinator that ties everything together.

**Key API note:** `tabManager.tabs(in: Space)` returns unfiled regular tabs (already excludes pinned and folder tabs), so no additional filtering needed.

**Files:**
- Create: `Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift`

### Steps

- [ ] **Step 1: Create the file**

```swift
import Foundation

@Observable
@MainActor
final class TabOrganizerManager {

    // MARK: - Properties

    let engine: LocalLLMEngine

    private(set) var plan: TabOrganizationPlan?
    private(set) var tabMapping: [Int: Tab] = [:]
    private(set) var ungroupedTabs: [TabInput] = []
    private(set) var isOrganizing: Bool = false
    private(set) var showPreview: Bool = false
    private(set) var error: String?

    private var undoSnapshot: TabSnapshot?
    private var undoSpaceId: UUID?
    private(set) var canUndo: Bool = false

    // MARK: - Init

    init(engine: LocalLLMEngine = LocalLLMEngine()) {
        self.engine = engine
    }

    // MARK: - Public

    func organizeTabs(in space: Space, using tabManager: TabManager) async {
        guard !isOrganizing else { return }

        isOrganizing = true
        error = nil
        plan = nil
        showPreview = false

        defer { isOrganizing = false }

        // tabs(in:) returns regular unfiled tabs only (no pinned, no folder tabs)
        let unfiledTabs = tabManager.tabs(in: space)

        guard unfiledTabs.count >= 3 else {
            error = "Not enough tabs to organize (need at least 3 unfiled tabs)"
            return
        }

        guard unfiledTabs.count <= TabOrganizationPrompt.maxTabs else {
            error = "Too many tabs (\(unfiledTabs.count)). Maximum is \(TabOrganizationPrompt.maxTabs). Try organizing one space at a time."
            return
        }

        // Build index mapping (1-based for prompt)
        var mapping: [Int: Tab] = [:]
        var inputs: [TabInput] = []
        for (i, tab) in unfiledTabs.enumerated() {
            let index = i + 1
            mapping[index] = tab
            inputs.append(TabInput(index: index, tab: tab))
        }
        self.tabMapping = mapping

        // Build prompt
        let existingFolders = tabManager.folders(for: space.id).map(\.name)
        let prompt = TabOrganizationPrompt.build(
            tabs: inputs,
            spaceName: space.name,
            existingFolderNames: existingFolders
        )

        // Run inference
        do {
            let output = try await engine.generate(
                systemPrompt: prompt.system,
                userPrompt: prompt.user,
                maxTokens: 1024
            )
            let parsedPlan = try TabOrganizationPlanParser.parse(output, validRange: 1...unfiledTabs.count)
            self.plan = parsedPlan
            self.showPreview = true

            // Identify ungrouped tabs
            let groupedIndices = Set(parsedPlan.groups.flatMap(\.tabs))
            self.ungroupedTabs = inputs.filter { !groupedIndices.contains($0.index) }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func applyPlan(accepted: AcceptedChanges, spaceId: UUID, tabManager: TabManager) {
        guard let plan = self.plan else { return }

        let snapshot = TabOrganizationApplier.apply(
            plan: plan,
            accepted: accepted,
            tabMapping: tabMapping,
            spaceId: spaceId,
            tabManager: tabManager
        )

        self.undoSnapshot = snapshot
        self.undoSpaceId = spaceId
        self.canUndo = true
        self.plan = nil
        self.showPreview = false
        self.tabMapping = [:]
        self.ungroupedTabs = []
    }

    func undoLastOrganization(using tabManager: TabManager) {
        guard let snapshot = undoSnapshot, let spaceId = undoSpaceId else { return }
        TabOrganizationApplier.undo(snapshot: snapshot, spaceId: spaceId, tabManager: tabManager)
        self.undoSnapshot = nil
        self.undoSpaceId = nil
        self.canUndo = false
    }

    func dismissPlan() {
        plan = nil
        showPreview = false
        tabMapping = [:]
        ungroupedTabs = []
        error = nil
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift && git commit -m "feat: add TabOrganizerManager coordinator"
```

---

## Task 9: Add Settings Keys

**Files:**
- Modify: `Settings/NookSettingsService.swift`

### Steps

- [ ] **Step 1: Add settings properties**

In `Settings/NookSettingsService.swift`, add keys and properties following the existing pattern (property with `didSet` that persists to UserDefaults):

```swift
// Keys (add near line 17-50 where other keys are defined)
private static let tabOrganizerEnabledKey = "tabOrganizerEnabled"
private static let tabOrganizerModelDownloadedKey = "tabOrganizerModelDownloaded"
private static let tabOrganizerIdleTimeoutKey = "tabOrganizerIdleTimeout"

// Properties (add near other feature properties)
var tabOrganizerEnabled: Bool = true {
    didSet { userDefaults.set(tabOrganizerEnabled, forKey: Self.tabOrganizerEnabledKey) }
}

var tabOrganizerModelDownloaded: Bool = false {
    didSet { userDefaults.set(tabOrganizerModelDownloaded, forKey: Self.tabOrganizerModelDownloadedKey) }
}

var tabOrganizerIdleTimeout: TimeInterval = 300 {
    didSet { userDefaults.set(tabOrganizerIdleTimeout, forKey: Self.tabOrganizerIdleTimeoutKey) }
}
```

Also add loading from UserDefaults in the initializer (or wherever other settings are loaded from defaults):

```swift
tabOrganizerEnabled = userDefaults.object(forKey: Self.tabOrganizerEnabledKey) as? Bool ?? true
tabOrganizerModelDownloaded = userDefaults.object(forKey: Self.tabOrganizerModelDownloadedKey) as? Bool ?? false
tabOrganizerIdleTimeout = userDefaults.object(forKey: Self.tabOrganizerIdleTimeoutKey) as? TimeInterval ?? 300
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Settings/NookSettingsService.swift && git commit -m "feat: add tab organizer settings keys"
```

---

## Task 10: Wire Up Environment Injection

**Files:**
- Modify: `App/NookApp.swift`

### Steps

- [ ] **Step 1: Create and inject TabOrganizerManager**

In `App/NookApp.swift`, add the manager creation (near line 18-24 where other managers are created):

```swift
@State private var tabOrganizerManager = TabOrganizerManager()
```

Then add the environment injection (near line 44-57 where other `.environment()` calls are):

```swift
.environment(tabOrganizerManager)
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add App/NookApp.swift && git commit -m "feat: inject TabOrganizerManager into environment"
```

---

## Task 11: Build Preview Sheet UI

**Files:**
- Create: `Nook/Components/TabOrganizer/TabOrganizerPreviewSheet.swift`

### Steps

- [ ] **Step 1: Create the preview sheet**

```swift
import SwiftUI

struct TabOrganizerPreviewSheet: View {
    @Environment(TabOrganizerManager.self) private var organizer
    @Environment(\.dismiss) private var dismiss

    let spaceId: UUID
    let tabManager: TabManager

    @State private var acceptedGroups: Set<UUID> = []
    @State private var acceptedRenames: Set<UUID> = []
    @State private var acceptedDuplicates: Set<UUID> = []
    @State private var applySortOrder: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Organize Tabs")
                .font(.headline)
                .padding(.bottom, 4)

            if let plan = organizer.plan {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
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
                            Toggle("Apply suggested sort order", isOn: $applySortOrder)
                        }
                        if !organizer.ungroupedTabs.isEmpty {
                            ungroupedSection
                        }
                    }
                }
                .frame(maxHeight: 400)

                HStack {
                    Button("Cancel") {
                        organizer.dismissPlan()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Apply Selected") { applyChanges() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(acceptedGroups.isEmpty && acceptedRenames.isEmpty && acceptedDuplicates.isEmpty && !applySortOrder)
                }
            } else if let error = organizer.error {
                Text(error)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") {
                        organizer.dismissPlan()
                        dismiss()
                    }
                    Spacer()
                    Button("Retry") {
                        dismiss()
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .onAppear {
            if let plan = organizer.plan {
                acceptedGroups = Set(plan.groups.map(\.id))
                acceptedRenames = Set(plan.renames.map(\.id))
                acceptedDuplicates = Set(plan.duplicates.map(\.id))
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func groupsSection(_ groups: [TabOrganizationPlan.Group]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Groups", systemImage: "folder")
                .font(.subheadline.weight(.semibold))

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: binding(for: group.id, in: $acceptedGroups)) {
                        Text("\(group.name) (\(group.tabs.count) tabs)")
                    }
                    ForEach(group.tabs, id: \.self) { index in
                        if let tab = organizer.tabMapping[index] {
                            Text("  \u{2022} \(tab.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renamesSection(_ renames: [TabOrganizationPlan.Rename]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Renames", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))

            ForEach(renames) { rename in
                if let tab = organizer.tabMapping[rename.tab] {
                    Toggle(isOn: binding(for: rename.id, in: $acceptedRenames)) {
                        VStack(alignment: .leading) {
                            Text(tab.displayName)
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Text(rename.name)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func duplicatesSection(_ duplicates: [TabOrganizationPlan.DuplicateSet]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Duplicates", systemImage: "doc.on.doc")
                .font(.subheadline.weight(.semibold))

            ForEach(duplicates) { dup in
                Toggle(isOn: binding(for: dup.id, in: $acceptedDuplicates)) {
                    VStack(alignment: .leading) {
                        if let keepTab = organizer.tabMapping[dup.keep] {
                            Text("Keep: \(keepTab.displayName)")
                                .font(.caption)
                        }
                        ForEach(dup.close, id: \.self) { index in
                            if let tab = organizer.tabMapping[index] {
                                let isPinned = tab.isPinned || tab.isSpacePinned
                                HStack {
                                    Text("Close: \(tab.displayName)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                            .help("Pinned — will be unpinned before closing")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ungroupedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Ungrouped (\(organizer.ungroupedTabs.count) tabs)", systemImage: "list.bullet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(organizer.ungroupedTabs, id: \.index) { input in
                Text("  \u{2022} \(input.tab.displayName)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Helpers

    private func binding(for id: UUID, in set: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isOn in
                if isOn { set.wrappedValue.insert(id) }
                else { set.wrappedValue.remove(id) }
            }
        )
    }

    private func applyChanges() {
        organizer.applyPlan(
            accepted: AcceptedChanges(
                acceptedGroupIds: acceptedGroups,
                acceptedRenameIds: acceptedRenames,
                acceptedDuplicateIds: acceptedDuplicates,
                applySortOrder: applySortOrder
            ),
            spaceId: spaceId,
            tabManager: tabManager
        )
        dismiss()
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Nook/Components/TabOrganizer/TabOrganizerPreviewSheet.swift && git commit -m "feat: add TabOrganizerPreviewSheet UI"
```

---

## Task 12: Add Entry Points (Command Palette + Context Menu + Sheet Wiring)

Wire up the "Organize Tabs" action from command palette and space context menu, and present the preview sheet.

**Files:**
- Modify: `App/NookCommands.swift`
- Modify: `Navigation/Sidebar/SpaceContextMenu.swift` (or `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:175-202`)
- Modify: A parent view (e.g., `App/ContentView.swift` or the sidebar container) to present the sheet

### Steps

- [ ] **Step 1: Add "Organize Tabs" to space context menu**

In `Navigation/Sidebar/SpaceContextMenu.swift`, add a new menu item. Find the existing menu items (around lines 23-96) and add:

```swift
Divider()
Button("Organize Tabs") {
    Task {
        await tabOrganizerManager.organizeTabs(in: space, using: tabManager)
    }
}
```

The view needs access to `@Environment(TabOrganizerManager.self)`. Add this to the view's properties.

- [ ] **Step 2: Add "Organize Tabs" command to NookCommands**

In `App/NookCommands.swift`, add a keyboard-shortcut command following the existing pattern (lines 79-150):

```swift
Button("Organize Tabs") {
    NotificationCenter.default.post(name: .organizeTabsRequested, object: nil)
}
.keyboardShortcut("o", modifiers: [.command, .shift, .option])
```

Define the notification name:

```swift
extension Notification.Name {
    static let organizeTabsRequested = Notification.Name("organizeTabsRequested")
}
```

- [ ] **Step 3: Wire up sheet presentation**

In the appropriate parent view (the view that contains the sidebar — likely `ContentView.swift` or the window-level view), add a sheet modifier that watches `tabOrganizerManager.showPreview`:

```swift
.sheet(isPresented: Binding(
    get: { tabOrganizerManager.showPreview },
    set: { if !$0 { tabOrganizerManager.dismissPlan() } }
)) {
    TabOrganizerPreviewSheet(
        spaceId: currentSpace.id,
        tabManager: tabManager
    )
}
```

Also add a `.onReceive` for the notification (to handle the command palette trigger):

```swift
.onReceive(NotificationCenter.default.publisher(for: .organizeTabsRequested)) { _ in
    Task {
        await tabOrganizerManager.organizeTabs(in: currentSpace, using: tabManager)
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: add Organize Tabs entry points and sheet presentation"
```

---

## Task 13: Add "Reset Tab Name" Context Menu Item

The spec requires users be able to clear a display name override.

**Files:**
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift` (tab context menu)

### Steps

- [ ] **Step 1: Add context menu item**

In `SpaceTab.swift`, find the existing tab context menu and add:

```swift
if tab.displayNameOverride != nil {
    Button("Reset Tab Name") {
        tab.displayNameOverride = nil
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```

- [ ] **Step 3: Commit**

```bash
git add Nook/Components/Sidebar/SpaceSection/SpaceTab.swift && git commit -m "feat: add Reset Tab Name context menu item"
```

---

## Task 14: Integration Testing and Polish

End-to-end verification with real and mocked data.

### Steps

- [ ] **Step 1: Test with mocked engine output**

Create a temporary test or set a breakpoint to bypass the LLM and feed a known JSON response into `TabOrganizationPlanParser.parse()`, then apply via the applier. Verify:
- Folders are created with correct names
- Tabs move into the right folders
- Renames apply and persist across page navigations
- Duplicates are closed (including pinned ones after unpinning)
- Undo restores everything (tab positions, names, recreates closed tabs, deletes created folders)

- [ ] **Step 2: Test model download and inference**

Run the app, trigger "Organize Tabs", and verify:
- Download prompt appears with progress
- Download completes successfully
- Model loads and inference runs
- Preview sheet shows reasonable suggestions
- Apply works
- Undo works

- [ ] **Step 3: Test edge cases**

- Fewer than 3 unfiled tabs → appropriate error message
- All tabs already in folders → "Not enough tabs" (tabs(in:) returns empty)
- Model produces garbage JSON → shows error with retry
- Cancel during inference → returns to normal state
- Memory pressure → model unloads gracefully
- Idle timeout → model unloads after 5 minutes

- [ ] **Step 4: Final commit**

```bash
git add -A && git commit -m "feat: complete local LLM tab organizer integration"
```

---

## Dependency Order

```
Task 1 (displayNameOverride) ──┐
Task 2 (persistence)       ────┤
Task 3 (MLX SPM)           ────┤
                                ├── Task 4 (engine) ──┐
Task 9 (settings)          ────┤                      │
                                ├── Task 5 (prompt)    ├── Task 8 (manager) ── Task 10 (injection) ── Task 12 (entry points)
                                ├── Task 6 (plan)      │                                              │
                                └── Task 7 (applier) ──┘                      Task 11 (preview UI) ───┤
                                                                              Task 13 (reset name) ───┘
                                                                                                       │
                                                                              Task 14 (integration) ───┘
```

Tasks 1, 2, 3, and 9 can be done in parallel (no dependencies on each other).
Tasks 4, 5, 6, 7 depend on Task 1 (for `displayNameOverride`) and Task 3 (for MLX imports in Task 4).
Task 8 depends on Tasks 4-7.
Tasks 10-13 depend on Task 8.
Task 14 is last.
