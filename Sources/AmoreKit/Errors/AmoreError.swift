import Foundation

public enum AmoreError: LocalizedError, Equatable, Sendable {
    case client(ClientError)
    case hardwareIdMismatch
    case invalidSignature
    case keychain(KeychainError)
    case network(NetworkError)
    case nonceMismatch
    case noStoredToken
    
    public var errorDescription: String? {
        switch self {
        case .client(let error):
            return error.localizedDescription
        case .hardwareIdMismatch:
            return "This license is registered to a different device."
        case .invalidSignature:
            return "The server response has an invalid signature."
        case .keychain(let error):
            return error.localizedDescription
        case .network(let error):
            return error.message
        case .nonceMismatch:
            return "The server response failed nonce verification."
        case .noStoredToken:
            return "No stored license token found."
        }
    }
}
