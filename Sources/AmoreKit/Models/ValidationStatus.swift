import Foundation

public enum ValidationStatus: Sendable, Equatable {
    case gracePeriod(License)
    case invalid
    case unknown
    case valid(License)
}
