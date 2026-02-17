import Foundation

/// An error indicating a network request to the licensing server failed.
public struct NetworkError: LocalizedError, Equatable, Sendable {
    /// A human-readable description of the failure.
    public let message: String
    
    public var errorDescription: String? { message }
}
