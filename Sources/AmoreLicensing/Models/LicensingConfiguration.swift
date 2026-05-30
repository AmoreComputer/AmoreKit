/// Configuration for license validation behavior.
public struct LicensingConfiguration: Sendable {
    /// How long to allow usage after token expiry. Defaults to 7 days.
    public var gracePeriod: GracePeriod
    /// How stale a cached license may become before ``AmoreLicensing/validate()`` refreshes it. Defaults to weekly.
    public var validationFrequency: ValidationFrequency
    
    /// Creates a licensing configuration.
    /// - Parameters:
    ///   - gracePeriod: How long to allow usage after token expiry. Defaults to 7 days.
    ///   - validationFrequency: How stale a cached license may become before ``AmoreLicensing/validate()`` refreshes it. Defaults to weekly.
    public init(
        gracePeriod: GracePeriod = .days(7),
        validationFrequency: ValidationFrequency = .weekly
    ) {
        self.gracePeriod = gracePeriod
        self.validationFrequency = validationFrequency
    }
    
    /// A default configuration with a 7-day grace period and weekly validation.
    public static let `default` = LicensingConfiguration()
}
