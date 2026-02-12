@testable import AmoreLicensing

final class MockLicenseClient: LicenseClient, @unchecked Sendable {
    var onActivate: ((String, String, String) async throws -> String)?
    var onDeactivate: ((String) async throws -> Void)?
    var onValidate: ((String, String) async throws -> String)?

    func activate(licenseKey: String, hardwareId: String, nonce: String) async throws -> String {
        guard let handler = onActivate else {
            throw AmoreError.activationFailed("not configured")
        }
        return try await handler(licenseKey, hardwareId, nonce)
    }

    func deactivate(token: String) async throws {
        guard let handler = onDeactivate else {
            throw AmoreError.deactivationFailed("not configured")
        }
        try await handler(token)
    }

    func validate(token: String, nonce: String) async throws -> String {
        guard let handler = onValidate else {
            throw AmoreError.activationFailed("not configured")
        }
        return try await handler(token, nonce)
    }
}
