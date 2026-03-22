# Extension Library Panel — Design Spec

## Overview

A unified site panel popover triggered by a button in the URL bar, combining site utilities, an extension grid, and per-site settings in a single floating panel. Replaces the current inline extension icons with a collapsed library button (plus optional pinned extensions).

Modeled after Arc browser's site panel, adapted for Nook's liquid glass aesthetic and macOS Tahoe design language.

## Goals

- Consolidate extension access into a single, clean entry point
- Surface per-site controls (content blocker, zoom) alongside extensions
- Support pinning frequently-used extensions to the URL bar for quick access
- Provide deeper site settings (cookies, permissions, site data) behind a "more" menu
- Use native macOS patterns (NSPanel, NSVisualEffectView) for proper vibrancy and window behavior

## Non-Goals

- Extension management (install/remove/update) — stays in Settings
- Extension settings/options pages — accessed from extension's own UI
- Per-site permission management UI beyond simple toggles — stays in Settings
- Sidebar-based extension UI

---

## Data Model & State

### Pin State

`NookSettingsService` gets a new property following its existing UserDefaults + JSON encoding pattern:

```swift
var pinnedExtensionIDs: [String] = [] {
    didSet {
        if let data = try? JSONEncoder().encode(pinnedExtensionIDs) {
            UserDefaults.standard.set(data, forKey: "pinnedExtensionIDs")
        }
    }
}
```

Initialized in `init()` by decoding from UserDefaults, same as `adBlockerWhitelist`.

- **Default on upgrade**: On first launch after this feature ships, if the key is absent, all currently installed extensions start pinned (preserves existing behavior). This migration runs once in `init()`.
- **New installs**: Start unpinned. User opts in via right-click → "Pin to URL Bar".

### Panel Visibility

`BrowserWindowState` gets:

```swift
var isExtensionLibraryVisible: Bool = false
```

- Per-window, transient (not persisted across launches).
- Toggled by the library button click.

### No New Models

Consumes existing `InstalledExtension` from `ExtensionManager.installedExtensions`. No new data types required. Note: `InstalledExtension` does not conform to `Identifiable`, so SwiftUI `ForEach` must use explicit `id: \.id`.

---

## Component Architecture

### New Files

| File | Purpose |
|------|---------|
| `Nook/Components/Extensions/ExtensionLibraryPanel.swift` | `NSPanel` subclass + controller. Handles window creation, positioning relative to anchor button, click-outside dismissal via event monitor, `NSVisualEffectView` background. Hosts SwiftUI content via `NSHostingView`. |
| `Nook/Components/Extensions/ExtensionLibraryView.swift` | SwiftUI content for the panel. Three sections: utility buttons row, extension grid, site settings. |
| `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift` | Second `NSPanel` for the "more" submenu (cookies, site data, permissions, clear data). Same vibrancy treatment. |
| `Nook/Components/Extensions/ExtensionLibraryButton.swift` | Grid icon button placed inside the URL bar. Toggles `isExtensionLibraryVisible`. Reports its frame for panel anchoring via `GeometryReader`. |

### Modified Files

| File | Change |
|------|--------|
| `URLBarView.swift` | Replace inline `ExtensionActionView` with: pinned `ExtensionActionButton`s (filtered by `pinnedExtensionIDs`) + `ExtensionLibraryButton`. Keep existing copy link and PiP buttons. |
| `TopBarView.swift` | Remove `extensionsView` computed property entirely. Extensions no longer live in the TopBar. |
| `ExtensionActionView.swift` | Kept as-is. Still renders individual extension action buttons, now used only for pinned extensions in the URL bar. |
| `NookSettingsService` | Add `pinnedExtensionIDs: [String]` property (UserDefaults + JSON encoding). |
| `BrowserWindowState` | Add `isExtensionLibraryVisible: Bool`. |

### No Changes to ExtensionManager

All extension interactions use existing APIs:
- `ExtensionManager.shared.installedExtensions` — list of extensions
- `ExtensionManager.shared.getExtensionContext(for: extensionId)` → returns `WKWebExtensionContext`
- `WKWebExtensionContext.performAction(for: adapter)` — triggers extension action/popup
- `ExtensionManager.shared.stableAdapter(for: tab)` — gets `ExtensionTabAdapter` for current tab
- `ExtensionManager.shared.showExtensionInstallDialog()` — file picker for .zip/.xpi

---

## UI Layout

### URL Bar Layout (Both Modes)

