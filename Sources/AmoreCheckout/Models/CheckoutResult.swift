import AmoreLicensing
import Foundation

/// The outcome of an embedded checkout flow.
public enum CheckoutResult: Sendable, Hashable {
    /// The purchase completed and the license was activated on this device.
    case completed(License, licenseKey: String)
    /// The user dismissed checkout without completing a purchase.
    case cancelled
    /// The flow failed. `CheckoutError.activationFailed` carries the license
    /// key so it can always be shown to the user: the purchase succeeded even
    /// though automatic activation did not.
    case failed(CheckoutError)
}
