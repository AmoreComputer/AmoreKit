import Foundation

/// The result of a license validation check.
public enum ValidationStatus: Sendable, Equatable {
    /// The license has expired but is within the configured grace period.
    case gracePeriod(License)
    /// The license is invalid or revoked.
    case invalid
    /// No license has been validated yet.
    case unknown
    /// The license is valid and active.
    case valid(License)
}
