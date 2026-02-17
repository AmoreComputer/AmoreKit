/// Configuration for license validation behavior.
public struct LicensingConfiguration: Sendable {
    var gracePeriod: GracePeriod
    var validationFrequency: ValidationFrequency
    
    /// Creates a licensing configuration.
    /// - Parameters:
    ///   - gracePeriod: How long to allow usage after token expiry. Defaults to 7 days.
    ///   - validationFrequency: How often to re-validate with the server. Defaults to weekly.
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
