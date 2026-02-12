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

public enum AmoreError: Error, Equatable, Sendable {
    case activationFailed(String)
    case hardwareIdMismatch
    case invalidSignature
    case networkError(String)
    case nonceMismatch
    case deactivationFailed(String)
    case noStoredToken
}
