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
