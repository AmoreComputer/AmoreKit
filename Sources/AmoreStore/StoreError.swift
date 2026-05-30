import Foundation

/// Errors thrown by ``AmoreStore/products()``.
public enum StoreError: LocalizedError, Equatable, Sendable {
    /// The network request failed (offline, timeout, or an unexpected transport error).
    case network(String)
    /// The server rejected the request because too many were made in a short window.
    case rateLimited
    /// No app matches the configured bundle identifier.
    case appNotFound
    /// The server returned an unexpected status code.
    case serverError(statusCode: Int)
    
    public var errorDescription: String? {
        switch self {
        case .network(let message): message
        case .rateLimited: "Too many requests. Please try again later."
        case .appNotFound: "App not found."
        case .serverError(let statusCode): "The server returned an unexpected response (\(statusCode))."
        }
    }
}
