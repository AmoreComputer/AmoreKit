import AmoreLicensing
import struct AmoreStore.Product

/// The details of a completed purchase, handed to the success screen.
///
/// ``AmoreCheckoutView`` builds one when the flow reaches
/// ``CheckoutState/completed(_:licenseKey:)`` and passes it to its
/// `completedView` builder. The sheet's built-in success screen renders it
/// as a receipt; a custom screen reads the same details.
public struct CheckoutCompletion {
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
        license: License,
        licenseKey: String,
        onDone: (() -> Void)? = nil,
        product: Product
    ) {
        self.license = license
        self.licenseKey = licenseKey
        self.onDone = onDone
        self.product = product
    }
}
