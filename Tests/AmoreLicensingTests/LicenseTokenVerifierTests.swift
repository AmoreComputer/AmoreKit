import AmoreJWT
import Crypto
import Foundation
import Testing

@testable import AmoreLicensing

@Suite("LicenseTokenVerifier")
struct LicenseTokenVerifierTests {
    private let hardwareId = "TEST-SERIAL-123"
    private let privateKey = Curve25519.Signing.PrivateKey()
    
    private func makeVerifier(
        publicKey: Curve25519.Signing.PublicKey? = nil,
        hardwareId: String? = nil
    ) -> LicenseTokenVerifier {
        LicenseTokenVerifier(
            publicKey: publicKey ?? privateKey.publicKey,
            deviceIdentity: MockDeviceIdentity(identifier: hardwareId ?? self.hardwareId)
        )
    }
    
    // MARK: - decode
    
    @Test func decodeReturnsPayloadForValidToken() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "n-1")
        let payload = try makeVerifier().decode(token, expectedNonce: "n-1")
        #expect(payload.hardwareId == hardwareId)
        #expect(payload.nonce == "n-1")
    }
    
    @Test func decodeThrowsNonceMismatchWhenNonceDiffers() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "issued")
        #expect(throws: AmoreError.nonceMismatch) {
            try makeVerifier().decode(token, expectedNonce: "expected")
        }
    }
    
    @Test func decodeSkipsNonceCheckWhenNoneExpected() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "n-1")
        let payload = try makeVerifier().decode(token)
        #expect(payload.nonce == "n-1")
    }
    
    @Test func decodeThrowsHardwareIdMismatchForOtherDevice() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: "OTHER-HW", nonce: "n-1")
        #expect(throws: AmoreError.hardwareIdMismatch) {
            try makeVerifier().decode(token, expectedNonce: "n-1")
        }
    }
    
    @Test func decodeThrowsInvalidTokenForWrongKey() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "n-1")
        let otherKey = Curve25519.Signing.PrivateKey().publicKey
        #expect(throws: AmoreError.invalidToken) {
            try makeVerifier(publicKey: otherKey).decode(token, expectedNonce: "n-1")
        }
    }
    
    @Test func decodeRejectsExpiredTokenWhenVerifyingTimeClaims() throws {
        let token = try signV2Token(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "n-1",
            exp: Date().addingTimeInterval(-3600)
        )
        #expect(throws: AmoreError.invalidToken) {
            try makeVerifier().decode(token, expectedNonce: "n-1")
        }
    }
    
    // MARK: - decodeLocally
    
    @Test func decodeLocallyToleratesExpiredToken() throws {
        let token = try signV2Token(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "n-1",
            exp: Date().addingTimeInterval(-3600)
        )
        guard case .decoded(let payload) = makeVerifier().decodeLocally(token) else {
            Issue.record("Expected .decoded for an expired but otherwise valid token")
            return
        }
        #expect(payload.hardwareId == hardwareId)
    }
    
    @Test func decodeLocallyReturnsHardwareMismatch() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: "OTHER-HW", nonce: "n-1")
        guard case .hardwareMismatch = makeVerifier().decodeLocally(token) else {
            Issue.record("Expected .hardwareMismatch")
            return
        }
    }
    
    @Test func decodeLocallyReturnsUnverifiableForWrongKey() throws {
        let token = try signV2Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "n-1")
        let otherKey = Curve25519.Signing.PrivateKey().publicKey
        guard case .unverifiable = makeVerifier(publicKey: otherKey).decodeLocally(token) else {
            Issue.record("Expected .unverifiable")
            return
        }
    }
}
