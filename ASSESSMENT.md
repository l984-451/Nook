# Nook Browser — Assessment Report

**Date**: 2026-03-20
**Branch**: `main` (post upstream/dev merge, commit `f2c7f50`)
**Build SDK**: macOS 26.2 (Xcode 17.x)
**Deployment Target**: macOS 15.5

---

## 1. Build Status

| Metric | Value |
|--------|-------|
| **Build result** | SUCCESS |
| **Errors** | 0 |
| **Total warnings** | 91 (raw), 52 unique (project-only) |
| **SPM packages** | 18 — all resolved successfully |
| **Build command** | `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` |

**Note**: Build requires `CODE_SIGNING_ALLOWED=NO` or a configured Apple Development team. The upstream team ID (`9DLM793N9T`) is baked into the project; local dev needs their own team or ad-hoc signing.

---

## 2. Warning Audit

### By Category

#### Concurrency / Swift 6 Preparation (16 warnings)
The largest category. These will become **errors** under Swift 6 strict concurrency.

| File | Warning | Severity |
|------|---------|----------|
| `ExtensionManager.swift:2085,2087,2089,2101` | `ExtensionEntity` Sendable conformance unavailable (PersistentModels) | Medium — Swift 6 blocker |
| `ExtensionManager.swift:106,2095` | Main actor-isolated `logger` accessed from nonisolated context | Medium |
| `ExtensionManager.swift:2355,2362` | `actionAnchors` accessed/mutated from Sendable closure | High — potential race |
| `NookDragSessionManager.swift:125` | `NSEvent` Sendable conformance unavailable | Low |
| `FocusableWKWebView.swift:128` | `imageContentTypes` accessed from nonisolated context | Low |
| `FocusableWKWebView.swift:195` | `UNUserNotificationCenter` captured in `@Sendable` closure | Low |
| `FocusableWKWebView.swift:2` | Missing `@preconcurrency` on `UserNotifications` import | Low — easy fix |
| `AnyShape.swift:12` | Non-Sendable `(CGRect) -> Path` in Sendable struct | Low |
| `SidebarMenuDownloadsHover.swift:259` | Main actor-isolated `completion` called from nonisolated context | Medium |
| `SidebarMenuDownloadsTab.swift:193` | Same as above | Medium |

#### Unused Variables (14 warnings)
| File | Variable | Notes |
|------|----------|-------|
| `SplitViewManager.swift:90,180,351,356,361,394,399` | `bm` (7 instances) | Unused `BrowserManager` references — likely from refactoring |
| `HoverSidebarManager.swift:78` | `bm` | Same pattern |
| `BrowserManager.swift:437` | `activeMute` | |
| `Tab.swift:448,452` | `allScripts`, `boostScriptSources` | Dead code in boost injection |
| `Tab.swift:1772` | `webView` | |
| `NookButtonStyle.swift:63,64` | `shadowColor`, `highlightColor` | |
| `PeekManager.swift:27` | `browserManager` | |

#### Unused Return Values (3 warnings)
| File | Call |
|------|------|
| `SpaceTitle.swift:262` | `createFolder(for:name:)` |
| `SpacesSideBarView.swift:255` | `createFolder(for:name:)` |
| `SidebarBottomBar.swift:65` | `createFolder(for:name:)` |

#### Unnecessary `await`/`try` (4 warnings)
| File | Issue |
|------|-------|
| `MCPClient.swift:192` | No async operations in `await` expression (23 duplicate emissions — same warning) |
| `NookButtonStyle.swift:88,98,107` | No throwing functions in `try` expression |

#### Deprecation (2 warnings)
| File | API |
|------|-----|
| `Tab.swift:577` (x2) | `WKProcessPool.processPool` deprecated macOS 12.0 |

#### Suspicious Return Expressions (2 warnings)
| File | Issue |
|------|-------|
| `PrivacySettingsView.swift:24` | Expression after `return` treated as argument |
| `SettingsView.swift:1603` | Same |

