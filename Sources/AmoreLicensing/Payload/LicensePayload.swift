import Foundation

struct LicensePayload: Codable, Sendable {
    var exp: Date
    var hardwareId: String
    var iat: Date
    var licenseId: UUID
    var nonce: String
    var product: Product
    var entitlements: Set<License.Entitlement> = []
    var subscriptionState: SubscriptionState?
    var customer: Customer?
    
    enum CodingKeys: String, CodingKey {
        case exp
        case hardwareId = "hardware_id"
        case iat
        case licenseId = "license_id"
        case nonce
        case product
        case entitlements
        case subscriptionState = "subscription_state"
        case customer
    }
}
