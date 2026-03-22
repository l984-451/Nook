# Local LLM Tab Organizer

**Date:** 2026-03-22
**Status:** Draft

## Overview

An on-device, zero-network tab organization feature powered by a tiny LLM (Qwen2.5-0.5B via MLX Swift). The user triggers "Organize Tabs" from the command palette or context menu, the model analyzes tab titles and URLs, and proposes: groupings into folders, cleaner display names, sort order, and duplicate detection. The user previews and accepts/rejects suggestions before anything changes.

## Goals

- Fully local — no API keys, no network, no privacy concerns
- Fast — inference completes in a few seconds on Apple Silicon
- Non-destructive — user previews all changes before they apply, with undo support
- Lightweight — model loads lazily, unloads after idle timeout

## Non-Goals

- Replacing the existing AI chat system (this is separate, single-purpose)
- Running continuously or in the background
- Supporting non-Apple-Silicon Macs (macOS 15.5+ is ARM-only effectively)
- Custom model training or fine-tuning
- Reorganizing existing folder structures (only organizes unfiled tabs; preserves existing folders)

## Why not use the existing AI infrastructure (Ollama)?

The existing AI system supports Ollama for local inference, but it requires the user to install and run Ollama separately. This feature targets zero-setup: no external process, no configuration, no API keys. The model runs inside Nook's own process via MLX. This also avoids a runtime dependency on a third-party service being available.

---

## Architecture

### New Components

```
Nook/Managers/TabOrganizerManager/
├── TabOrganizerManager.swift      — Public API, coordinates the flow
├── LocalLLMEngine.swift           — MLX model lifecycle (load, infer, unload)
├── TabOrganizationPrompt.swift    — Prompt construction from tab metadata
├── TabOrganizationPlan.swift      — Parsed model output (the plan of changes)
└── TabOrganizationApplier.swift   — Applies accepted changes via TabManager
```

### Dependencies

Two new SPM packages:
- `mlx-swift` — Apple's MLX framework for Swift
- `mlx-swift-transformers` — Tokenizer and text generation pipeline

### Model

- **Qwen2.5-0.5B-Instruct** (4-bit quantized, MLX format)
- Size: ~350MB on disk
- Memory: ~400MB when loaded
- Source: Pre-converted MLX models on HuggingFace (`mlx-community/Qwen2.5-0.5B-Instruct-4bit`)
- **Delivery:** Downloaded on first use to `~/Library/Application Support/Nook/Models/`. Not bundled with the app to keep the DMG small.
- **Download resilience:** Use `mlx-swift-transformers` Hub download support which handles resumption. Verify SHA256 checksum after download.

---

## Tab Model Change: Display Name Override

**Critical prerequisite.** The `Tab` model currently has no concept of a user/AI-set display name — `updateTitle()` unconditionally overwrites `tab.name` on every page title change from KVO. An LLM-suggested rename would be immediately lost.

**Required change:** Add a `displayNameOverride: String?` property to `Tab`:

```swift
// Tab.swift
var displayNameOverride: String? = nil

/// The name to show in the sidebar. Prefers override, falls back to page title.
var displayName: String {
    displayNameOverride ?? name
}
```

- Sidebar rendering uses `tab.displayName` instead of `tab.name`
- `updateTitle()` continues to update `tab.name` but does NOT touch `displayNameOverride`
- User can clear the override (right-click → "Reset Tab Name")
- Persisted in both persistence paths:
  - **SwiftData:** Add `displayNameOverride: String?` to `TabEntity`
  - **Atomic snapshots:** Add `displayNameOverride: String?` to `SnapshotTab` (Codable struct in PersistenceActor)
  - **Snapshot build:** Update `_buildSnapshot()` in TabManager to include the field
  - **Snapshot restore:** Update `upsertTab()` in PersistenceActor and `toRuntime()` on SnapshotTab to read/write the field

---

## Component Design

### 1. LocalLLMEngine

`@MainActor @Observable` class, matching the `AIService` pattern used elsewhere in the codebase.

**Responsibilities:**
- Download model on first use (with progress reporting)
- Load model into memory (lazy, on first inference request)
- Run text generation with structured output
- Unload after idle timeout (default: 5 minutes) to reclaim ~400MB
- Report status for UI binding

