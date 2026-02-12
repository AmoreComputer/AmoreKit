public struct LicensingConfiguration: Sendable {
    var gracePeriod: GracePeriod
    
    public init(gracePeriod: GracePeriod) {
        self.gracePeriod = gracePeriod
    }
    
    public static let `default` = LicensingConfiguration(gracePeriod: .days(7))
}