The library button and pinned extensions live inside whichever URL bar is active. Nook has two layout modes:

**Sidebar URL bar** (`URLBarView.swift`, when `topBarAddressView = false`):
```
[url text] [spacer] [copy link] [pip?] [pinned ext icons] [library button ⊞]
```

**TopBar URL bar** (`TopBarView.swift`, when `topBarAddressView = true`):
```
[back/fwd/reload] [url bar w/ pinned exts + library btn] [spacer] [chat?]
```

In both modes, the extension icons and library button are inside the URL bar's rounded rect. `TopBarView.extensionsView` is removed — no extensions outside the URL bar.

- Pinned extension icons: Same `ExtensionActionButton` as today, filtered to only show extensions in `pinnedExtensionIDs`.
- Library button: Always visible. SF Symbol `square.grid.2x2` icon. Toggles the panel.

### Main Panel Content

```
┌──────────────────────────────────┐
│  [Copy Link] [Screenshot] [Mute] [Boosts]  │  ← Utility buttons
├──────────────────────────────────┤
│  EXTENSIONS                                  │
│  [icon] [icon] [icon] [icon]                │  ← 4-column grid
│  [icon] [icon] [+Add]                       │  ← Pin dot on pinned items
├──────────────────────────────────┤
│  🛡 Content Blocker    Enabled · 24  [toggle]│  ← Per-site settings
│  🔍 Page Zoom                    [- 100% +] │
├──────────────────────────────────┤
│  🔒 Secure · github.com              [ ⋯ ]  │  ← Footer
└──────────────────────────────────┘
```

### More Menu (⋯)

```
┌─────────────────────┐
│  Cookies           12│
│  Site Data      2.4MB│
│  Notifications Allowed│
│  Location      Blocked│
│  Microphone       Ask│
│  Camera           Ask│
│  ─────────────────── │
│  Clear All Site Data │
└─────────────────────┘
```

---

## Implementation Approach

### NSPanel + NSHostingView + NSVisualEffectView

**Why NSPanel:**
- `NSPopover` dismisses when an extension opens its own popup (both compete for popover status). NSPanel stays open.
- SwiftUI `.popover()` has sizing bugs on macOS and can't do vibrancy backgrounds.
- Pure SwiftUI overlay can't break out of window bounds or float above web content.

**Panel setup:**
- Style: `.borderless` + `.nonactivatingPanel` — doesn't steal focus from the main window.
- `.isFloatingPanel = true` — stays above browser content.
- `.hidesOnDeactivate = true` — auto-hides when app loses focus.
- `NSVisualEffectView` with `.material = .hudWindow` (or `.popover`) for frosted glass vibrancy.
- On macOS 26, `NSVisualEffectView` automatically gets Liquid Glass treatment.

**SwiftUI content:**
- Hosted via `NSHostingView` inside the panel.
- Receives environment objects (`BrowserManager`, `BrowserWindowState`, `NookSettingsService`) from the hosting view.
- Content updates reactively via SwiftUI bindings.

**Existing precedent in Nook:** `NookDragPreviewWindow`, `ExternalMiniWindowManager`, and the extension popup system all use similar floating `NSWindow`/`NSPanel` patterns.

---

## Interaction Flow

### Opening/Closing

1. User clicks library button (grid icon) in URL bar.
2. `BrowserWindowState.isExtensionLibraryVisible` toggles.
3. `ExtensionLibraryPanel` positions below URL bar, right-aligned to button.
4. **Dismiss triggers:**
   - Click outside panel within app → dismiss (via `NSEvent.addLocalMonitorForEvents`, checking click is outside panel frame)
   - Click outside app / app loses focus → dismiss (via `.hidesOnDeactivate = true`)
   - Press Escape → dismiss
   - Switch tabs → dismiss
   - Switch/close window → dismiss

### Extension Interactions (Inside Panel)

- **Click extension icon** → gets `WKWebExtensionContext` via `ExtensionManager.shared.getExtensionContext(for: ext.id)`, then calls `context.performAction(for: adapter)` where `adapter` is obtained via `ExtensionManager.shared.stableAdapter(for: currentTab)`. Opens the extension's own popup. Library panel stays open behind it.
- **Right-click extension icon** → context menu: "Pin to URL Bar" / "Unpin from URL Bar".
- **Click "Add New" (+)** → calls `ExtensionManager.showExtensionInstallDialog()`.

### Pinned Extensions (In URL Bar)

- Unchanged from current behavior. Click triggers extension action directly via `ExtensionActionButton`.

