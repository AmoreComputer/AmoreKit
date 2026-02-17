public struct LicensingConfiguration: Sendable {
    var gracePeriod: GracePeriod
    var validationFrequency: ValidationFrequency
    
    public init(
        gracePeriod: GracePeriod = .days(7),
        validationFrequency: ValidationFrequency = .weekly
    ) {
        self.gracePeriod = gracePeriod
        self.validationFrequency = validationFrequency
    }
    
    public static let `default` = LicensingConfiguration()
}
