protocol LicenseClient: Sendable {
    func activate(licenseKey: String, hardwareId: String, nonce: String) async throws -> String
    func deactivate(hardwareId: String, token: String) async throws
    func validate(token: String, nonce: String) async throws -> String
}
