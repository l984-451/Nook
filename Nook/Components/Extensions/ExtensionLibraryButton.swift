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
                        .fill(.primary.opacity(isHovering ? 0.08 : 0))
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
