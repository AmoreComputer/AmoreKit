import Foundation
import AmoreLicensing

/// Errors surfaced by the embedded checkout flow.
public enum CheckoutError: Error, Sendable, Hashable {
    /// The checkout session could not be created.
    case sessionCreationFailed(underlying: CheckoutClientError)
    /// The session was created but could not be recorded on this device, so a
    /// purchase interrupted by the app quitting could not be recovered. The
    /// session is abandoned before payment rather than charging for a checkout
    /// that cannot be resumed.
    case checkoutNotRecordable
    /// A purchase interrupted earlier could not be resolved, so no new session
    /// was created: charging again risks paying twice for the same license.
    /// `underlying` is the status check's failure, or `nil` when the server
    /// reported a paid session without the license key it should carry.
    /// Retrying re-checks that session and picks it up if it was paid.
    case pendingSessionUnresolved(underlying: CheckoutClientError?)
    /// The checkout session expired, or the server no longer has any record
    /// of it, before payment completed.
    case sessionExpired
    /// The server could not be reached for long enough that the flow stopped
    /// waiting for payment. The session is untouched: retrying re-checks it
    /// and picks it up if it was paid in a browser tab after all.
    case pollingFailed(underlying: CheckoutClientError)
    /// Payment succeeded but the server did not issue the license before the
    /// flow stopped waiting for it. The purchase is not lost: the pending
    /// session outlives this failure, so a retry or the next launch's
    /// ``AmoreCheckout/recoverPendingPurchase()`` picks the license up.
    case licenseIssuanceTimedOut
    /// Payment succeeded but the license could not be activated on this device.
    case activationFailed(licenseKey: String, underlying: AmoreError)
}

extension CheckoutError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .sessionCreationFailed(let underlying):
            underlying.errorDescription
        case .checkoutNotRecordable:
            "Checkout could not start because this purchase could not be saved on your Mac. You have not been charged."
            // The transport detail matters less than the fact that an earlier
            // purchase is unconfirmed and retrying is safe.
        case .pendingSessionUnresolved:
            "Your previous purchase could not be confirmed. Please try again."
        case .sessionExpired:
            "This checkout session has expired."
        case .pollingFailed:
            "Checkout lost contact with the server. If you completed a payment, it will be picked up the next time you open the app."
        case .licenseIssuanceTimedOut:
            "Your payment went through, but your license has not arrived yet. It will finish activating shortly, or the next time you open the app."
        case .activationFailed(_, let underlying):
            underlying.errorDescription
        }
    }
}
