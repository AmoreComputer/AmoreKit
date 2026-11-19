import AmoreLicensing
import struct AmoreStore.Price
import struct AmoreStore.Product

/// The details of a completed purchase, handed to the success screen.
///
/// ``AmoreCheckoutView`` builds one when the flow reaches
/// ``CheckoutState/completed(_:)`` and passes it to its
/// `completedView` builder. The sheet's built-in success screen renders it
/// as a receipt; a custom screen reads the same details.
public struct CheckoutCompletion {
    /// The total charged at checkout, as ``CheckoutPurchase/amountPaid``
    /// describes.
    public let amountPaid: Price?
    /// The license activated on this device.
    public let license: License
    /// The purchased license key, never persisted beyond the flow.
    public let licenseKey: String
    /// Closes the container the success screen is shown in. The checkout sheet
    /// always supplies one; an ``AmoreCheckoutView`` supplies one only when its
    /// own `onDone` was passed, so a screen shown there offers its Done button
    /// conditionally, just as the default receipt does.
    public let onDone: (() -> Void)?
    /// The purchased product.
    public let product: Product
    
    /// Creates a completion, for previewing and testing a custom success screen.
    public init(
        amountPaid: Price? = nil,
        license: License,
        licenseKey: String,
        onDone: (() -> Void)? = nil,
        product: Product
    ) {
        self.amountPaid = amountPaid
        self.license = license
        self.licenseKey = licenseKey
        self.onDone = onDone
        self.product = product
    }

    /// Creates the completion for a purchase the flow completed, carrying
    /// over every detail the purchase holds.
    init(purchase: CheckoutPurchase, onDone: (() -> Void)?, product: Product) {
        self.init(
            amountPaid: purchase.amountPaid,
            license: purchase.license,
            licenseKey: purchase.licenseKey,
            onDone: onDone,
            product: product
        )
    }
}

extension CheckoutCompletion {
    /// The price to show on a receipt: the amount paid, or the product's
    /// price when `amountPaid` is `nil`.
    ///
    /// `nil` for a trial and for a subscription that charged nothing at
    /// checkout: both charge the price later, so a receipt that shows zero
    /// reads as free. Also `nil` when neither price is known.
    public var displayPrice: String? {
        if case .trialing = license.subscriptionState { return nil }
        if license.subscriptionState != nil, amountPaid?.unitAmount == 0 { return nil }
        return amountPaid?.displayPrice ?? product.displayPrice
    }
}
