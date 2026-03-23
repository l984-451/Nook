# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Nook is a fast, minimal macOS browser with sidebar-first design. Built with Swift 5, SwiftUI, and WKWebView. Licensed GPL-3.0.

- **Minimum macOS**: 15.5 (Tahoe)
- **Xcode**: 16.4+
- **Bundle ID**: `io.browsewithnook.nook`
- **Current Version**: 1.0.7 (build 107)
- **NOT sandboxed** — runs with hardened runtime but no App Sandbox

## Build & Run

```bash
# Open in Xcode (single scheme: "Nook")
open Nook.xcodeproj

# Build from command line
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build

# Release build (universal)
xcodebuild -scheme Nook -configuration Release -arch arm64 -arch x86_64 -derivedDataPath build

# Run tests (UI tests only)
xcodebuild test -scheme Nook
```

**Signing**: You must set your personal Development Team in Xcode Signing settings to build locally. CI uses team `96M8ZZRJK6`; local dev uses `9DLM793N9T`.

**No SPM resolve needed**: All dependencies are embedded locally or use file-system-synchronized groups. Xcode resolves packages automatically on open.

**Bridging Header**: `Nook/Supporting Files/Nook-Bridging-Header.h` imports `MuteableWKWebView.h` and `HTSymbolHook.h` for ObjC interop.

## Git Workflow

- **All work branches from `dev`**. PRs must target `dev`, not `main` (enforced by CI).
- **`main`** is release-only. Merges from `dev` are tagged `v*`, triggering the notarized DMG build.
- AI assistance must be disclosed per CONTRIBUTING.md.
- Upstream remote: `https://github.com/nook-browser/Nook.git` (added as `upstream`).

## Architecture

### Manager-Based Pattern

The app uses ~30 specialized **Managers** for each feature domain, coordinated through environment injection. All managers are `@MainActor` confined.

**Core managers:**

| Manager | Location | Responsibility |
|---------|----------|----------------|
| **BrowserManager** | `Nook/Managers/BrowserManager/` | Central coordinator (~2874 lines). Aggregates all other managers. Being refactored toward independent injection. |
| **TabManager** | `Nook/Managers/TabManager/` | Tab lifecycle (~2810 lines), persistence via `PersistenceActor`, spaces, folders, pins |
| **ProfileManager** | `Nook/Managers/ProfileManager/` | Profile lifecycle, ephemeral/incognito profiles with non-persistent `WKWebsiteDataStore` |
| **ExtensionManager** | `Nook/Managers/ExtensionManager/` | WKWebExtension integration (~3990 lines). Singleton. See [Extension CLAUDE.md](Nook/Managers/ExtensionManager/CLAUDE.md) |
| **WindowRegistry** | `Nook/Managers/WindowRegistry/` | Multi-window state tracking. Single source of truth for all open windows |
| **WebViewCoordinator** | `Nook/Managers/WebViewCoordinator/` | WebView pool for multi-window tab display |

**Feature managers:**

