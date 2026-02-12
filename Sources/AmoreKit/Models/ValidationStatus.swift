import Foundation

public enum ValidationStatus: Sendable, Equatable {
    case gracePeriod(until: Date)
    case invalid
    case unknown
    case valid(until: Date)
}
