import Foundation

public enum ValidationFrequency: Sendable {
    case afterExpiration
    case daily
    case everyLaunch
    case monthly
    case seconds(TimeInterval)
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
