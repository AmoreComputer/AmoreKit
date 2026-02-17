import Foundation

public struct License: Identifiable, Hashable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var expiresAt: Date?
    public var entitlements: Set<String>
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

public extension Set where Element == String {
    
    func contains(_ member: LicenseEntitlement) -> Bool {
        self.contains(member.rawValue)
    }
    
}
