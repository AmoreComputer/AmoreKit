import Foundation

public struct NetworkError: LocalizedError, Equatable, Sendable {
    public let message: String
    
    public var errorDescription: String? { message }
}
