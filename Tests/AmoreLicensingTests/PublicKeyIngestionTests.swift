import AmoreJWT
import Crypto
import Foundation
import Testing

@testable import AmoreLicensing

/// Exercises the public ``AmoreLicensing/init(publicKey:bundleIdentifier:configuration:server:tokenStore:)``
/// string-to-key path: the one place a deployed app's hardcoded key string is
/// ingested. ``ValidationFrequency/manual`` keeps the initializer side-effect
/// free (no launch validation, no network).
@MainActor
@Suite("Public key ingestion")
struct PublicKeyIngestionTests {
    private let manual = LicensingConfiguration(validationFrequency: .manual)
    
    @Test func acceptsWellFormedKeyString() throws {
        let keyString = Curve25519.Signing.PrivateKey()
            .publicKey.rawRepresentation.base64URLEncodedString()
        _ = try AmoreLicensing(
            publicKey: keyString,
            bundleIdentifier: "com.test.amorekit",
            configuration: manual,
            tokenStore: MockTokenStore()
        )
    }
    
    @Test func rejectsUndecodableKeyString() {
        #expect(throws: AmoreError.invalidPublicKey) {
            _ = try AmoreLicensing(
                publicKey: "not base64 !!!",
                bundleIdentifier: "com.test.amorekit",
                configuration: manual,
                tokenStore: MockTokenStore()
            )
        }
    }
    
    @Test func rejectsWrongLengthKeyString() {
        let tooShort = Data([1, 2, 3, 4]).base64URLEncodedString()
        #expect(throws: AmoreError.invalidPublicKey) {
            _ = try AmoreLicensing(
                publicKey: tooShort,
                bundleIdentifier: "com.test.amorekit",
                configuration: manual,
                tokenStore: MockTokenStore()
            )
        }
    }
}