#### API Mismatch (1 warning)
| File | Issue |
|------|-------|
| `ExtensionManager.swift:3029` | `webExtensionController(_:connectUsingMessagePort:for:)` nearly matches protocol requirement — **may cause runtime failure** if method is never called |

#### `nonisolated(unsafe)` Deprecation (2 warnings)
| File | Issue |
|------|-------|
| `KeyboardShortcutManager.swift:563` | `nonisolated(unsafe)` has no effect, use `nonisolated` |
| `WebsiteShortcutDetector.swift:39` | Same |

#### Asset Catalog (2 warnings)
| Asset | Issue |
|-------|-------|
| `adblocker-on.imageset` | Contains `adblocker-off.png` as unassigned child |
| `adblocker-off.imageset` | Contains `adblocker-on.png` as unassigned child |

#### Miscellaneous (2 warnings)
| File | Issue |
|------|-------|
| `SidebarAIChat.swift:27` | Immutable property won't be decoded (has initial value) |
| `ExtensionManager.swift:1562,2152` | Consider using async alternative function |

---

## 3. Merge Artifact Assessment

The upstream merge (`f2c7f50`) resolved 2 conflicts:
1. `SplitDropCaptureView.swift` — Clean, properly integrated with new drag system
2. `SplitTabRow.swift` — Clean, uses `NookDragSessionManager.shared`

**No remaining merge artifacts.** All `draggedItem` references (15 total) use the new `NookDragSessionManager` system. Legacy drag code has been fully removed.

---

## 4. Feature Status Matrix

| Feature | Status | Notes |
|---------|--------|-------|
| **Tab creation/navigation** | Likely Working | Core path, no warnings in critical code |
| **Sidebar rendering** | Likely Working | Spaces, tabs, essentials grid all compile clean |
| **Tab drag-drop reorder** | Likely Working | New unified system fully integrated, no type mismatches |
| **Tab drag between spaces** | Likely Working | `NookDragSessionManager` handles cross-zone drops |
| **Space switching** | Likely Working | BigUIPaging integration unchanged |
| **Space creation/deletion** | Likely Working | Standard SwiftData CRUD |
| **Profile switching** | Likely Working | `ProfileManager` unchanged |
| **Split view** | Partial Risk | `SplitViewManager` has 7 unused `bm` variables — may indicate incomplete refactoring |
| **Extensions** | Partial Risk | 13 warnings including potential API mismatch (`connectUsingMessagePort`), Sendable violations |
| **Boosts** | Partial Risk | 2 unused variables (`allScripts`, `boostScriptSources`) in Tab.swift suggest dead injection code |
| **Keyboard shortcuts** | Likely Working | Only `nonisolated(unsafe)` deprecation warnings |
| **Downloads** | Minor Risk | Main actor isolation warnings in completion handlers |
| **AI chat** | Minor Risk | Immutable property won't decode; MCPClient has unnecessary `await` |
| **Peek preview** | Likely Working | Only unused variable warning |
| **Onboarding** | Likely Working | No warnings |
| **Incognito** | Likely Working | Profile system with ephemeral stores unchanged |
| **Auto-update (Sparkle)** | Likely Working | No warnings from integration |

---

## 5. Technical Debt

### God Objects
| File | Lines | Status |
|------|-------|--------|
| `ExtensionManager.swift` | 3,990 | Highest complexity, most warnings (13) |
| `BrowserManager.swift` | 2,874 | Central coordinator, 1 warning |
| `TabManager.swift` | 2,810 | Core logic, 1 TODO |

### Deprecated Code
- `Nook/Components/Boosts - deprecated/` — 2 files (BoostColorCanvas.swift, ColorWheelPicker.swift). Replaced by new Boosts UI but not yet removed from project.

### Outstanding TODOs
- 9 TODOs across BrowserManager (3), TabManager (1), ExtensionManager (1), BoostsWindowManager (1), SpaceTab (3)
- 1 FIXME in HTSymbolHook.m (third-party)

### Dual State Pattern
`Tab` uses both `@Observable` and `@Published`/`ObservableObject` — documented as intentional but adds complexity.

---

## 6. Dependency Health

