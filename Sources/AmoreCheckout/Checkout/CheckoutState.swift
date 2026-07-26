import Foundation
import AmoreLicensing

/// Where the checkout flow currently stands.
public enum CheckoutState: Sendable, Hashable {
    /// No checkout is running. Also the state after a cancellation.
    case idle
    /// ``AmoreCheckout/start(_:customerEmail:)`` was called; the checkout
    /// session is being created.
    case preparing
    /// The session is open at the given checkout URL and payment is up to
    /// the user, whether in an embedded web view or the external browser.
    case awaitingPayment(URL)
    /// Payment was detected; the license is being issued and activated.
    /// The purchase is no longer safely cancellable.
    case activating
    /// The purchase completed and the license is active on this device.
    case completed(License, licenseKey: String)
    /// The flow failed. ``CheckoutError/activationFailed(licenseKey:underlying:)``
    /// means payment succeeded; keep showing the license key it carries.
    case failed(CheckoutError)
}

extension CheckoutState {
    /// Whether the flow can still be abandoned without losing a payment:
    /// `true` until payment is detected, `false` from ``activating`` on.
    public var isCancellable: Bool {
        switch self {
        case .preparing, .awaitingPayment: true
        case .idle, .activating, .completed, .failed: false
        }
    }
}
