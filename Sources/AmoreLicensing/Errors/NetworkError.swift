import Foundation

/// An error indicating a network request to the licensing server failed.
public enum NetworkError: LocalizedError, Equatable, Sendable {
    case rateLimited
    case requestFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .rateLimited: "Too many requests. Please try again later."
        case .requestFailed(let message): message
        }
    }
}
