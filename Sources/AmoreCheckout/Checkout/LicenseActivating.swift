import AmoreLicensing

/// The slice of `AmoreLicensing` the checkout flow needs, as a seam for tests.
@MainActor
protocol LicenseActivating: AnyObject {
    var status: ValidationStatus { get }
    func activate(licenseKey: String) async throws(AmoreError)
}

extension AmoreLicensing: LicenseActivating {}