| Manager | Purpose |
|---------|---------|
| **AIManager/** | AI chat: providers (Gemini, OpenRouter, Ollama, OpenAI-compatible), MCP client/server, browser tool execution |
| **BoostsManager/** | Per-domain CSS/JS injection (brightness, contrast, sepia, tint, custom CSS/JS, font override, zoom) |
| **DialogManager/** | Modal dialogs: profile creation, space editing, basic auth, settings, import, confirmations |
| **DownloadManager/** | File downloads via `WKDownloadDelegate` |
| **DragManager/** | `TabDragManager` (drag container types) and `DragLockManager` (conflict prevention). Legacy system — see DragDrop below |
| **FindManager/** | In-page find/search |
| **HistoryManager/** | Browsing history, SwiftData persistence |
| **ImportManager/** | Browser import from Safari, Arc, and Dia |
| **KeyboardShortcutManager/** | Global + website-specific keyboard shortcuts |
| **PeekManager/** | Quick-preview overlay for links (PeekSession + PeekWebView) |
| **PrivacyManager/** | TrackingProtectionManager + OAuthDetector |
| **SearchManager/** | Search engine integration |
| **SplitViewManager/** | Split-screen tab viewing |
| **ZoomManager/** | Page zoom controls |
| **PiPManager** | Picture-in-Picture mode |
| **CacheManager** | Web cache management |
| **CookieManager** | Cookie storage/clearing |
| **AuthenticationManager** | HTTP Basic auth dialogs |
| **MediaControlsManager** | Audio/media integration |
| **GradientColorManager** | Space gradient colors |
| **HoverSidebarManager** | Sidebar hover interactions |
| **ExternalMiniWindowManager** | Mini browser windows |

### State Management

- **`@Observable`** (Swift Observation): `Profile`, `Space`, `Tab`, `BrowserWindowState`, `WebViewCoordinator`, `WindowRegistry`, `AIService`
- **`@Published` / `ObservableObject`** (Combine): `BrowserManager`, `Tab` (dual — uses both patterns), `ExtensionManager`, `NookDragSessionManager`, `PeekManager`, `BoostsManager`
- **SwiftData**: `SpaceEntity`, `ProfileEntity`, `TabEntity`, `FolderEntity`, `HistoryEntity`, `ExtensionEntity`, `TabsStateEntity`
- **UserDefaults**: `NookSettingsService` (all app settings)
- All state is `@MainActor` confined for thread safety.

### App Entry & Window Hierarchy

```
NookApp.swift          — @main entry, WindowGroup scene, environment injection
  └─ ContentView.swift — Per-window container, registers with WindowRegistry
       └─ WindowView   — Main browser: Sidebar + WebsiteView + TopBar + StatusBar
```

**Environment injection**: `NookApp` creates `BrowserManager`, `WindowRegistry`, `WebViewCoordinator`, `NookSettingsService`, `KeyboardShortcutManager`, `AIConfigService`, `MCPManager`, `AIService` and injects them as `@EnvironmentObject` / `@Environment`. Each window gets its own `BrowserWindowState`.

### Top-Level Modules

| Directory | Purpose |
|-----------|---------|
| `App/` | Entry point (`NookApp.swift`), `AppDelegate`, `ContentView`, window management, `NookCommands` |
| `Nook/Managers/` | ~30 feature managers (business logic) |
| `Nook/Models/` | Data models and SwiftData entities |
| `Nook/Components/` | SwiftUI views (~22 subdirectories) |
| `Nook/Protocols/` | Protocol definitions (e.g., `TabListDataSource`) |
| `Nook/Adapters/` | External API adapters (`TabListAdapter`) |
| `Nook/Extensions/` | Swift language extensions |
| `Nook/Utils/` | Utilities, WebKit extensions, Metal shaders, debug tools |
| `Nook/ThirdParty/` | Embedded dependencies |
| `Settings/` | `NookSettingsService` — `@Observable` settings backed by UserDefaults |
| `CommandPalette/` | Command palette UI |
| `UI/` | Shared UI components |
| `Navigation/` | Sidebar structure (header, bottom bar, spaces list, context menus) |
| `Onboarding/` | 9-stage onboarding flow (Hello → TabLayout → URLBar → Import → AdBlocker → Background → AiChat → Final) |

## Drag-and-Drop System (New)

The codebase has a **new** unified drag-drop system in `Nook/Components/DragDrop/` that replaces the older `TabDragManager`:

| File | Purpose |
|------|---------|
| `NookDragSessionManager.swift` | Singleton coordinator: tracks active drag state, cursor position, zone geometry, insertion indices, preview window |
| `NookDragItem.swift` | Draggable item model + `DropZoneID` enum (`.essentials`, `.spacePinned(UUID)`, `.spaceRegular(UUID)`, `.folder(UUID)`) |
| `NookDragSourceView.swift` | `NSView`-based drag source, weak-registered with manager |
| `NookDropZoneHostView.swift` | Drop zone target management |
| `NookDragPreviewWindow.swift` | Floating preview window following cursor during drag |

Custom UTType: `com.nook.tab-drag-item` (registered in Info.plist). Items encode to pasteboard as JSON via `NookDragItem.writeToPasteboard()`.

## AI System

Located in `Nook/Managers/AIManager/`:

- **AIService** — Central orchestrator: manages providers, conversations, streaming, tool execution (max 20 iterations)
- **AIConfigService** — Provider configuration and API key management
- **AIProvider** — Protocol + factory for provider implementations
- **Providers/**: `GeminiProvider`, `OpenRouterProvider`, `OllamaProvider`, `OpenAICompatibleProvider`
- **MCP/**: `MCPManager` (server lifecycle), `MCPClient` (JSON-RPC), `MCPTransport` (stdio/SSE)
- **Tools/**: `BrowserTools` (tool definitions), `BrowserToolExecutor` (executes browser actions from AI)

Settings stored in `NookSettingsService`: `aiProvider`, API keys per provider, model selection, web search config.

## Boosts System

Per-domain website customization via CSS/JS injection (`Nook/Managers/BoostsManager/`):

- `BoostConfig`: brightness, contrast, sepia, tint color/strength, custom CSS, custom JS, font family, page zoom, text transform
- Configs stored per normalized domain in UserDefaults
- `WKUserScript` injection with caching (`scriptCache`)
- `BoostsWindowManager`: UI for editing boosts

## Entitlements & Security

**NOT sandboxed** — the app runs with hardened runtime but no App Sandbox. Key entitlements (`Nook/Nook.entitlements`):

| Entitlement | Purpose |
|-------------|---------|
| `aps-environment: development` | Push notifications (dev) |
| `autofill-credential-provider` | Password autofill integration |
| `web-browser.public-key-credential` | WebAuthn/passkey support (restricted — requires Apple approval) |
| `automation.apple-events` | AppleScript support |
| `mach-lookup: com.apple.PIPAgent` | Picture-in-Picture |

**Info.plist**: Registers as URL handler for `http`/`https` (LSHandlerRank: Owner). Allows arbitrary loads in web content and local networking. Sparkle auto-updates enabled (daily check, feed at gh-pages/appcast.xml).

## Key Patterns

- **Lazy WebView**: `Tab.webView` is lazily initialized on first access. Tabs exist without loaded webviews to save memory. **Important**: When changing the active tab (e.g., after data load), call `loadWebViewIfNeeded()` before refreshing the compositor — the compositor skips unloaded tabs.
- **Multi-window webviews**: Same tab in multiple windows gets separate webview instances via `WebViewCoordinator`. Primary window owns the "real" webview; others get clones.
- **Profile data isolation**: Each `Profile` owns a unique `WKWebsiteDataStore`. Ephemeral profiles use `.nonPersistent()` stores destroyed on window close.
- **Atomic persistence**: `TabManager` uses a Swift `actor` (`PersistenceActor`) for coalesced, atomic snapshot writes with backup recovery.
- **Favicon cache**: Global LRU cache (200 max) with persistent disk cache; concurrent DispatchQueue with NSLock.
- **File-system-synced groups**: Xcode uses filesystem-synchronized groups (not manual file references) — new files in the directory are automatically included in the build.
- **WebContent sandbox**: WKWebView's WebContent processes are sandboxed by Apple. They cannot access the system pasteboard, launchservicesd, or RunningBoard. Clipboard operations must route through the app process. The `WebContent[PID]` log messages about sandbox restrictions are normal and not actionable.
- **WKWebView.configuration returns a copy**: `webView.configuration.preferences.setValue(...)` modifies a discarded copy. Use base config before webview creation, or access `userContentController` (which IS shared).

## Dependencies

**SPM packages (resolved automatically):**
Sparkle (auto-update), FaviconFinder, Garnish (UI utils), swift-numerics, swift-atomics, Highlightr (syntax highlighting), Fuzi (HTML/XML parsing), reeeed (web tech detection), LRUCache, Motion (animation), UniversalGlass, ColorfulX

**Embedded in ThirdParty/:**
BigUIPaging (paged views), HTSymbolHook (ObjC symbol hooking), MuteableWKWebView (audio muting, ObjC)

## CI/CD

Two GitHub Actions workflows in `.github/workflows/`:

1. **`enforce-pr-base.yml`** — Fails PRs targeting `main` instead of `dev`
2. **`macos-notarize.yml`** — Triggered on release publication: builds universal binary, re-signs Sparkle framework, notarizes with Apple, creates DMG, uploads to GitHub release, updates Sparkle appcast on gh-pages

## Code Style

- No SwiftLint or SwiftFormat enforced — follow existing patterns
- `@MainActor` on all stateful classes
- `// MARK: -` sections to organize code
- PascalCase for types, camelCase for properties/methods
- System imports first, then external packages, then local imports
- OSLog with privacy annotations for logging (`Logger(subsystem:category:)`)
- Standard Xcode file headers with author/date

## Extension System

The web extension system (WKWebExtension, macOS 15.4+) is the most complex subsystem. Full documentation is in [Nook/Managers/ExtensionManager/CLAUDE.md](Nook/Managers/ExtensionManager/CLAUDE.md).

**Quick reference**: All extension code requires `@available(macOS 15.4, *)` guards. Content scripts require macOS 15.5+. Tab webview configs **MUST** derive from the same `WKWebViewConfiguration` that the `WKWebExtensionController` was configured with (via `.copy()`) — see `BrowserConfig.swift`.
