import Foundation

/// Errors thrown by AmoreLicensing operations.
public enum AmoreError: LocalizedError, Equatable, Sendable {
    /// A server-returned client error.
    case client(ClientError)
    /// The license token's hardware ID does not match this device.
    case hardwareIdMismatch
    /// The configured public key is not a valid Ed25519 key.
    case invalidPublicKey
    /// The server response could not be verified (bad signature, malformed,
    /// expired on arrival, or otherwise unparseable).
    case invalidToken
    /// A token store operation failed.
    case tokenStore(TokenStoreError)
    /// A network request failed.
    case network(NetworkError)
    /// The server response failed nonce verification.
    case nonceMismatch
    /// No license token is stored locally.
    case noStoredToken
    
    public var errorDescription: String? {
        switch self {
        case .client(let error):
            return error.localizedDescription
        case .hardwareIdMismatch:
            return "This license is registered to a different device."
        case .invalidPublicKey:
            return "The configured public key is invalid."
        case .invalidToken:
            return "The server response could not be verified."
        case .tokenStore(let error):
            return error.localizedDescription
        case .network(let error):
            return error.localizedDescription
        case .nonceMismatch:
            return "The server response failed nonce verification."
        case .noStoredToken:
            return "No stored license token found."
        }
    }
}
