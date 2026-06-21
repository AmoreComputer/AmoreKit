import Foundation

/// A validated software license with its associated metadata.
public struct License: Identifiable, Hashable, Codable, Sendable {
    /// Unique identifier for the license.
    public var id: UUID
    /// The product this license is for.
    public var product: Product
    /// When the license expires, or `nil` if it never expires.
    public var expiresAt: Date?
    /// The set of entitlement keys granted by this license.
    public var entitlements: Set<Entitlement>
    /// Subscription state if this license is subscription-backed,
    /// or `nil` for perpetual / one-time-purchase licenses.
    public var subscriptionState: SubscriptionState?
    /// The customer this license was issued to, or `nil` if the license has no
    /// associated customer. Use `customer?.email` to show "Licensed to <email>".
    public var customer: Customer?
    
    /// The product name this license is for.
    @available(*, deprecated, renamed: "product.name", message: "Use `product.name` instead.")
    public var name: String { product.name }
}

extension License {
    
    init(from payload: LicensePayload) {
        self = License(
            id: payload.licenseId,
            product: payload.product,
            expiresAt: payload.exp,
            entitlements: payload.entitlements,
            subscriptionState: payload.subscriptionState,
            customer: payload.customer
        )
    }
    
}