**Key interface:**
```swift
@Observable
@MainActor
final class LocalLLMEngine {
    enum Status: Sendable {
        case notDownloaded
        case downloading(Double)  // 0.0–1.0
        case ready                // downloaded but not loaded
        case loading
        case loaded
        case generating
        case error(String)
    }

    private(set) var status: Status = .notDownloaded

    func ensureDownloaded() async throws
    func generate(prompt: String, maxTokens: Int = 1024) async throws -> String
    func unload()
}
```

**Threading model:** The class is `@MainActor` for safe `@Observable` tracking and UI binding. All heavy work (model loading, tokenization, MLX inference) runs via `Task.detached` to avoid blocking the main thread. The detached tasks capture only the model reference and prompt (both `Sendable`), then hop back to `MainActor` to update `status`. This matches how `AIService` handles streaming — `@MainActor` class with detached work for I/O.

**Memory pressure:** Registers for `NSNotification.Name.NSProcessInfoPowerStateDidChange` and `DispatchSource.makeMemoryPressureSource` to unload the model early under system memory pressure.

### 2. TabOrganizationPrompt

Pure function / struct. Takes tab metadata, produces the prompt string.

**Input:** Array of tab info structs. Also includes current space name and existing folder names for context.

**Key design decision: Use integer indices, not UUIDs.** UUIDs are 36 characters each and a small model may corrupt them during generation. Instead, tabs are numbered 1, 2, 3... in the prompt. The parser maps indices back to Tab UUIDs. This reduces token count by ~80% for the ID fields and eliminates corruption risk.

**Token budget:** Each tab entry is ~30-50 tokens (index + title + URL). System prompt is ~200 tokens. For 50 tabs: ~1500-2700 input tokens + ~500-1000 output tokens = ~2000-3700 total. Well within Qwen2.5-0.5B's 8K context window. **Maximum: 60 tabs per invocation.** Beyond that, the feature shows "Too many tabs — try organizing one space at a time."

**Prompt strategy:**

```
System: You organize browser tabs. Given a numbered list of tabs, output JSON:
{"groups":[{"name":"...","tabs":[1,2,5]}],
 "renames":[{"tab":1,"name":"shorter name"}],
 "sort":[3,1,2,5,4],
 "duplicates":[{"keep":1,"close":[3]}]}

Rules:
- Group by topic/purpose, not domain
- Group names: 1-3 words
- Only rename cluttered titles (ads, long product names)
- Only flag true duplicates (same page, different URL)
- Tabs already in folders: DO NOT include in groups
- Output ONLY valid JSON

User: Space "Research", 12 unfiled tabs, 2 existing folders (Shopping, Docs):
1. "Amazon.com: HDMI Cable 6ft Braided Gold..." | amazon.com/dp/B08X...
2. "Best HDMI Cables 2026 - Wirecutter" | nytimes.com/wirecutter/...
...
```

**Handling existing folders:** The prompt tells the model which tabs are already filed and excludes them from the tab list. The model only organizes unfiled (regular, non-pinned, non-folder) tabs. Existing folder structure is preserved.

### 3. TabOrganizationPlan

Codable struct parsed from the model's JSON output.

```swift
struct TabOrganizationPlan: Codable {
    struct Group: Codable, Identifiable {
        let id = UUID()
        let name: String
        let tabs: [Int]  // indices from prompt
    }
    struct Rename: Codable, Identifiable {
        let id = UUID()
        let tab: Int
        let name: String
    }
    struct DuplicateSet: Codable, Identifiable {
        let id = UUID()
        let keep: Int
        let close: [Int]
    }

    let groups: [Group]
    let renames: [Rename]
    let sort: [Int]?
    let duplicates: [DuplicateSet]
}
```

**Index validation:** After parsing, validate that all indices are within the valid range (1...tabCount). Discard any entries with invalid indices rather than failing the whole plan.

**Parsing resilience:** Small models sometimes produce slightly malformed JSON. The parser will:
1. Try strict `JSONDecoder`
2. Strip markdown fences (`` ```json ... ``` ``), trailing text, then retry
3. Extract the first `{...}` balanced block and retry
4. If all fail, surface "Couldn't parse suggestions — try again" with retry button

### 4. TabOrganizationApplier

Takes a `TabOrganizationPlan`, the user's accept/reject decisions, and an index→Tab mapping. Calls `TabManager` APIs.

**Mapping to actual TabManager APIs:**

