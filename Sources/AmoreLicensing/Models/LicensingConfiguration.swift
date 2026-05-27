import Foundation

/// Configuration for license validation behavior.
public struct LicensingConfiguration: Sendable {
    /// How long to allow usage after token expiry. Defaults to 7 days.
    public var gracePeriod: GracePeriod
    /// How often to re-validate with the server. Defaults to weekly.
    public var validationFrequency: ValidationFrequency
    
    /// Possible token store locations
    public enum TokenStoreLocation: Sendable {
        case defaultLocation             // The default location.
        case directory(URL)              // Caller provided directory path.
        case appGroup(String)            // App Group identifier (e.g. com.company.appname).
        case keychainAccessGroup(String) // Access Group name.
    }

    /// Location of the token store.
    public var tokenStoreLocation: TokenStoreLocation

    /// Creates a licensing configuration.
    /// - Parameters:
    ///   - gracePeriod: How long to allow usage after token expiry. Defaults to 7 days.
    ///   - validationFrequency: How often to re-validate with the server. Defaults to weekly.
    public init(
        gracePeriod: GracePeriod = .days(7),
        validationFrequency: ValidationFrequency = .weekly,
        tokenStoreLocation: TokenStoreLocation = .defaultLocation
    ) {
        self.gracePeriod = gracePeriod
        self.validationFrequency = validationFrequency
        self.tokenStoreLocation = tokenStoreLocation
    }
    
    /// A default configuration with a 7-day grace period and weekly validation.
    public static let `default` = LicensingConfiguration()
}
