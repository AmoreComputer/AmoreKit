import Foundation

/// Errors from keychain operations used to store and retrieve license tokens.
public enum KeychainError: LocalizedError, Equatable, Sendable {
    case deleteFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case storeFailed(OSStatus)
    
    public var errorDescription: String? {
        switch self {
        case .deleteFailed(let status): "Keychain delete failed: \(status)"
        case .retrieveFailed(let status): "Keychain retrieve failed: \(status)"
        case .storeFailed(let status): "Keychain store failed: \(status)"
        }
    }
}
