# Extension Library Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a unified site panel popover in the URL bar that consolidates extensions, site utilities, and per-site settings behind a single library button.

**Architecture:** NSPanel with NSVisualEffectView (vibrancy) hosting SwiftUI content via NSHostingView. The library button lives inside the URL bar. Pinned extensions remain visible as individual buttons; unpinned ones collapse into the panel grid.

**Tech Stack:** Swift, SwiftUI, AppKit (NSPanel, NSVisualEffectView, NSHostingView), WKWebExtension APIs

**Spec:** `docs/superpowers/specs/2026-03-21-extension-library-panel-design.md`

---

## File Map

### New Files

| File | Responsibility |
|------|---------------|
| `Nook/Components/Extensions/ExtensionLibraryPanel.swift` | NSPanel subclass + controller (window lifecycle, positioning, dismissal, vibrancy) |
| `Nook/Components/Extensions/ExtensionLibraryView.swift` | SwiftUI panel content (utility buttons, extension grid, site settings, footer) |
| `Nook/Components/Extensions/ExtensionLibraryButton.swift` | URL bar button that toggles the panel, reports anchor frame |
| `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift` | Second NSPanel for the "more" submenu (cookies, permissions, clear data) |

### Modified Files

| File | Change |
|------|--------|
| `Settings/NookSettingsService.swift` | Add `pinnedExtensionIDs` property + UserDefaults key |
| `Nook/Models/BrowserWindowState.swift` | Add `isExtensionLibraryVisible` property |
| `Nook/Components/Sidebar/URLBarView.swift` | Replace `ExtensionActionView` with pinned icons + library button |
| `Nook/Components/Sidebar/TopBar/TopBarView.swift` | Remove `extensionsView`, add pinned icons + library button inside url bar |

---

### Task 1: Add State Properties

**Files:**
- Modify: `Settings/NookSettingsService.swift`
- Modify: `Nook/Models/BrowserWindowState.swift`

- [ ] **Step 1: Add UserDefaults key for pinnedExtensionIDs in NookSettingsService**

In `NookSettingsService.swift`, add the key constant near the other key declarations (~line 42):

```swift
private let pinnedExtensionIDsKey = "settings.pinnedExtensionIDs"
```

- [ ] **Step 2: Add pinnedExtensionIDs property with didSet**

Add the property near the other array properties (after `adBlockerWhitelist` ~line 119):

```swift
var pinnedExtensionIDs: [String] = [] {
    didSet {
        if let data = try? JSONEncoder().encode(pinnedExtensionIDs) {
            userDefaults.set(data, forKey: pinnedExtensionIDsKey)
        }
    }
}
```

- [ ] **Step 3: Initialize pinnedExtensionIDs in init()**

Find the `init()` method where `adBlockerWhitelist` is decoded from UserDefaults. Add the same pattern for `pinnedExtensionIDs` right after it:

```swift
if let pinnedData = userDefaults.data(forKey: pinnedExtensionIDsKey),
   let pinnedIDs = try? JSONDecoder().decode([String].self, from: pinnedData) {
    self.pinnedExtensionIDs = pinnedIDs
} else {
    // Migration: on first launch, pin all currently installed extensions
    // so existing users keep their current URL bar behavior.
    // This will be populated on first panel open when ExtensionManager is available.
    self.pinnedExtensionIDs = []
}
```

- [ ] **Step 4: Add isExtensionLibraryVisible to BrowserWindowState**

In `Nook/Models/BrowserWindowState.swift`, add to the UI presentation properties (near `isCommandPaletteVisible` ~line 76):

```swift
var isExtensionLibraryVisible: Bool = false
var extensionLibraryPanelController: ExtensionLibraryPanelController?
```

Note: `extensionLibraryPanelController` will need `@available(macOS 15.5, *)`. Since `BrowserWindowState` itself isn't availability-gated, store it as `Any?` and cast at use site, or wrap with `#if`:

