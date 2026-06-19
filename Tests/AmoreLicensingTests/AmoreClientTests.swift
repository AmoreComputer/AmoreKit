import Foundation
import JWTKit
import Testing

@testable import AmoreLicensing

@MainActor
@Suite struct AmoreClientTests {
    private let hardwareId = "TEST-SERIAL-123"
    private let bundleId = "com.test.amorekit"

    private func makeKeys() throws -> (EdDSA.PrivateKey, EdDSA.PublicKey) {
        let privateKey = try EdDSA.PrivateKey(curve: .ed25519)
        return (privateKey, privateKey.publicKey)
    }

    private func signToken(
        privateKey: EdDSA.PrivateKey,
        hardwareId: String,
        nonce: String,
        exp: Date = Date().addingTimeInterval(30 * 24 * 3600),
        licenseId: UUID = UUID(),
        product: Product = .testSample
    ) async throws -> String {
        let payload = LicensePayload(
            exp: .init(value: exp),
            hardwareId: hardwareId,
            iat: .init(value: Date()),
            licenseId: licenseId,
            nonce: nonce,
            product: product
        )
        let keys = await JWTKeyCollection().add(eddsa: privateKey)
        return try await keys.sign(payload)
    }

    private func makeClient(
        publicKey: EdDSA.PublicKey,
        tokenStore: MockTokenStore = MockTokenStore(),
        licenseClient: MockLicenseClient = MockLicenseClient()
    ) -> (AmoreLicensing, MockTokenStore, MockLicenseClient) {
        let client = AmoreLicensing(
            publicKey: publicKey,
            bundleIdentifier: bundleId,
            tokenStore: tokenStore,
            deviceIdentity: MockDeviceIdentity(identifier: hardwareId),
            licenseClient: licenseClient
        )
        return (client, tokenStore, licenseClient)
    }

    // MARK: - Activation

