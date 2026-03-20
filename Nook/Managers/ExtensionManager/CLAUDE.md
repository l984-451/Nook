# Extension System (WKWebExtension)

Deep documentation for Nook's web extension subsystem. For project-level context, see the [root CLAUDE.md](../../../CLAUDE.md).

## Availability

All extension code requires `@available(macOS 15.4, *)` guards. Content script injection specifically requires macOS 15.5+.

## Key Files

| File | Purpose |
|------|---------|
| `ExtensionManager.swift` | Core facade (~380 lines): properties, init/deinit, setup, profile stores, context identity |
| `ExtensionManager+Installation.swift` | Install flow, persistence, Safari discovery, Chrome Web Store, enable/disable/uninstall, MV3 support |
| `ExtensionManager+Delegate.swift` | All `WKWebExtensionControllerDelegate` methods: popup, permissions, tabs/windows, options page, native messaging |
| `ExtensionManager+ExternallyConnectable.swift` | Bridge JS generation for `externally_connectable`, manifest patching for WebKit |
| `ExtensionManager+Diagnostics.swift` | Background health probes, state diagnosis, popup diagnostics, testing helpers |
| `ExtensionManager+TabNotifications.swift` | Tab adapter management, tab lifecycle notifications, action anchor tracking |
| `NativeMessagingHandler.swift` | Standalone class: launches native host processes, stdin/stdout messaging protocol |
| `PopupUIDelegate.swift` | Standalone class: WKUIDelegate/WKNavigationDelegate for extension popup webviews |
| `ExtensionBridge.swift` | `WKWebExtensionTab` / `WKWebExtensionWindow` protocol adapters |
| `Nook/Models/Extension/ExtensionModels.swift` | `ExtensionEntity` (SwiftData) + `InstalledExtension` runtime model |
| `Nook/Models/BrowserConfig/BrowserConfig.swift` | Shared `WKWebViewConfiguration` factory — extension controller lives here |
| `Nook/Components/Extensions/ExtensionActionView.swift` | Toolbar buttons, popup anchor positioning |
| `Nook/Components/Extensions/ExtensionPermissionView.swift` | Permission grant/deny dialogs |
| `Nook/Components/Extensions/PopupConsoleWindow.swift` | Debug console for extension popups |
| `Nook/Utils/ExtensionUtils.swift` | Manifest validation, version checks |

## Critical: WebView Config Derivation

Tab webview configs **MUST** derive from the same `WKWebViewConfiguration` that the `WKWebExtensionController` was configured with (via `.copy()`). Creating a fresh `WKWebViewConfiguration()` and just setting `webExtensionController` on it is **NOT** enough — WebKit needs the config to share the same process pool / internal state.

The chain:
```
BrowserConfig.shared.webViewConfiguration  (base)
  → ExtensionManager sets .webExtensionController on it
  → webViewConfiguration(for: profile) calls .copy() + sets profile-specific data store
  → tab gets that derived config
```

See `BrowserConfig.swift:webViewConfiguration(for:)`.

## Installation Flow

Supported formats: `.zip`, `.appex` (Safari extension bundle), `.app` (scans `Contents/PlugIns/` for `.appex`), bare directories.

1. Extract/resolve source to get `manifest.json`
2. `ExtensionUtils.validateManifest()` — checks required fields
3. MV3 validation — verifies `background.service_worker` exists
4. `patchManifestForWebKit()` — patches world isolation, injects externally_connectable bridge
5. Create temporary `WKWebExtension` to get `uniqueIdentifier`
6. Move to `~/Library/Application Support/Nook/Extensions/{extensionId}/`
7. Grant ALL manifest permissions + host_permissions at install time (Chrome-like model)
8. Load background service worker immediately
9. Extract icon (128/64/48/32/16px from manifest icons), resolve `__MSG_key__` locale strings

## Externally Connectable Bridge

**Problem**: Pages like `account.proton.me` call `browser.runtime.sendMessage(SAFARI_EXT_ID, msg)` but Safari extension IDs don't match WKWebExtension IDs.

**Solution** (`setupExternallyConnectableBridge`): Two-layer bridge injected as content scripts:
- **PAGE world script**: Wraps `browser.runtime.sendMessage()` and `.connect()`, relays via `window.postMessage()` to the isolated world
- **ISOLATED world script** (`nook_bridge.js`): Receives postMessages, calls the real `browser.runtime.sendMessage()`, forwards responses back

`patchManifestForWebKit()` auto-injects the bridge content script entry into `manifest.json` when `externally_connectable` is present.

## Extension Bridge (ExtensionBridge.swift)

- **`ExtensionWindowAdapter`** implements `WKWebExtensionWindow`: exposes active tab, tab list, window state (minimized/maximized/fullscreen), focus/close operations, privacy status.
- **`ExtensionTabAdapter`** implements `WKWebExtensionTab`: exposes url, title, selection state, loading, pinned, muted, audio state. Returns `tab.assignedWebView` (does NOT trigger lazy init). Stable adapters cached in `tabAdapters` dictionary by `Tab.id`.

## Tab <> Extension Notification

Tab notifies the extension system after webview creation:
```
Tab.setupWebView()
  -> ExtensionManager.shared.notifyTabOpened(tab)  // controller.didOpenTab(adapter)
  -> If active: notifyTabActivated()                // controller.didActivateTab(adapter)
  -> tab.didNotifyOpenToExtensions = true
```

## Permission Model

- **Install-time**: ALL manifest `permissions` + `host_permissions` auto-granted (matching Chrome behavior)
- **On load (existing extensions)**: Grants both requested + optional permissions/match patterns, enables Web Inspector
- **Runtime** (`chrome.permissions.request`): Triggers `ExtensionPermissionView` dialog via delegate

## Storage Isolation

- Extensions installed globally (`~/Library/Application Support/Nook/Extensions/{id}/`)
- Runtime storage (`chrome.storage.*`, cookies, indexedDB) isolated per profile via separate `WKWebsiteDataStore`
- On profile switch: `controller.configuration.defaultWebsiteDataStore` updated to profile-specific store

## Native Messaging

Looks up host manifests in order:
1. `~/Library/Application Support/Nook/NativeMessagingHosts/`
2. Chrome, Chromium, Edge, Brave, Mozilla standard paths

Protocol: 4-byte native-endian length prefix + JSON. Supports single-shot (5s timeout) and long-lived `MessagePort` connections.

## Delegate Methods (WKWebExtensionControllerDelegate)

Key delegate implementations in ExtensionManager:
- **Action popup**: Grants permissions, wakes MV3 service worker, positions popover via registered anchor views
- **Open tab/window**: Creates tabs for extension pages, handles OAuth popup flows
- **Options page**: Resolves URL from manifest (`options_ui.page` / `options_page`), opens in separate NSWindow with extension's webViewConfiguration. Includes path traversal protection.
- **Permission prompts**: `promptForPermissions()` and `promptForPermissionToAccess()` for runtime permission requests

## Diagnostics

- `probeBackgroundHealth()` — Runs at +3s and +8s after background load; uses KVC to access `_backgroundWebView` and evaluates capability probe (available APIs, permissions, errors)
- `diagnoseExtensionState()` — Full diagnostic on content scripts + messaging per extension
- Memory debug logging uses `[MEMDEBUG]` prefix
