import AmoreJWT
import Crypto
import Foundation

/// Verifies signed license tokens against the app's public key and this device's
/// identity.
///
/// Pure and stateless: it performs no I/O and holds no mutable state, so the
/// signature, nonce, hardware, and expiry checks can be exercised in isolation.
struct LicenseTokenVerifier: Sendable {
    
    /// The outcome of a best-effort local decode that tolerates expired tokens.
    enum LocalResult: Sendable {
        case decoded(LicensePayload)
        case hardwareMismatch
        case unverifiable
    }
    
    let publicKey: Curve25519.Signing.PublicKey
    let deviceIdentity: any DeviceIdentity
    
    /// Verifies a token's signature and claims and returns its payload.
    /// - Parameters:
    ///   - token: The signed JWT to verify.
    ///   - expectedNonce: If provided, the payload's nonce must match it.
    ///   - verifyTimeClaims: Whether to reject expired or not-yet-valid tokens.
    /// - Throws: ``AmoreError`` if the signature, nonce, or hardware ID is invalid.
    func decode(
        _ token: String,
        expectedNonce: String? = nil,
        verifyTimeClaims: Bool = true
    ) throws(AmoreError) -> LicensePayload {
        let payload: LicensePayload
        do {
            payload = try EdDSAJWT.verify(
                token, as: LicensePayload.self, using: publicKey,
                verifyTimeClaims: verifyTimeClaims
            )
        } catch {
            throw .invalidToken
        }
        if let expectedNonce, payload.nonce != expectedNonce { throw .nonceMismatch }
        guard payload.hardwareId == deviceIdentity.identifier else { throw .hardwareIdMismatch }
        return payload
    }
    
    /// Decodes a stored token without enforcing time claims, classifying the
    /// result so callers can tell a hardware mismatch from an unverifiable token.
    func decodeLocally(_ token: String) -> LocalResult {
        do {
            return .decoded(try decode(token, verifyTimeClaims: false))
        } catch .hardwareIdMismatch {
            return .hardwareMismatch
        } catch {
            return .unverifiable
        }
    }
}
