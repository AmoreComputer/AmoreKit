import Foundation
import JWTKit

protocol LicensePayloadProtocol {
    var exp: ExpirationClaim { get }
    var hardwareId: String { get }
    var iat: IssuedAtClaim { get }
    var licenseId: UUID { get }
    var nonce: String { get }
    var product: Product { get }
    var entitlements: Set<License.Entitlement> { get }
}

struct LicensePayload: JWTPayload, LicensePayloadProtocol {
    var exp: ExpirationClaim
    var hardwareId: String
    var iat: IssuedAtClaim
    var licenseId: UUID
    var nonce: String
    var product: Product
    var entitlements: Set<License.Entitlement> = []
    
    enum CodingKeys: String, CodingKey {
        case exp
        case hardwareId = "hardware_id"
        case iat
        case licenseId = "license_id"
        case nonce
        case product
        case entitlements
    }
    
    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}

struct GracePeriodPayload: JWTPayload, LicensePayloadProtocol {
    var exp: ExpirationClaim
    var hardwareId: String
    var iat: IssuedAtClaim
    var licenseId: UUID
    var nonce: String
    var product: Product
    var entitlements: Set<License.Entitlement> = []
    
    enum CodingKeys: String, CodingKey {
        case exp
        case hardwareId = "hardware_id"
        case iat
        case licenseId = "license_id"
        case nonce
        case product
        case entitlements
    }
    
    func verify(using algorithm: some JWTAlgorithm) throws {
        // Signature verified by JWTKit; expiration intentionally unchecked
    }
}
