import Foundation

/// How stale a stored license may become before ``AmoreLicensing/validate()``
/// refreshes it from the server.
///
/// AmoreLicensing validates once at launch (except ``manual``); drive any
/// further checks by calling ``AmoreLicensing/validate()`` from your app's
/// lifecycle, for example when the window comes to the foreground.
public enum ValidationFrequency: Sendable, Equatable {
    /// Only refresh once the token has expired.
    case afterExpiration
    /// Refresh when the token is more than a day old.
    case daily
    /// Refresh on every ``AmoreLicensing/validate()`` call.
    case everyLaunch
    /// Never refresh proactively. Call ``AmoreLicensing/validate()`` yourself.
    case manual
    /// Refresh when the token is more than a month old.
    case monthly
    /// Refresh after a custom interval.
    case seconds(TimeInterval)
    /// Refresh when the token is more than a week old.
    case weekly

    /// Whether a server refresh is due for a token issued at `issuedAt`.
    ///
    /// ``manual`` and ``afterExpiration`` never refresh proactively (the token
    /// is only refreshed once it has actually expired); ``everyLaunch`` always
    /// refreshes; interval-based cases refresh once the interval has elapsed.
    func isRefreshDue(issuedAt: Date) -> Bool {
        guard let interval = timeInterval else { return false }
        return Date().timeIntervalSince(issuedAt) >= interval
    }

    /// Whether the license should be validated automatically at app launch.
    var shouldValidateAtLaunch: Bool {
        self != .manual
    }

    var timeInterval: TimeInterval? {
        switch self {
        case .afterExpiration: nil
        case .daily: 86_400
        case .everyLaunch: 0
        case .manual: nil
        case .monthly: 30 * 86_400
        case .seconds(let seconds): seconds
        case .weekly: 7 * 86_400
        }
    }
}
