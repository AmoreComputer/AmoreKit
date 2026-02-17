import Foundation

/// A validated software license with its associated metadata.
public struct License: Identifiable, Hashable, Codable, Sendable {
    /// Unique identifier for the license.
    public var id: UUID
    /// The product name this license is for.
    public var name: String
    /// When the license expires, or `nil` if it never expires.
    public var expiresAt: Date?
    /// The set of entitlement keys granted by this license.
    public var entitlements: Set<Entitlement>
}

extension License {
    
    init(from payload: some LicensePayloadProtocol) {
        self = License(
            id: payload.licenseId,
            name: payload.product,
            expiresAt: payload.exp.value,
            entitlements: payload.entitlements
        )
    }
    
}