| Plan action | TabManager API | Constraints |
|-------------|---------------|-------------|
| Create folder for group | `createFolder(for: spaceId, name: groupName)` | Space must exist; single call, no separate rename needed |
| Move tab to folder | `moveTabToFolder(tab, folderId)` | Tab must have non-nil `spaceId`; sets `isSpacePinned = true` |
| Rename tab | Set `tab.displayNameOverride` | New property (see Tab Model Change section) |
| Reorder tabs | Batch reorder (see below) | — |
| Close duplicate | `removeTab(tab.id)` | Cannot remove pinned/space-pinned tabs — must unpin first |

**Duplicate closing constraint:** `removeTab(_:)` deactivates pinned tabs rather than closing them. The applier must unpin before removing:
- **Global pinned tabs:** call `unpinTab(tab)` (alias: `removeFromEssentials(tab)`) first
- **Space-pinned tabs (including folder members):** call `unpinTabFromSpace(tab)` first
- Then call `removeTab(tab.id)` to close

The preview UI will show a warning icon next to pinned duplicate candidates.

**Batch reorder strategy:** Applying sort order one tab at a time triggers N persistence writes. The applier will:
1. Build the target index array from the plan
2. Set `tab.index` directly for each tab in the new order
3. Call `persistSnapshot()` once after all moves complete

This requires exposing a `batchReorder(tabIds: [UUID], in spaceId: UUID)` convenience on `TabManager` or having the applier directly set indices and trigger a single persistence flush. The implementation will determine the cleanest approach; worst case, the sequential `reorderRegular` calls work correctly, just with extra persistence writes (acceptable for a user-triggered one-shot operation).

### 5. TabOrganizerManager

The public-facing coordinator. Injected via `.environment()` from `NookApp` (matching the pattern used by `AIService`, `NookSettingsService`, and other `@Observable` managers).

```swift
@Observable
@MainActor
final class TabOrganizerManager {
    let engine: LocalLLMEngine

    private(set) var plan: TabOrganizationPlan?
    private(set) var tabMapping: [Int: Tab] = [:]  // index → Tab
    private(set) var isOrganizing: Bool = false
    private(set) var preApplySnapshot: TabSnapshot?  // for undo

    func organizeTabs(in space: Space, using tabManager: TabManager) async
    func applyPlan(_ plan: TabOrganizationPlan,
                   accepted: AcceptedChanges,
                   using tabManager: TabManager) async
    func undoLastOrganization(using tabManager: TabManager) async
    func dismissPlan()
}

struct AcceptedChanges {
    var acceptedGroups: Set<UUID>
    var acceptedRenames: Set<UUID>
    var acceptedDuplicates: Set<UUID>
    var applySortOrder: Bool
}
```

---

## Undo Support

Before applying any changes, the applier snapshots the affected tabs' state:

```swift
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
    let tabs: [TabState]
    let createdFolderIds: [UUID]       // folders created by the organize action
    let closedTabs: [ClosedTabState]   // full state of tabs closed as duplicates
}
```

