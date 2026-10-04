import Foundation

/// The result of a license validation check.
public enum ValidationStatus: Sendable, Equatable {
    /// The stored token has expired and no refresh has succeeded yet. The
    /// license works until ``LicensingConfiguration/gracePeriod`` elapses.
    case gracePeriod(License)
    /// The license is invalid or revoked.
    case invalid
    /// No license has been validated yet.
    case unknown
    /// The license is valid and active.
    case valid(License)
}
