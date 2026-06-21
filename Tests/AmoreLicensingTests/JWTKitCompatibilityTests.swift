import AmoreJWT
import Crypto
import Foundation
import JWTKit
import Testing

@testable import AmoreLicensing

/// Proves the shipped client stays byte-compatible with the JWTKit-based
/// tooling that mints keys and signs tokens server-side, for the *real*
/// ``LicensePayload`` wire shape rather than a synthetic stand-in. Catches
/// drift in the public-key encoding, snake_case keys, or nested claim types.
@Suite("JWTKit ↔ AmoreLicensing wire contract")
struct JWTKitCompatibilityTests {
    
    /// Mirrors the exact bytes the JWTKit-based server emits: NumericDate
    /// `exp`/`iat` claims and the snake_case keys ``LicensePayload`` expects.
    /// Frozen on purpose: if ``LicensePayload``'s coding keys or nested types
    /// drift away from this, the decode below fails.
    private struct ServerLicensePayload: JWTPayload {
        var exp: ExpirationClaim
        var hardwareId: String
        var iat: IssuedAtClaim
        var licenseId: UUID
        var nonce: String
        var product: Product
        var entitlements: Set<License.Entitlement>
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
        
        func verify(using algorithm: some JWTAlgorithm) throws {}
    }
    
    // MARK: - Public key string
    
    @Test func publicKeyStringIngestsIdenticallyToJWTKit() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let keyString = privateKey.publicKey.rawRepresentation.base64URLEncodedString()
        
        // JWTKit's interpretation (what deployed apps used) and AmoreLicensing's
        // must yield identical key bytes.
        let jwtKitKey = try EdDSA.PublicKey(x: keyString, curve: .ed25519)
        let amoreData = try #require(keyString.base64URLDecodedData())
        let amoreKey = try Curve25519.Signing.PublicKey(rawRepresentation: amoreData)
        #expect(amoreKey.rawRepresentation == jwtKitKey.rawRepresentation)
        
        // And the ingested key actually verifies a token the matching private key signed.
        let token = try signV2Token(privateKey: privateKey, hardwareId: "HW-1", nonce: "n-1")
        let payload = try EdDSAJWT.verify(token, as: LicensePayload.self, using: amoreKey)
        #expect(payload.hardwareId == "HW-1")
    }
    
    // MARK: - Payload wire shape
    
    @Test func jwtKitSignedLicensePayloadDecodesWithAmoreJWT() async throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let exp = Date().addingTimeInterval(3600)
        let iat = Date()
        let renewsAt = Date().addingTimeInterval(30 * 86_400)
        let licenseId = UUID()
        
        let server = ServerLicensePayload(
            exp: .init(value: exp),
            hardwareId: "HW-42",
            iat: .init(value: iat),
            licenseId: licenseId,
            nonce: "n-1",
            product: .testSample,
            entitlements: ["pro", "team"],
            subscriptionState: .renewing(renewsAt: renewsAt),
            customer: Customer(email: "licensed@example.com")
        )
        let keys = await JWTKeyCollection().add(eddsa: EdDSA.PrivateKey(backing: privateKey))
        let token = try await keys.sign(server)
        
        let decoded = try EdDSAJWT.verify(token, as: LicensePayload.self, using: privateKey.publicKey)
        
        #expect(decoded.hardwareId == "HW-42")
        #expect(decoded.licenseId == licenseId)
        #expect(decoded.nonce == "n-1")
        #expect(decoded.product == .testSample)
        #expect(decoded.entitlements == ["pro", "team"])
        #expect(decoded.customer?.email == "licensed@example.com")
        #expect(abs(decoded.exp.timeIntervalSince(exp)) < 1)
        #expect(abs(decoded.iat.timeIntervalSince(iat)) < 1)
        guard case .renewing(let decodedRenewsAt) = decoded.subscriptionState else {
            Issue.record("Expected .renewing subscription state")
            return
        }
        #expect(abs(decodedRenewsAt.timeIntervalSince(renewsAt)) < 1)
    }
}