### Site Settings

- **Content blocker toggle** → reads current state via `browserManager.contentBlockerManager.isDomainAllowed(host)`, then calls `browserManager.contentBlockerManager.allowDomain(host, allowed: !currentState)` to toggle. The blocked count label is aspirational — initial implementation shows "Enabled" / "Disabled for this site" without a count (WKWebView does not expose per-page block counts natively).
- **Zoom +/−** → calls `browserManager.zoomManager.zoomIn(for: webView, domain: domain, tabId: tab.id)` / `.zoomOut(...)`. Requires current tab's webView (via `WebViewCoordinator.getWebView(for: tab.id, in: windowState.id)` from environment — note: `BrowserManager.getWebView` is deprecated), domain (from `tab.url.host`), and tab ID. Percentage label reads from `zoomManager.currentZoomPercentage` (computed `Int` property) and updates live.
- **More button (⋯)** → opens second `NSPanel` with deeper settings.

### Keyboard Shortcut

- Default: `Cmd+Shift+E` to toggle panel (registered via `KeyboardShortcutManager`, user-configurable).

---

## Panel Positioning & Lifecycle

### Positioning

- Library button reports its frame via `GeometryReader` preference key.
- Panel appears below URL bar, right-aligned to library button.
- If panel would extend off-screen, shifts left to stay within window bounds.
- Width: fixed ~340pt.
- Height: dynamic, based on number of extensions and visible settings.

### Lifecycle

- Created lazily on first open, then reused (show/hide) — not recreated each time.
- Owned per-window: each `BrowserWindowState` gets its own panel instance.
- Released on window close.

### More Menu

- Positioned adjacent to main panel (right side, or left if insufficient space).
- Dismissed independently — closing it returns focus to main panel.
- Closing main panel also dismisses more menu.

### Animations

- **Open:** Subtle scale + fade (0.95 → 1.0 scale, 0 → 1 opacity, ~0.15s ease-out).
- **Close:** Quick fade out (~0.1s).

---

## Availability Guards

The project minimum is macOS 15.5. All extension-related UI requires `@available(macOS 15.5, *)` guards. The entire panel is gated behind this since extensions are its primary content.

---

## More Menu Data Sources

| Field | Source | Notes |
|-------|--------|-------|
| Cookies (count) | `WKHTTPCookieStore.getAllCookies()` filtered by current domain | Async; cache the count on panel open |
| Site Data (size) | `WKWebsiteDataStore.dataRecords(ofTypes:)` | Returns records but not byte sizes; show "stored" / "none" initially, defer size display to future iteration |
| Notifications | App-level `UNUserNotificationCenter.authorizationStatus` | macOS permissions are app-level, not per-site; show app-level state |
| Location | `CLLocationManager.authorizationStatus` | Same — app-level |
| Microphone | `AVCaptureDevice.authorizationStatus(for: .audio)` | Same — app-level |
| Camera | `AVCaptureDevice.authorizationStatus(for: .video)` | Same — app-level |
| Clear All Site Data | `CacheManager.clearSiteData(for: domain)` + `CookieManager.deleteAllCookies(for: domain)` | Destructive; no confirmation dialog needed (action is clearly labeled) |

Note: Per-site permission management (as opposed to app-level) is a non-goal for V1. The More Menu shows current app-level states as informational. Future iterations could add per-site WKWebView permission tracking.

---

## Edge Cases

- **0 extensions installed**: Panel still shows utility buttons and site settings sections. Extensions section shows only the "+ Add New" button.
- **20+ extensions**: Grid scrolls vertically within a max height. Panel gets a `ScrollView` with a max height of ~400pt.
- **No active tab**: Utility buttons (copy link, mute) and site settings (blocker, zoom) are disabled/hidden. Extensions section still functional.
- **Window resize while panel open**: Panel repositions on next frame via window notification observer, or dismisses if anchor is no longer visible.

---

## Accessibility

- Library button: VoiceOver label "Extension Library" with hint "Opens site utilities and extensions panel".
- Extension grid items: VoiceOver labels use extension name, trait `.isButton`.
- Keyboard navigation: Tab key moves between sections, arrow keys navigate within the extension grid.
- Focus management: First responder set to the panel on open, returned to URL bar on close.
- All interactive elements have accessibility identifiers for UI testing.

---

## Visual Reference

Mockups are in `.superpowers/brainstorm/5278-1774098585/panel-liquidglass.html` — liquid glass panel with SVG icons showing the main view and more menu side by side.
