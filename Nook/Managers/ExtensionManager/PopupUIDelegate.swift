//
//  PopupUIDelegate.swift
//  Nook
//
//  UI delegate for extension popup webviews.
//  Handles context menus, navigation events, and diagnostic logging.
//

import os
import WebKit

// MARK: - Popup UI Delegate

@available(macOS 15.4, *)
class PopupUIDelegate: NSObject, WKUIDelegate, WKNavigationDelegate {
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionPopup")
    weak var webView: WKWebView?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
    }

    // MARK: - WKUIDelegate

    #if os(macOS)
    func webView(
        _ webView: WKWebView,
        contextMenu: NSMenu
    ) -> NSMenu {
        let reloadItem = NSMenuItem(
            title: "Reload Extension Popup",
            action: #selector(reloadPopup),
            keyEquivalent: "r"
        )
        reloadItem.target = self

        let menu = NSMenu()
        menu.addItem(reloadItem)
        menu.addItem(.separator())

        for item in contextMenu.items {
            menu.addItem(item.copy() as! NSMenuItem)
        }

        return menu
    }
    #endif

    @objc private func reloadPopup() {
        Self.logger.debug("Reloading extension popup...")
        webView?.reload()
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("[POPUP] Started loading: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("[POPUP] Committed: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[POPUP] Finished loading: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[POPUP] Navigation FAILED: \(error.localizedDescription)")
        print("[POPUP]   URL: \(webView.url?.absoluteString ?? "nil")")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[POPUP] Provisional navigation FAILED: \(error.localizedDescription)")
        print("[POPUP]   URL: \(webView.url?.absoluteString ?? "nil")")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("[POPUP] ERROR: Web content process terminated unexpectedly")
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        print("[POPUP] decidePolicyFor: \(navigationAction.request.url?.absoluteString ?? "nil")")
        return .allow
    }
}
