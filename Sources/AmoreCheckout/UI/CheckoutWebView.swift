import AppKit
import SwiftUI
import WebKit

/// Hosts the checkout page and routes success/cancel redirects to the flow.
struct CheckoutWebView: NSViewRepresentable {
    let url: URL
    let checkout: AmoreCheckout
    let onLoadFailure: (Error) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(url, in: webView)
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.onLoadFailure = onLoadFailure
        context.coordinator.load(url, in: nsView)
    }
    
    func makeCoordinator() -> NavigationDelegate {
        NavigationDelegate(checkout: checkout, onLoadFailure: onLoadFailure)
    }
    
    @MainActor
    final class NavigationDelegate: NSObject, WKNavigationDelegate, WKUIDelegate {
        var onLoadFailure: (Error) -> Void
        
        private let checkout: AmoreCheckout
        private var requestedURL: URL?
        
        init(checkout: AmoreCheckout, onLoadFailure: @escaping (Error) -> Void) {
            self.checkout = checkout
            self.onLoadFailure = onLoadFailure
        }
        
        func load(_ url: URL, in webView: WKWebView) {
            guard requestedURL != url else { return }
            requestedURL = url
            webView.load(URLRequest(url: url))
        }
        
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            switch checkout.navigationAction(for: url) {
            case .allow:
                decisionHandler(.allow)
            case .interceptSuccess:
                decisionHandler(.cancel)
                checkout.handleSuccessRedirect()
            case .interceptCancel:
                decisionHandler(.cancel)
                checkout.handleCancelRedirect()
            }
        }
        
        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            report(error)
        }
        
        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: any Error
        ) {
            report(error)
        }
        
        private func report(_ error: any Error) {
            guard (error as NSError).code != NSURLErrorCancelled else { return }
            requestedURL = nil
            onLoadFailure(error)
        }
    }
}
