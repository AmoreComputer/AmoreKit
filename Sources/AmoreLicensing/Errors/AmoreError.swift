import Foundation

/// Errors thrown by AmoreLicensing operations.
public enum AmoreError: LocalizedError, Equatable, Sendable {
    /// A server-returned client error.
    case client(ClientError)
    /// The license token's hardware ID does not match this device.
    case hardwareIdMismatch
    /// The server response has an invalid cryptographic signature.
    case invalidSignature
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
        case .invalidSignature:
            return "The server response has an invalid signature."
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
