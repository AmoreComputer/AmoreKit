import Foundation

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
