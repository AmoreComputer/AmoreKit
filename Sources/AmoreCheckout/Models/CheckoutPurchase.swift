import AmoreLicensing
import struct AmoreStore.Price

/// A completed purchase: the license it activated and what checkout charged.
///
/// Carried by ``CheckoutResult/completed(_:)`` and
/// ``CheckoutState/completed(_:)``.
public struct CheckoutPurchase: Sendable, Hashable {
    /// The total charged at checkout, after discounts and tax, in the
    /// currency the customer paid in.
    ///
    /// This can differ from the product's price, and its `recurringInterval`
    /// is always `nil`. It is zero when checkout charged nothing, as for a
    /// trial or a full discount. For a bank debit that has not settled yet,
    /// it is the amount the bank debits. It is `nil` only when the server did
    /// not report the amount. ``CheckoutCompletion/displayPrice`` turns it
    /// into the price a receipt shows.
    public let amountPaid: Price?
    /// The license activated on this device.
    public let license: License
    /// The purchased license key, never persisted beyond the flow.
    public let licenseKey: String
    
    /// Creates a purchase, for previewing and testing code that handles
    /// ``CheckoutResult`` or ``CheckoutState``.
    public init(amountPaid: Price? = nil, license: License, licenseKey: String) {
        self.amountPaid = amountPaid
        self.license = license
        self.licenseKey = licenseKey
    }
}
