import Foundation

@MainActor
internal protocol Licensing: Sendable {
    func activate(licenseKey: String) async throws
    func deactivate() async throws
    func validate() async throws -> ValidationStatus
    var status: ValidationStatus { get }
}

public struct LicensingConfiguration: Sendable {
    var gracePeriod: GracePeriod
    
    public init(gracePeriod: GracePeriod) {
        self.gracePeriod = gracePeriod
    }
    
    public static let `default` = LicensingConfiguration(gracePeriod: .days(7))
}

public enum GracePeriod: Sendable {
    case days(Int)
    case seconds(TimeInterval)
    
    var timeInterval: TimeInterval {
        switch self {
        case .days(let days): TimeInterval(days) * 86_400
        case .seconds(let seconds): seconds
        }
    }
}

public enum ValidationStatus: Sendable, Equatable {
    case gracePeriod(until: Date)
    case invalid
    case unknown
    case valid(until: Date)
}

public enum AmoreError: LocalizedError, Equatable, Sendable {
    case hardwareIdMismatch
    case invalidSignature
    case keychainError(String)
    case networkError(String)
    case nonceMismatch
    case noStoredToken
    case serverError(String)

    public var errorDescription: String? {
        switch self {
        case .hardwareIdMismatch:
            return "This license is registered to a different device."
        case .invalidSignature:
            return "The server response has an invalid signature."
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .nonceMismatch:
            return "The server response failed nonce verification."
        case .noStoredToken:
            return "No stored license token found."
        case .serverError(let message):
            return "Server error: \(message)"
        }
    }
}
