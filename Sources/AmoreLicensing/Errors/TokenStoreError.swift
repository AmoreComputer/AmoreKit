import Foundation

/// Errors from token store operations used to persist license tokens.
public enum TokenStoreError: LocalizedError, Equatable, Sendable {
    case deleteFailed(String)
    case retrieveFailed(String)
    case storeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .deleteFailed(let reason): "Token delete failed: \(reason)"
        case .retrieveFailed(let reason): "Token retrieve failed: \(reason)"
        case .storeFailed(let reason): "Token store failed: \(reason)"
        }
    }
}
