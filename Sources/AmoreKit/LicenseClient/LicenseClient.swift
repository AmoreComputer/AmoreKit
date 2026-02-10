protocol LicenseClient: Sendable {
    func activate(licenseKey: String, hardwareId: String, nonce: String) async throws -> String
    func refresh(hardwareId: String, oldToken: String, nonce: String) async throws -> String
}