```swift
private var _extensionLibraryPanelController: Any?
@available(macOS 15.5, *)
var extensionLibraryPanelController: ExtensionLibraryPanelController? {
    get { _extensionLibraryPanelController as? ExtensionLibraryPanelController }
    set { _extensionLibraryPanelController = newValue }
}
```

- [ ] **Step 5: Build to verify no compile errors**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Settings/NookSettingsService.swift Nook/Models/BrowserWindowState.swift
git commit -m "feat: add pinnedExtensionIDs and isExtensionLibraryVisible state"
```

---

### Task 2: Create ExtensionLibraryPanel (NSPanel + Controller)

**Files:**
- Create: `Nook/Components/Extensions/ExtensionLibraryPanel.swift`

Reference `Nook/Components/DragDrop/NookDragPreviewWindow.swift` for the existing NSWindow + NSHostingView pattern.

- [ ] **Step 1: Create the NSPanel subclass**

Create `Nook/Components/Extensions/ExtensionLibraryPanel.swift`:

```swift
//
//  ExtensionLibraryPanel.swift
//  Nook
//

import SwiftUI
import AppKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionLibraryPanelController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var hostingView: NSHostingView<AnyView>?

    private let panelWidth: CGFloat = 340

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(
        anchorFrame: CGRect,
        in window: NSWindow,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        settings: NookSettingsService
    ) {
        if isVisible {
            dismiss()
        } else {
            show(anchorFrame: anchorFrame, in: window, browserManager: browserManager, windowState: windowState, settings: settings)
        }
    }

    func show(
        anchorFrame: CGRect,
        in window: NSWindow,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        settings: NookSettingsService
    ) {
        let panel = self.panel ?? createPanel()
        self.panel = panel

        // Update SwiftUI content
        let content = ExtensionLibraryView(
            browserManager: browserManager,
            windowState: windowState,
            settings: settings,
            onDismiss: { [weak self] in self?.dismiss() }
        )

        if let hostingView = self.hostingView {
            hostingView.rootView = AnyView(content)
        } else {
            let hosting = NSHostingView(rootView: AnyView(content))
            hosting.translatesAutoresizingMaskIntoConstraints = false

            // Add vibrancy background
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            visualEffect.blendingMode = .behindWindow
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 16
            visualEffect.layer?.masksToBounds = true
            visualEffect.translatesAutoresizingMaskIntoConstraints = false

            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(visualEffect)
            container.addSubview(hosting)

            NSLayoutConstraint.activate([
                visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            panel.contentView = container
            self.hostingView = hosting
        }

        // Size the panel to fit content
        hostingView?.invalidateIntrinsicContentSize()
        let fittingSize = hostingView?.fittingSize ?? CGSize(width: panelWidth, height: 400)
        let panelSize = CGSize(width: panelWidth, height: min(fittingSize.height, 500))

        // Position below the anchor, right-aligned
        let windowAnchor = window.convertPoint(toScreen: CGPoint(
            x: anchorFrame.maxX,
            y: anchorFrame.minY
        ))
        let origin = CGPoint(
            x: windowAnchor.x - panelWidth,
            y: windowAnchor.y - panelSize.height - 4
        )

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.orderFront(nil)

        // Open animation
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installEventMonitor()
    }

    func dismiss() {
        guard let panel = panel, panel.isVisible else { return }

        removeEventMonitor()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.1
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            panel.orderOut(nil)
            self?.panel?.alphaValue = 1
        })
    }

    // MARK: - Private

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: panelWidth, height: 400)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        return panel
    }

    private func installEventMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return event }

            // Escape key dismisses
            if event.type == .keyDown && event.keyCode == 53 {
                self.dismiss()
                return event
            }

            // Check if click is inside the panel
            if let eventWindow = event.window, eventWindow == panel {
                return event // Click inside panel, allow it
            }

            // Click outside panel — dismiss
            self.dismiss()
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        let monitor = localMonitor
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
```

- [ ] **Step 2: Build to verify no compile errors**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED (ExtensionLibraryView does not exist yet — this file will compile but won't be linked until the view is created)

Note: This file references `ExtensionLibraryView` which is created in Task 3. If the build fails on the missing type, create a minimal placeholder:

```swift
// Temporary placeholder in ExtensionLibraryView.swift
@available(macOS 15.5, *)
struct ExtensionLibraryView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService
    let onDismiss: () -> Void
    var body: some View { Text("Extension Library") }
}
```

- [ ] **Step 3: Commit**

```bash
git add Nook/Components/Extensions/ExtensionLibraryPanel.swift
git commit -m "feat: add ExtensionLibraryPanelController (NSPanel with vibrancy)"
```

---

### Task 3: Create ExtensionLibraryView (SwiftUI Content)

**Files:**
- Create: `Nook/Components/Extensions/ExtensionLibraryView.swift`

Reference `Nook/Components/Extensions/ExtensionActionView.swift` for extension icon rendering and action triggering patterns.

- [ ] **Step 1: Create the SwiftUI view with all three sections**

Create `Nook/Components/Extensions/ExtensionLibraryView.swift`:

```swift
//
//  ExtensionLibraryView.swift
//  Nook
//

