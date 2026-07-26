import Foundation

enum CheckoutNavigationAction: Equatable {
    case allow
    case interceptSuccess
    case interceptCancel
}

// The server's success and cancel redirect pages are intercepted before they
// render and folded back into the flow.
extension AmoreCheckout {
    func navigationAction(for url: URL) -> CheckoutNavigationAction {
        if matches(url, pathSuffix: "checkout/success") { return .interceptSuccess }
        if matches(url, pathSuffix: "checkout/cancel") { return .interceptCancel }
        return .allow
    }
    
    // The polling loop picks up the completed session and activates as usual.
    func handleSuccessRedirect() {
        guard isInProgress else { return }
        state = .activating
    }
    
    func handleCancelRedirect() {
        if case .activating = state { return }
        cancel()
    }
    
    private func matches(_ url: URL, pathSuffix: String) -> Bool {
        guard url.scheme == baseURL.scheme, url.host() == baseURL.host() else { return false }
        let expected = baseURL.appending(path: pathSuffix).path()
        return url.path() == expected || url.path().hasPrefix(expected + "/")
    }
}
