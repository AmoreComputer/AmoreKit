import Foundation

/// A failure talking to the licensing server's checkout endpoints.
public enum CheckoutClientError: LocalizedError, Hashable {
    /// The request could not be sent or its payload could not be encoded or decoded.
    case network(String)
    /// The response was not an HTTP response.
    case invalidResponse
    /// The server rejected the request because too many were made in a short window.
    case rateLimited
    /// The server returned an unexpected status code.
    case httpStatus(Int)
    
    public var errorDescription: String? {
        switch self {
        case .network(let message): message
        case .invalidResponse: "Invalid response from server."
        case .rateLimited: "Too many requests. Please try again later."
        case .httpStatus(let statusCode): "The server returned an unexpected response (\(statusCode))."
        }
    }
}
