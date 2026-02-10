import JWTKit

struct LicensePayload: JWTPayload {
    var exp: ExpirationClaim
    var hardwareId: String
    var iat: IssuedAtClaim
    var licenseId: String
    var nonce: String

    enum CodingKeys: String, CodingKey {
        case exp
        case hardwareId = "hardware_id"
        case iat
        case licenseId = "license_id"
        case nonce
    }

    func verify(using algorithm: some JWTAlgorithm) throws {
        try exp.verifyNotExpired()
    }
}