| Status | Details |
|--------|---------|
| **SPM resolution** | All 18 packages resolve cleanly |
| **Version conflicts** | None |
| **Pinned to branch** | `Motion` (main), `Garnish` (main) — risk of breaking changes |
| **Embedded deps** | BigUIPaging, HTSymbolHook, MuteableWKWebView — no version management |
| **WKProcessPool** | Deprecated since macOS 12; used in Tab.swift:577 — functional but should be removed |

---

## 7. Runtime Smoke Test Checklist

After building, manually verify these flows:

- [ ] App launches without crash
- [ ] Sidebar renders with spaces, tabs, essentials grid
- [ ] New tab creation works
- [ ] Tab navigation (click URL bar, load page)
- [ ] Tab drag-drop reorder in sidebar
- [ ] Tab drag between spaces
- [ ] Space switching (horizontal paging)
- [ ] Space creation/deletion
- [ ] Profile switching (via Settings)
- [ ] Split view (right-click → Open in Split)
- [ ] Extension installation (if macOS 15.4+)
- [ ] Sidebar collapse/expand
- [ ] Incognito window
- [ ] Keyboard shortcuts (Cmd+T, Cmd+W, Cmd+L)
- [ ] Downloads (save a file)
- [ ] AI chat sidebar (if configured)

---

## 8. Prioritized Roadmap

### P0 — Must Fix (Build/Crash/Regression Risk)
1. **ExtensionManager API mismatch** (`connectUsingMessagePort` vs `connectUsing`) — may silently break extension messaging. Verify at runtime; if broken, rename method to match protocol.
2. **Main actor isolation in download completions** (`SidebarMenuDownloadsHover:259`, `SidebarMenuDownloadsTab:193`) — calling main-actor-isolated closure from nonisolated context could cause runtime issues.
3. **Code signing setup** — Document how local devs should configure signing (or add a `Debug-Local` scheme with ad-hoc signing).

### P1 — Should Fix (Broken Features / Quality)
4. **Dead boost injection code** in `Tab.swift:448-452` — `allScripts` and `boostScriptSources` are computed but never used, suggesting boost CSS/JS injection may be broken.
5. **ExtensionManager Sendable violations** (5 warnings) — `ExtensionEntity` passed across actor boundaries. Works now but will break under Swift 6.
6. **`return` expression warnings** in `PrivacySettingsView` and `SettingsView` — likely a missing semicolon or unintended return value that could cause subtle UI bugs.
7. **SplitViewManager cleanup** — 7 unused `bm` variables suggest an incomplete refactoring. Verify split view actually works.
8. **Remove deprecated Boosts folder** — `Boosts - deprecated/` can be deleted if new Boosts UI is confirmed working.
9. **Asset catalog fix** — adblocker image sets have swapped image assignments.

### P2 — Nice to Have (Polish / Future-Proofing)
10. **Remove `WKProcessPool` usage** — deprecated since macOS 12, does nothing.
11. **Fix `nonisolated(unsafe)` warnings** (2) — trivial rename to `nonisolated`.
12. **Clean up unused variables** (14 warnings) — mostly `bm` references.
13. **MCPClient unnecessary `await`** — remove await from non-async expression.
14. **Pin `Motion` and `Garnish`** to tagged versions instead of `main` branch.
15. **Swift 6 preparation** — Address all 16 concurrency warnings before Swift 6 migration.
16. **Break up god objects** — ExtensionManager (3,990 lines), BrowserManager (2,874), TabManager (2,810).

---

## Summary

| Metric | Value |
|--------|-------|
| **Build** | Clean (0 errors) |
| **Warnings** | 52 unique project warnings |
| **Merge status** | Clean — no artifacts, drag-drop migration complete |
| **Critical risks** | 3 (extension API mismatch, actor isolation in downloads, dead boost code) |
| **Swift files** | 243 |
| **SPM packages** | 18 (all healthy) |
| **Technical debt** | Moderate (3 god objects, deprecated folder, dual Tab state) |
| **Overall health** | Good — app compiles cleanly, architecture is solid, no merge regressions detected |
