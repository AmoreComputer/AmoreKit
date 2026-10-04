import AmoreJWT
import Crypto
import Foundation
import Testing

@testable import AmoreLicensing

/// Grace covers a license server the app cannot reach, not a license that has
/// ended. Each scenario stores a token that expired two days ago, inside the
/// default seven-day grace period, and differs only in how the license ends.
@MainActor
@Suite struct GracePeriodTests {
    struct Scenario: Sendable, CustomTestStringConvertible {
        let testDescription: String
        var subscriptionState: SubscriptionState? = nil
        let expiresAt: Date
        let keepsGrace: Bool
    }

    private let hardwareId = "TEST-SERIAL-123"
    private let bundleId = "com.test.amorekit"

    /// The server caps a token's expiry at the license end, so most scenarios
    /// share this date for both.
    private nonisolated static let tokenEnd = Date(timeIntervalSinceNow: -2 * 24 * 3600)
    private nonisolated static let canceledAt = tokenEnd.addingTimeInterval(-10 * 24 * 3600)

    nonisolated static let scenarios = [
        Scenario(
            testDescription: "license that has not ended",
            expiresAt: .now.addingTimeInterval(30 * 24 * 3600),
            keepsGrace: true
        ),
        Scenario(testDescription: "license that has ended", expiresAt: tokenEnd, keepsGrace: false),
        Scenario(
            testDescription: "renewing subscription",
            subscriptionState: .renewing(renewsAt: tokenEnd),
            expiresAt: tokenEnd,
            keepsGrace: true
        ),
        Scenario(
            testDescription: "trial that converts",
            subscriptionState: .trialing(trialEndsAt: tokenEnd, canceledAt: nil),
            expiresAt: tokenEnd,
            keepsGrace: true
        ),
        Scenario(
            testDescription: "canceled trial",
            subscriptionState: .trialing(trialEndsAt: tokenEnd, canceledAt: canceledAt),
            expiresAt: tokenEnd,
            keepsGrace: false
        ),
        Scenario(
            testDescription: "canceling subscription",
            subscriptionState: .canceling(endsAt: tokenEnd, canceledAt: canceledAt),
            expiresAt: tokenEnd,
            keepsGrace: false
        ),
    ]

    @Test(arguments: scenarios)
    func validateOffline(_ scenario: Scenario) async throws {
        let (store, publicKey) = try storeToken(for: scenario)
        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        let client = AmoreLicensing(
            publicKey: publicKey,
            bundleIdentifier: bundleId,
            tokenStore: store,
            deviceIdentity: MockDeviceIdentity(identifier: hardwareId),
            licenseClient: mock
        )

        let result = try await client.validate()

        #expect(result.isGracePeriod == scenario.keepsGrace)
        #expect(scenario.keepsGrace || result == .invalid)
    }

    /// The launch initializer reads the stored token synchronously. Without
    /// grace it stays `.unknown` and lets the server decide.
    @Test(arguments: scenarios)
    func launch(_ scenario: Scenario) throws {
        let (store, publicKey) = try storeToken(for: scenario)
        let unreachable = URL(string: "http://127.0.0.1:1")!

        let client = try AmoreLicensing(
            publicKey: publicKey.rawRepresentation.base64URLEncodedString(),
            bundleIdentifier: bundleId,
            server: LicenseServer(activateURL: unreachable, deactivateURL: unreachable, validateURL: unreachable),
            deviceIdentity: MockDeviceIdentity(identifier: hardwareId),
            tokenStore: store
        )

        #expect(client.status.isGracePeriod == scenario.keepsGrace)
        #expect(scenario.keepsGrace || client.status == .unknown)
    }

    private func storeToken(for scenario: Scenario) throws -> (MockTokenStore, Curve25519.Signing.PublicKey) {
        let privateKey = Curve25519.Signing.PrivateKey()
        let payload = LicensePayload(
            exp: Self.tokenEnd,
            hardwareId: hardwareId,
            iat: Date(),
            licenseId: UUID(),
            nonce: "stored",
            product: .testSample,
            subscriptionState: scenario.subscriptionState,
            expiresAt: scenario.expiresAt
        )
        let store = MockTokenStore()
        try store.store(EdDSAJWT.sign(payload, using: privateKey))
        return (store, privateKey.publicKey)
    }
}

private extension ValidationStatus {
    var isGracePeriod: Bool {
        if case .gracePeriod = self { true } else { false }
    }
}
