import Foundation
import JWTKit

struct LicensePayload: JWTPayload {
    var exp: ExpirationClaim
    var hardwareId: String
    var iat: IssuedAtClaim
    var licenseId: UUID
    var nonce: String
    var product: String = "Amore"
    var entitlements: Set<String> = []
    
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
