import Foundation

/// A product offered by an Amore-licensed application.
public struct Product: Identifiable, Hashable, Codable, Sendable {
    /// Server identifier for this product.
    public var id: UUID
    /// Display name configured by the app owner.
    public var name: String
    /// License duration in seconds, or `nil` for non-expiring licenses.
    public var durationInSeconds: Int?
    /// Maximum number of devices that can activate a single license for this product.
    public var deviceLimit: Int
    /// Pricing information, or `nil` when no price is configured.
    public var price: Price?
    
    /// The web checkout URL for this product.
    ///
    /// Prefer the `amoreCheckout(item:checkout:)` view modifier from the
    /// `AmoreCheckout` module, which presents checkout in-app and activates
    /// the purchased license automatically. Open this URL directly only when
    /// you want the plain browser flow with no activation or recovery:
    /// ```swift
    /// NSWorkspace.shared.open(product.checkoutURL)
    /// ```
    public var checkoutURL: URL
    
    public init(
        id: UUID,
        name: String,
        durationInSeconds: Int?,
        deviceLimit: Int,
        price: Price?,
        checkoutURL: URL
    ) {
        self.id = id
        self.name = name
        self.durationInSeconds = durationInSeconds
        self.deviceLimit = deviceLimit
        self.price = price
        self.checkoutURL = checkoutURL
    }
}

public extension Product {
    
    /// The localized string representation of the product price, suitable for display.
    var displayPrice: String? {
        price?.displayPrice
    }
    
}

extension Product: CustomStringConvertible {
    
    public var description: String {
        if let displayPrice {
            "\(name) (\(id)): \(displayPrice)"
        } else {
            "\(name) (\(id))"
        }
    }
    
}