`undoLastOrganization()`:
- Restores tab positions, folder assignments, pin states, and display name overrides
- Deletes folders that were created by the organize action
- Recreates closed duplicate tabs from `ClosedTabState` (stored in the snapshot itself, independent of the recently-closed stack, so intervening user actions don't corrupt undo)
- Only the most recent organize action is undoable (single-level undo)

---

## User Flow

1. User opens command palette (or right-clicks space header) → selects "Organize Tabs"
2. If model not downloaded: show download prompt with size (~350MB) and progress bar. One-time.
3. If >60 unfiled tabs in the space: show "Too many tabs — try organizing one space at a time" (or organize just the current space's unfiled tabs)
4. Model loads (if not already warm). Small spinner in status bar.
5. Inference runs (1-5 seconds).
6. **Preview sheet** appears showing:
   - Proposed folder groups with tab assignments (checkboxes per group)
   - Rename suggestions (toggle each on/off)
   - Duplicate pairs (toggle each, with warning on pinned tabs)
   - Sort order preview
   - **Ungrouped section** showing tabs the model left uncategorized
7. User clicks "Apply Selected" → snapshot taken → accepted changes execute
8. Status bar shows "Tabs organized — [Undo]" for 30 seconds
9. Model stays loaded for 5 minutes in case user wants to re-run

---

## Entry Points

Two ways to trigger:
1. **Command Palette** — "Organize Tabs" command registered in `NookCommands`
2. **Space context menu** — "Organize Tabs in [Space Name]" added to existing space right-click menu (in the space header context menu view)

Both call `TabOrganizerManager.organizeTabs(in:using:)`.

---

## Preview UI

A simple sheet (not a new window). Shows the plan as a checklist:

```
┌─ Organize Tabs ──────────────────────────┐
│                                          │
│ 📁 Groups                                │
│ ☑ Shopping (3 tabs)                      │
│   • HDMI Cable                           │
│   • USB-C Hub                            │
│   • Monitor Stand                        │
│ ☑ Documentation (4 tabs)                 │
│   • SwiftUI Docs                         │
│   • MLX README                           │
│   • Apple Dev Forums                     │
│   • Stack Overflow: MLX...               │
│                                          │
│ ✏️ Renames                                │
│ ☑ "Amazon.com: HDMI Cable 6ft..." → "HDMI Cable" │
│ ☑ "Stack Overflow: How to use..." → "SO: MLX Generation" │
│                                          │
│ 🔁 Duplicates                             │
│ ☑ Close "GitHub - mlx (tab 2)" (keeping tab 1) │
│                                          │
│ 📋 Ungrouped (2 tabs)                    │
│   • Settings - Google Account            │
│   • localhost:3000                        │
│                                          │
│           [Cancel]  [Apply Selected]     │
└──────────────────────────────────────────┘
```

SwiftUI view consuming `TabOrganizerManager.plan` and `tabMapping`.

---

## Error Handling

| Scenario | Behavior |
|----------|----------|
| Model download fails / interrupted | Retry button, error message. Download resumes from where it left off. |
| Model fails to load | Error state, suggest redownloading |
| Model file corrupted | Detect via SHA256 checksum on load, offer re-download |
| Inference produces invalid JSON | "Couldn't parse suggestions — try again" with retry button |
| Inference is very slow (>15s) | Show cancel button, allow user to abort |
| No tabs to organize (<3 unfiled tabs) | Disable the menu item / show "Not enough tabs to organize" |
| >60 unfiled tabs | Show message suggesting organizing one space at a time |
| System memory pressure during inference | Cancel inference, unload model, show error |

---

## Model Management

- **Storage:** `~/Library/Application Support/Nook/Models/qwen2.5-0.5b-instruct-4bit/`
- **Download:** HTTPS from HuggingFace Hub (mlx-community repo). `mlx-swift-transformers` has built-in Hub download support with resumption.
- **Verification:** SHA256 checksum verified after download and on each model load.
- **Versioning:** Store a `model-version.json` alongside the model files. When we ship an update that needs a newer model, bump the version and re-download.
- **Cleanup:** Settings option to delete downloaded models to reclaim disk space.
- **Idle unload:** 5-minute timer after last inference. Configurable in settings. Also unloads on system memory pressure.

---

## Settings

Add to `NookSettingsService`:
- `tabOrganizerModelDownloaded: Bool` — tracks whether model is available
- `tabOrganizerIdleTimeout: TimeInterval` — how long to keep model loaded (default: 300s)
- `tabOrganizerEnabled: Bool` — feature flag, default true

---

## Testing

- **Unit tests:** `TabOrganizationPrompt` (prompt construction with various tab counts, edge cases), `TabOrganizationPlan` (JSON parsing including malformed input, invalid indices, partial results), `TabOrganizationApplier` (mock TabManager, verify correct API calls, verify pinned tab handling, verify undo snapshot)
- **Integration test:** Full flow with mocked engine response (known JSON → verify correct tab state changes)
- **Manual testing:** Run with real tabs, verify groupings make sense, renames are useful, duplicates are correct, undo works

---

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| 0.5B model quality too low | Prompt engineering with explicit JSON schema and integer indices; fall back to heuristic grouping (by domain) if model output is consistently bad. Can upgrade to 1.5B model later without architecture changes. |
| 350MB download deters users | One-time download with clear explanation. Could offer a smaller model option (~100MB SmolLM) in future. |
| MLX Swift API instability | Pin to a specific release tag. The API has stabilized as of 2025. |
| Memory pressure from loaded model | Aggressive idle unload (5 min default). Respond to system memory pressure notifications to unload early. |
| Slow inference on older M1 | 0.5B Q4 runs at ~50-100 tok/s even on M1. For 50 tabs the prompt+response is ~3K tokens. Should be <5s. |
| Token budget exceeded | Hard cap at 60 tabs per invocation. Prompt uses compact integer indices. |
| Model corrupts tab references | Integer indices instead of UUIDs, validated after parsing. Invalid indices are silently dropped. |
| User regrets organizing | Single-level undo via pre-apply snapshot. Status bar shows undo option for 30s. |
| Corporate firewall blocks HuggingFace | Error message with suggestion to check network. Could add alternate download mirror in future. |
