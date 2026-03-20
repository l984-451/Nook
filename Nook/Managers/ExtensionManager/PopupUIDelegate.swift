//
//  PopupUIDelegate.swift
//  Nook
//
//  UI delegate for extension popup webviews.
//  Handles context menus and navigation events.
//

import os
import WebKit

// MARK: - Popup UI Delegate for Context Menu

@available(macOS 15.4, *)
class PopupUIDelegate: NSObject, WKUIDelegate, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionPopup")
    weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    #if os(macOS)
    func webView(
        _ webView: WKWebView,
        contextMenu: NSMenu
    ) -> NSMenu {
        // Add reload menu item at the top
        let reloadItem = NSMenuItem(
            title: "Reload Extension Popup",
            action: #selector(reloadPopup),
            keyEquivalent: "r"
        )
        reloadItem.target = self

        let menu = NSMenu()
        menu.addItem(reloadItem)
        menu.addItem(.separator())

        // Add original menu items
        for item in contextMenu.items {
            menu.addItem(item.copy() as! NSMenuItem)
        }

        return menu
    }
    #endif

    @objc private func reloadPopup() {
        Self.logger.debug("🔄 Reloading extension popup...")
        webView?.reload()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Self.logger.info("[POPUP] Navigation finished")
        Self.logger.debug("   Final URL: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("[POPUP] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Self.logger.error("[POPUP] Provisional navigation failed: \(error.localizedDescription)")
        Self.logger.debug("   URL: \(webView.url?.absoluteString ?? "nil")")
    }
}