import SwiftUI
import AppKit
import WebKit
import os

@available(macOS 15.5, *)
struct ExtensionLibraryView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService
    let onDismiss: () -> Void

    @State private var showMoreMenu = false

    private let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionLibrary")

    private var currentTab: Tab? {
        browserManager.currentTab(for: windowState)
    }

    private var currentHost: String? {
        currentTab?.url.host
    }

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Utility Buttons
            utilityButtonsSection

            Divider().opacity(0.15)

            // MARK: - Extensions Grid
            extensionsSection

            Divider().opacity(0.15)

            // MARK: - Site Settings
            siteSettingsSection

            // MARK: - Footer
            footerSection
        }
        .frame(width: 340)
    }

    // MARK: - Utility Buttons

    private var utilityButtonsSection: some View {
        HStack(spacing: 6) {
            UtilityButton(icon: "link", label: "Copy Link") {
                guard let url = currentTab?.url.absoluteString else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
            .disabled(currentTab == nil)

            UtilityButton(icon: "camera.viewfinder", label: "Screenshot") {
                // Screenshot functionality — can be wired to existing screenshot logic
            }
            .disabled(currentTab == nil)

            UtilityButton(
                icon: currentTab?.isAudioMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: currentTab?.isAudioMuted == true ? "Unmute" : "Mute"
            ) {
                currentTab?.toggleMute()
            }
            .disabled(currentTab == nil)

            UtilityButton(icon: "slider.horizontal.3", label: "Boosts") {
                guard let tab = currentTab, let webView = tab.webView, let host = tab.url.host else { return }
                BoostsWindowManager.shared.show(for: webView, domain: host, boostsManager: browserManager.boostsManager)
            }
            .disabled(currentTab == nil)
        }
        .padding(12)
    }

    // MARK: - Extensions Grid

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXTENSIONS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
                .tracking(0.4)
                .padding(.horizontal, 4)

            let extensions = browserManager.extensionManager?.installedExtensions.filter { $0.isEnabled } ?? []

            ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(extensions, id: \.id) { ext in
                    ExtensionGridItem(
                        ext: ext,
                        isPinned: settings.pinnedExtensionIDs.contains(ext.id),
                        browserManager: browserManager,
                        windowState: windowState,
                        settings: settings
                    )
                }

                // Add New button
                Button {
                    ExtensionManager.shared.showExtensionInstallDialog()
                } label: {
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundStyle(.secondary.opacity(0.2))
                            .frame(width: 34, height: 34)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.secondary.opacity(0.3))
                            }
                        Text("Add New")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary.opacity(0.3))
                    }
                }
                .buttonStyle(.plain)
            }
            }
            .frame(maxHeight: 300)
        }
        .padding(12)
    }

    // MARK: - Site Settings

    private var siteSettingsSection: some View {
        VStack(spacing: 2) {
            // Content Blocker Toggle
            if let host = currentHost {
                let isAllowed = browserManager.contentBlockerManager.isDomainAllowed(host)

                SiteSettingRow(
                    icon: "shield.checkered",
                    iconColor: .green,
                    title: "Content Blocker",
                    subtitle: isAllowed ? "Disabled for this site" : "Enabled"
                ) {
                    Toggle("", isOn: Binding(
                        get: { !browserManager.contentBlockerManager.isDomainAllowed(host) },
                        set: { enabled in
                            browserManager.contentBlockerManager.allowDomain(host, allowed: !enabled)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            // Page Zoom
            if currentTab != nil {
                SiteSettingRow(
                    icon: "magnifyingglass",
                    iconColor: .blue,
                    title: "Page Zoom",
                    subtitle: nil
                ) {
                    HStack(spacing: 6) {
                        Button {
                            zoomOut()
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)

                        Text("\(browserManager.zoomManager.currentZoomPercentage)%")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36)

                        Button {
                            zoomIn()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: currentTab?.url.scheme == "https" ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text(currentHost ?? "No site loaded")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            Spacer()

            Button {
                showMoreMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.08))
    }

    // MARK: - Zoom Helpers

    private func zoomIn() {
        guard let tab = currentTab, let webView = tab.webView else { return }
        browserManager.zoomManager.zoomIn(for: webView, domain: tab.url.host, tabId: tab.id)
    }

    private func zoomOut() {
        guard let tab = currentTab, let webView = tab.webView else { return }
        browserManager.zoomManager.zoomOut(for: webView, domain: tab.url.host, tabId: tab.id)
    }
}

// MARK: - Utility Button

private struct UtilityButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isHovering ? .secondary.opacity(0.12) : .secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Extension Grid Item

@available(macOS 15.5, *)
private struct ExtensionGridItem: View {
    let ext: InstalledExtension
    let isPinned: Bool
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let settings: NookSettingsService

    @State private var isHovering = false
    @State private var badgeText: String?

    private var currentTab: Tab? {
        browserManager.currentTab(for: windowState)
    }

    var body: some View {
        Button {
            triggerExtensionAction()
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let iconPath = ext.iconPath,
                           let nsImage = NSImage(contentsOfFile: iconPath) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .interpolation(.high)
                                .antialiased(true)
                                .scaledToFit()
                        } else {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                    if let badge = badgeText, !badge.isEmpty {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 4, y: -4)
                    }

                    if isPinned {
                        Circle()
                            .fill(Color.blue.opacity(0.8))
                            .frame(width: 5, height: 5)
                            .offset(x: -2, y: 2)
                    }
                }

                Text(ext.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 72)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(isHovering ? .secondary.opacity(0.08) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onAppear { refreshBadge() }
        .contextMenu {
            if isPinned {
                Button("Unpin from URL Bar") {
                    settings.pinnedExtensionIDs.removeAll { $0 == ext.id }
                }
            } else {
                Button("Pin to URL Bar") {
                    settings.pinnedExtensionIDs.append(ext.id)
                }
            }
        }
        .accessibilityLabel(ext.name)
        .accessibilityHint("Extension. Double-tap to activate.")
        .accessibilityAddTraits(.isButton)
    }

    private func triggerExtensionAction() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else { return }

        if ctx.webExtension.hasBackgroundContent {
            ctx.loadBackgroundContent { error in
                if let error { Logger(subsystem: "com.nook.browser", category: "ExtensionLibrary").error("Background wake failed: \(error.localizedDescription, privacy: .public)") }
            }
        }

        let adapter: ExtensionTabAdapter? = currentTab.flatMap { ExtensionManager.shared.stableAdapter(for: $0) }
        ctx.performAction(for: adapter)
    }

    private func refreshBadge() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            badgeText = nil
            return
        }
        let adapter: ExtensionTabAdapter? = currentTab.flatMap { ExtensionManager.shared.stableAdapter(for: $0) }
        badgeText = ctx.action(for: adapter)?.badgeText
    }
}

// MARK: - Site Setting Row

private struct SiteSettingRow<Control: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String?
    @ViewBuilder let control: () -> Control

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }

            Spacer()

            control()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background(isHovering ? .secondary.opacity(0.06) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
    }
}
```

- [ ] **Step 2: Build to verify compile**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

If there are type issues with optional managers (e.g., `contentBlockerManager`, `zoomManager`, `boostsManager`), check how they're accessed on `BrowserManager` and adjust the optional chaining.

- [ ] **Step 3: Commit**

```bash
git add Nook/Components/Extensions/ExtensionLibraryView.swift
git commit -m "feat: add ExtensionLibraryView with utilities, grid, and site settings"
```

---

### Task 4: Create ExtensionLibraryButton

**Files:**
- Create: `Nook/Components/Extensions/ExtensionLibraryButton.swift`

- [ ] **Step 1: Create the library button view**

Create `Nook/Components/Extensions/ExtensionLibraryButton.swift`:

```swift
//
//  ExtensionLibraryButton.swift
//  Nook
//

import SwiftUI
import AppKit

@available(macOS 15.5, *)
struct ExtensionLibraryButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    @State private var isHovering = false

    var body: some View {
        Button {
            togglePanel()
        } label: {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.6))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovering ? .primary.opacity(0.08) : .clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityLabel("Extension Library")
        .accessibilityHint("Opens site utilities and extensions panel")
        .onChange(of: windowState.isExtensionLibraryVisible) { _, visible in
            if !visible && panelController.isVisible {
                panelController.dismiss()
            }
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { _, _ in
            // Dismiss panel on tab switch
            if panelController.isVisible {
                panelController.dismiss()
                windowState.isExtensionLibraryVisible = false
            }
        }
    }

    private var panelController: ExtensionLibraryPanelController {
        if windowState.extensionLibraryPanelController == nil {
            windowState.extensionLibraryPanelController = ExtensionLibraryPanelController()
        }
        return windowState.extensionLibraryPanelController!
    }

    private func togglePanel() {
        guard let window = windowState.window, let settings = browserManager.nookSettings else { return }

        windowState.isExtensionLibraryVisible.toggle()

        if windowState.isExtensionLibraryVisible {
            panelController.show(
                anchorFrame: windowState.urlBarFrame,
                in: window,
                browserManager: browserManager,
                windowState: windowState,
                settings: settings
            )
        } else {
            panelController.dismiss()
        }
    }
}

```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Nook/Components/Extensions/ExtensionLibraryButton.swift
git commit -m "feat: add ExtensionLibraryButton for URL bar"
```

---

### Task 5: Integrate into URLBarView and TopBarView

**Files:**
- Modify: `Nook/Components/Sidebar/URLBarView.swift`
- Modify: `Nook/Components/Sidebar/TopBar/TopBarView.swift`

- [ ] **Step 1: Update URLBarView to show pinned extensions + library button**

In `Nook/Components/Sidebar/URLBarView.swift`, replace the current extension block (~lines 68-73):

```swift
// Extension action buttons
if #available(macOS 15.5, *),
   let extensionManager = browserManager.extensionManager {
    ExtensionActionView(extensions: extensionManager.installedExtensions)
        .environmentObject(browserManager)
}
```

With pinned extensions + library button:

```swift
// Pinned extension buttons + library button
if #available(macOS 15.5, *),
   let extensionManager = browserManager.extensionManager {
    let pinnedIDs = browserManager.nookSettings?.pinnedExtensionIDs ?? []
    let pinnedExtensions = extensionManager.installedExtensions.filter { pinnedIDs.contains($0.id) }

    if !pinnedExtensions.isEmpty {
        ExtensionActionView(extensions: pinnedExtensions)
            .environmentObject(browserManager)
    }

    ExtensionLibraryButton()
        .environmentObject(browserManager)
}
```

- [ ] **Step 2: Update TopBarView to remove extensionsView and add to URL bar area**

In `Nook/Components/Sidebar/TopBar/TopBarView.swift`, find the `extensionsView` computed property (~lines 142-154) and the reference to it in the body (~line 54).

Remove the `extensionsView` usage from the body HStack. Replace line 54 (`extensionsView`) with nothing — the extensions now live inside the `urlBar` computed property.

Then modify the `urlBar` computed property (~line 216) to include pinned extensions and the library button inside the URL bar's HStack, after the URL text and before the closing of the HStack:

```swift
private var urlBar: some View {
    HStack(spacing: 8) {
        if browserManager.currentTab(for: windowState) != nil {
            Text(displayURL)
                .font(.system(size: 13, weight: .medium, design: .default))
                .foregroundStyle(urlBarTextColor)
                .tracking(-0.1)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()

            // Pinned extension buttons + library button
            if #available(macOS 15.5, *),
               let extensionManager = browserManager.extensionManager {
                let pinnedIDs = browserManager.nookSettings?.pinnedExtensionIDs ?? []
                let pinnedExtensions = extensionManager.installedExtensions.filter { pinnedIDs.contains($0.id) }

                if !pinnedExtensions.isEmpty {
                    ExtensionActionView(extensions: pinnedExtensions)
                        .environmentObject(browserManager)
                }

                ExtensionLibraryButton()
                    .environmentObject(browserManager)
            }
        } else {
            EmptyView()
        }
    }
    // ... rest of modifiers unchanged
}
```

Then delete the `extensionsView` computed property entirely (lines 142-154).

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Manually test**

Open the app. Verify:
1. Library button (grid icon) appears in the URL bar
2. Clicking it opens the panel below the URL bar
3. Panel shows utility buttons, extension grid, and site settings
4. Clicking an extension triggers its action
5. Right-click an extension to pin/unpin
6. Pinned extensions appear as individual icons in the URL bar
7. Click outside dismisses the panel
8. Escape dismisses the panel
9. Switching tabs dismisses the panel

- [ ] **Step 5: Commit**

```bash
git add Nook/Components/Sidebar/URLBarView.swift Nook/Components/Sidebar/TopBar/TopBarView.swift
git commit -m "feat: integrate extension library button into URL bar, remove from TopBar"
```

---

### Task 6: Create ExtensionLibraryMoreMenu

**Files:**
- Create: `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift`
- Modify: `Nook/Components/Extensions/ExtensionLibraryView.swift` (wire up the more button)

- [ ] **Step 1: Create the more menu panel**

Create `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift`:

```swift
//
//  ExtensionLibraryMoreMenu.swift
//  Nook
//

import SwiftUI
import AppKit
import WebKit
import AVFoundation
import CoreLocation

@available(macOS 15.5, *)
@MainActor
final class ExtensionLibraryMoreMenuController {
    private var panel: NSPanel?
    private var localMonitor: Any?

    private let menuWidth: CGFloat = 260

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(
        anchorFrame: NSRect,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        onDismiss: @escaping () -> Void
    ) {
        let panel = self.panel ?? createPanel()
        self.panel = panel

        let content = MoreMenuView(
            browserManager: browserManager,
            windowState: windowState,
            onDismiss: { [weak self] in
                self?.dismiss()
                onDismiss()
            }
        )

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(visualEffect)
        container.addSubview(hosting)

        NSLayoutConstraint.activate([
            visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        panel.contentView = container

        // Position adjacent to main panel
        let fittingSize = hosting.fittingSize
        let panelSize = CGSize(width: menuWidth, height: fittingSize.height)

        // Try right side of anchor, fall back to left
        var origin = CGPoint(
            x: anchorFrame.maxX + 4,
            y: anchorFrame.maxY - panelSize.height
        )

        if let screen = NSScreen.main, origin.x + panelSize.width > screen.visibleFrame.maxX {
            origin.x = anchorFrame.minX - menuWidth - 4
        }

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.alphaValue = 0
        panel.orderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        installEventMonitor()
    }

    func dismiss() {
        guard let panel = panel, panel.isVisible else { return }
        removeEventMonitor()

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: menuWidth, height: 300)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        return panel
    }

    private func installEventMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return event }
            if let eventWindow = event.window, eventWindow == panel { return event }
            self.dismiss()
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
}

// MARK: - More Menu SwiftUI Content

@available(macOS 15.5, *)
private struct MoreMenuView: View {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let onDismiss: () -> Void

    @State private var cookieCount: Int?
    @State private var hasSiteData: Bool = false

    private var currentHost: String? {
        browserManager.currentTab(for: windowState)?.url.host
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MoreMenuItem(
                    icon: "list.bullet.rectangle",
                    iconColor: .orange,
                    label: "Cookies",
                    detail: cookieCount.map { "\($0)" } ?? "..."
                )

                MoreMenuItem(
                    icon: "folder.fill",
                    iconColor: .purple,
                    label: "Site Data",
                    detail: hasSiteData ? "Stored" : "None"
                )

                MoreMenuItem(
                    icon: "bell.fill",
                    iconColor: .red,
                    label: "Notifications",
                    detail: notificationStatus
                )

                MoreMenuItem(
                    icon: "location.fill",
                    iconColor: .blue,
                    label: "Location",
                    detail: locationStatus
                )

                MoreMenuItem(
                    icon: "mic.fill",
                    iconColor: .indigo,
                    label: "Microphone",
                    detail: micStatus
                )

                MoreMenuItem(
                    icon: "video.fill",
                    iconColor: .cyan,
                    label: "Camera",
                    detail: cameraStatus
                )

                Divider().opacity(0.15).padding(.horizontal, 10).padding(.vertical, 4)

                Button {
                    clearAllSiteData()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.red.opacity(0.9))
                            .frame(width: 26, height: 26)
                            .background(.red.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text("Clear All Site Data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red.opacity(0.9))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(currentHost == nil)
            }
            .padding(6)
        }
        .frame(width: 260)
        .onAppear { loadSiteInfo() }
    }

    private func loadSiteInfo() {
        guard let host = currentHost,
              let tab = browserManager.currentTab(for: windowState),
              let webView = tab.webView else { return }

        // Load cookie count
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            Task { @MainActor in
                self.cookieCount = cookies.filter { $0.domain.contains(host) }.count
            }
        }

        // Check for site data
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        webView.configuration.websiteDataStore.fetchDataRecords(ofTypes: dataTypes) { records in
            Task { @MainActor in
                self.hasSiteData = records.contains { $0.displayName.contains(host) }
            }
        }
    }

    private var notificationStatus: String {
        let center = UNUserNotificationCenter.current()
        // UNUserNotificationCenter doesn't have sync status check — use "Check" as placeholder
        return "Check"
    }

    private var locationStatus: String {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }

    private var micStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }

    private var cameraStatus: String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "Allowed"
        case .denied, .restricted: return "Blocked"
        default: return "Ask"
        }
    }

    private func clearAllSiteData() {
        guard let host = currentHost else { return }
        Task {
            await browserManager.cacheManager.clearCacheForDomain(host)
            await browserManager.cookieManager.deleteCookiesForDomain(host)
        }
        onDismiss()
    }
}

// MARK: - More Menu Item

private struct MoreMenuItem: View {
    let icon: String
    let iconColor: Color
    let label: String
    let detail: String

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 26, height: 26)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(label)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovering ? .secondary.opacity(0.07) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovering = $0 }
    }
}
```

- [ ] **Step 2: Wire up the more button in ExtensionLibraryView**

In `ExtensionLibraryView.swift`:

1. Add state: `@State private var moreMenuController = ExtensionLibraryMoreMenuController()`
2. Replace the footer's more button action from `showMoreMenu = true` to:

```swift
Button {
    // Get the panel's screen frame for positioning
    if let panelWindow = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible && $0.frame.width == 340 }) {
        moreMenuController.show(
            anchorFrame: panelWindow.frame,
            browserManager: browserManager,
            windowState: windowState,
            onDismiss: {}
        )
    }
} label: {
    // ... existing label
}
```

3. Remove the unused `@State private var showMoreMenu = false`.

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -10`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift Nook/Components/Extensions/ExtensionLibraryView.swift
git commit -m "feat: add more menu with cookies, permissions, and clear site data"
```

---

### Task 7: Migration & Polish

**Files:**
- Modify: `Settings/NookSettingsService.swift`

- [ ] **Step 1: Add first-launch migration for pinned extensions**

In `NookSettingsService.init()`, after the `pinnedExtensionIDs` initialization block, add migration logic. Since `ExtensionManager` may not be available at init time, the migration should happen lazily. Add a helper method:

```swift
/// Call once after ExtensionManager is ready on first launch to pin all existing extensions.
func migrateExtensionPinStateIfNeeded(installedExtensionIDs: [String]) {
    let migrationKey = "settings.pinnedExtensionIDsMigrated"
    guard !userDefaults.bool(forKey: migrationKey) else { return }
    userDefaults.set(true, forKey: migrationKey)

    // Pin all currently installed extensions so existing users
    // see the same URL bar they had before the library button was added
    if pinnedExtensionIDs.isEmpty {
        pinnedExtensionIDs = installedExtensionIDs
    }
}
```

- [ ] **Step 2: Call migration from URLBarView.onAppear (NOT the panel)**

The migration must run before pinned extensions are filtered, so it goes in `URLBarView.swift` (and `TopBarView.swift`), not the library panel. Add an `.onAppear` to the pinned extensions block:

```swift
.onAppear {
    if #available(macOS 15.5, *) {
        let installedIDs = browserManager.extensionManager?.installedExtensions
            .filter { $0.isEnabled }
            .map { $0.id } ?? []
        browserManager.nookSettings?.migrateExtensionPinStateIfNeeded(installedExtensionIDs: installedIDs)
    }
}
```

This ensures existing users see all their extensions pinned on first launch after the update, even if they never open the library panel.

- [ ] **Step 3: Build and test the full flow end-to-end**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Manual testing:
1. Fresh launch — all extensions should be pinned (visible in URL bar)
2. Unpin an extension via right-click in the library panel
3. Verify it disappears from the URL bar but stays in the panel grid
4. Pin it back — appears in URL bar again
5. Content blocker toggle works for current site
6. Zoom controls update the page zoom
7. More menu shows cookies and permissions
8. "Clear All Site Data" clears data for current domain

- [ ] **Step 4: Commit**

```bash
git add Settings/NookSettingsService.swift Nook/Components/Extensions/ExtensionLibraryView.swift
git commit -m "feat: add pin state migration for existing extension users"
```

---

### Task 8: Keyboard Shortcut

**Files:**
- Modify: `App/NookCommands.swift` (or wherever keyboard shortcuts are registered)

- [ ] **Step 1: Add Cmd+Shift+E shortcut to toggle the extension library panel**

Find where keyboard shortcuts are registered (likely in `NookCommands.swift` or via `KeyboardShortcutManager`). Add a command that toggles `windowState.isExtensionLibraryVisible`. The actual panel show/hide is handled by the `ExtensionLibraryButton`'s `onChange` observer.

- [ ] **Step 2: Build and test**

Run: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

Test: Press Cmd+Shift+E to toggle the panel.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add Cmd+Shift+E shortcut for extension library panel"
```