    @Test func activationHardwareIdMismatch() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { _, _, nonce in
            try await self.signToken(privateKey: privateKey, hardwareId: "OTHER-HW", nonce: nonce)
        }
        let (client, _, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        await #expect(throws: AmoreError.hardwareIdMismatch) {
            try await client.activate(licenseKey: "KEY")
        }
    }

    @Test func activationInvalidSignature() async throws {
        let (_, publicKey) = try makeKeys()
        let (wrongPrivate, _) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { [self] _, hwId, nonce in
            try await signToken(privateKey: wrongPrivate, hardwareId: hwId, nonce: nonce)
        }
        let (client, _, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        await #expect(throws: AmoreError.invalidSignature) {
            try await client.activate(licenseKey: "KEY")
        }
    }

    @Test func activationRateLimited() async throws {
        let (_, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { _, _, _ in throw NetworkError.rateLimited }
        let (client, _, _) = makeClient(publicKey: publicKey, licenseClient: mock)
        
        await #expect(throws: AmoreError.network(.rateLimited)) {
            try await client.activate(licenseKey: "KEY")
        }
    }

    @Test func activationNetworkFailure() async throws {
        let (_, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { _, _, _ in throw URLError(.notConnectedToInternet) }
        let (client, _, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        await #expect(throws: AmoreError.self) {
            try await client.activate(licenseKey: "KEY")
        }
    }

    @Test func activationNonceMismatch() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { [self] _, hwId, _ in
            try await signToken(privateKey: privateKey, hardwareId: hwId, nonce: "wrong-nonce")
        }
        let (client, _, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        await #expect(throws: AmoreError.nonceMismatch) {
            try await client.activate(licenseKey: "KEY")
        }
    }

    @Test func activationSuccess() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { [self] _, hwId, nonce in
            try await signToken(privateKey: privateKey, hardwareId: hwId, nonce: nonce)
        }
        let (client, store, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        try await client.activate(licenseKey: "VALID-KEY")

        guard case .valid = client.status else {
            Issue.record("Expected valid, got \(client.status)")
            return
        }
        #expect(try store.retrieve() != nil)
    }

    // MARK: - Deactivation

    @Test func deactivationSuccess() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        var serverCalled = false
        mock.onActivate = { [self] _, hwId, nonce in
            try await signToken(privateKey: privateKey, hardwareId: hwId, nonce: nonce)
        }
        mock.onDeactivate = { _ in serverCalled = true }
        let (client, store, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        try await client.activate(licenseKey: "KEY")
        try await client.deactivate()

        #expect(client.status == .unknown)
        #expect(try store.retrieve() == nil)
        #expect(serverCalled)
    }

    @Test func deactivationNoStoredToken() async throws {
        let (_, publicKey) = try makeKeys()
        let (client, _, _) = makeClient(publicKey: publicKey)

        await #expect(throws: AmoreError.noStoredToken) {
            try await client.deactivate()
        }
    }

    @Test func deactivationNetworkFailure() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        mock.onActivate = { [self] _, hwId, nonce in
            try await signToken(privateKey: privateKey, hardwareId: hwId, nonce: nonce)
        }
        mock.onDeactivate = { _ in throw URLError(.notConnectedToInternet) }
        let (client, store, _) = makeClient(publicKey: publicKey, licenseClient: mock)

        try await client.activate(licenseKey: "KEY")
        let tokenBefore = try store.retrieve()

        await #expect(throws: AmoreError.self) {
            try await client.deactivate()
        }
        #expect(try store.retrieve() == tokenBefore)
        guard case .valid = client.status else {
            Issue.record("Expected status to remain valid, got \(client.status)")
            return
        }
    }

    // MARK: - Validation

    @Test func validateExpiredTokenGracePeriod() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let expDate = Date().addingTimeInterval(-2 * 24 * 3600) // expired 2 days ago
        let expired = try await signToken(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "old",
            exp: expDate
        )
        try store.store(expired)

        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        let (client, _, _) = makeClient(publicKey: publicKey, tokenStore: store, licenseClient: mock)

        let result = try await client.validate()

        guard case .gracePeriod(let license) = result else {
            Issue.record("Expected gracePeriod, got \(result)")
            return
        }
        let expectedEnd = expDate.addingTimeInterval(7 * 86_400)
        #expect(abs(license.expiresAt!.timeIntervalSince(expectedEnd)) < 1)
    }

    @Test func validateExpiredTokenValidates() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let expired = try await signToken(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "old",
            exp: Date().addingTimeInterval(-100)
        )
        try store.store(expired)

        let mock = MockLicenseClient()
        mock.onValidate = { [self] _, nonce in
            try await signToken(privateKey: privateKey, hardwareId: hardwareId, nonce: nonce)
        }
        let (client, _, _) = makeClient(publicKey: publicKey, tokenStore: store, licenseClient: mock)

        let result = try await client.validate()

        guard case .valid = result, case .valid = client.status else {
            Issue.record("Expected valid, got \(result)")
            return
        }
    }

    @Test func validateGracePeriodExpired() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let expired = try await signToken(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "old",
            exp: Date().addingTimeInterval(-10 * 24 * 3600) // expired 10 days ago
        )
        try store.store(expired)

        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        let (client, _, _) = makeClient(publicKey: publicKey, tokenStore: store, licenseClient: mock)

        let result = try await client.validate()

        #expect(result == .invalid)
        #expect(client.status == .invalid)
    }

    @Test func validateHardwareIdMismatchOnStoredToken() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, hardwareId: "OTHER-HW", nonce: "n")
        try store.store(token)
        let (client, _, _) = makeClient(publicKey: publicKey, tokenStore: store)

        await #expect(throws: AmoreError.hardwareIdMismatch) {
            try await client.validate()
        }
        #expect(client.status == .invalid)
    }

    @Test func validateNoStoredToken() async throws {
        let (_, publicKey) = try makeKeys()
        let (client, _, _) = makeClient(publicKey: publicKey)

        await #expect(throws: AmoreError.noStoredToken) {
            try await client.validate()
        }
    }

    @Test func validateValidStoredToken() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, hardwareId: hardwareId, nonce: "stored")
        try store.store(token)
        let (client, _, _) = makeClient(publicKey: publicKey, tokenStore: store)

        let result = try await client.validate()

        guard case .valid = result, case .valid = client.status else {
            Issue.record("Expected valid, got \(result)")
            return
        }
    }
}
