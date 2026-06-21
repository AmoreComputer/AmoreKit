import AmoreJWT
import Crypto
import Foundation

@testable import AmoreLicensing

extension Product {
    /// Fixed sample used across the test suite. Avoids letters in the UUID so
    /// the string form is case-insensitive across encoders.
    static let testSample = Product(
        name: "Amore",
        identifier: "pro"
    )
}

/// Signs a production (v2) token carrying an object `product` claim.
func signV2Token(
    privateKey: Curve25519.Signing.PrivateKey,
    hardwareId: String,
    nonce: String,
    product: Product = .testSample,
    exp: Date = Date().addingTimeInterval(30 * 24 * 3600),
    iat: Date = Date(),
    licenseId: UUID = UUID()
) throws -> String {
    let payload = LicensePayload(
        exp: exp,
        hardwareId: hardwareId,
        iat: iat,
        licenseId: licenseId,
        nonce: nonce,
        product: product
    )
    return try EdDSAJWT.sign(payload, using: privateKey)
}

/// Test-only mirror of the pre-v2 payload: `product` is a bare string, with the
/// same JSON coding keys the old SDK shipped. Used to mint "old" cached tokens.
struct LicensePayloadV1Fixture: Encodable {
    var exp: Date
    var hardwareId: String
    var iat: Date
    var licenseId: UUID
    var nonce: String
    var product: String
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
}

/// Signs an "old" (v1) token carrying a bare-string `product` claim.
func signV1Token(
    privateKey: Curve25519.Signing.PrivateKey,
    hardwareId: String,
    nonce: String,
    productName: String = "Amore",
    exp: Date = Date().addingTimeInterval(30 * 24 * 3600),
    iat: Date = Date(),
    licenseId: UUID = UUID()
) throws -> String {
    let payload = LicensePayloadV1Fixture(
        exp: exp,
        hardwareId: hardwareId,
        iat: iat,
        licenseId: licenseId,
        nonce: nonce,
        product: productName
    )
    return try EdDSAJWT.sign(payload, using: privateKey)
}
