@testable import AmoreLicensing

final class MockLicenseClient: LicenseClient, @unchecked Sendable {
    var onActivate: ((String, String, String) async throws -> String)?
    var onRefresh: ((String, String, String) async throws -> String)?

    func activate(licenseKey: String, hardwareId: String, nonce: String) async throws -> String {
        guard let handler = onActivate else {
            throw AmoreError.activationFailed("not configured")
        }
        return try await handler(licenseKey, hardwareId, nonce)
    }

    func refresh(hardwareId: String, oldToken: String, nonce: String) async throws -> String {
        guard let handler = onRefresh else {
            throw AmoreError.activationFailed("not configured")
        }
        return try await handler(hardwareId, oldToken, nonce)
    }
}
