import Foundation

/// How often the license should be re-validated with the server.
public enum ValidationFrequency: Sendable {
    /// Only re-validate after the token has expired.
    case afterExpiration
    /// Re-validate once per day.
    case daily
    /// Re-validate on every app launch.
    case everyLaunch
    /// Re-validate once per month.
    case monthly
    /// Re-validate after a custom interval.
    case seconds(TimeInterval)
    /// Re-validate once per week.
    case weekly

    var timeInterval: TimeInterval? {
        switch self {
        case .afterExpiration: nil
        case .daily: 86_400
        case .everyLaunch: 0
        case .monthly: 30 * 86_400
        case .seconds(let seconds): seconds
        case .weekly: 7 * 86_400
        }
    }
}
