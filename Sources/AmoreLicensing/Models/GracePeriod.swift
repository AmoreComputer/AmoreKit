import Foundation

/// The duration after token expiry during which the license remains usable.
public enum GracePeriod: Sendable {
    /// A grace period measured in days.
    case days(Int)
    /// A grace period measured in seconds.
    case seconds(TimeInterval)
    
    var timeInterval: TimeInterval {
        switch self {
        case .days(let days): TimeInterval(days) * 86_400
        case .seconds(let seconds): seconds
        }
    }
}
