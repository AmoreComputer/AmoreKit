import Crypto
import Foundation
import Testing

@testable import AmoreLicensing

@MainActor
@Suite struct ClockRollbackTests {
    private let hardwareId = "TEST-SERIAL-123"
    private let privateKey = Curve25519.Signing.PrivateKey()
    // A bundle identifier per test keeps each test's record in user defaults apart.
    private let bundleId = "com.test.clock.\(UUID().uuidString)"

    private var clockKey: String { "AmoreLicensing.latestValidation.\(bundleId)" }

    private func token(nonce: String, issuedAt: Date = Date()) throws -> String {
        try signV2Token(
            privateKey: privateKey,
            hardwareId: hardwareId,
            nonce: nonce,
            exp: issuedAt.addingTimeInterval(30 * 86_400),
            iat: issuedAt
        )
    }

    private func makeClient(
        server: MockLicenseClient,
        storedIssuedAt: Date = Date()
    ) throws -> AmoreLicensing {
        let store = MockTokenStore()
        try store.store(token(nonce: "stored", issuedAt: storedIssuedAt))
        return AmoreLicensing(
            publicKey: privateKey.publicKey,
            bundleIdentifier: bundleId,
            tokenStore: store,
            deviceIdentity: MockDeviceIdentity(identifier: hardwareId),
            licenseClient: server
        )
    }

    /// Makes the system clock look a day behind the latest time seen.
    private func setClockBack() {
        UserDefaults.standard.set(Date().addingTimeInterval(86_400), forKey: clockKey)
    }

    @Test func recordsTheLatestTimeSeen() async throws {
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }
        let client = try makeClient(server: MockLicenseClient())
        let start = Date()

        try await client.validate()

        let recorded = try #require(UserDefaults.standard.object(forKey: clockKey) as? Date)
        #expect(recorded >= start)
    }

    @Test func clockSetBackAsksTheServerAndTrustsTheClockAgain() async throws {
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }
        let server = MockLicenseClient()
        var serverCalls = 0
        server.onValidate = { [self] _, nonce in
            serverCalls += 1
            return try token(nonce: nonce)
        }
        let client = try makeClient(server: server)
        setClockBack()

        let first = try await client.validate()
        let second = try await client.validate()

        #expect(first.isValid && second.isValid)
        #expect(serverCalls == 1)
    }

    @Test func clockSetBackInvalidatesWhenServerIsUnreachable() async throws {
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }
        let server = MockLicenseClient()
        server.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        let client = try makeClient(server: server)
        setClockBack()

        #expect(try await client.validate() == .invalid)
    }

    /// A server answer confirms the license, not the system clock: a token
    /// issued ahead of the clock keeps the clock distrusted.
    @Test func clockSetBackStaysDistrustedAfterTheServerAnswers() async throws {
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }
        let server = MockLicenseClient()
        var serverCalls = 0
        var online = true
        server.onValidate = { [self] _, nonce in
            serverCalls += 1
            guard online else { throw URLError(.notConnectedToInternet) }
            return try token(nonce: nonce, issuedAt: Date().addingTimeInterval(86_400))
        }
        let client = try makeClient(server: server)
        setClockBack()

        let first = try await client.validate()
        online = false
        let second = try await client.validate()

        #expect(first.isValid)
        #expect(second == .invalid)
        #expect(serverCalls == 2)
    }

    @Test func clockBehindTheTokenIssueTimeIsDetectedWithoutARecord() async throws {
        defer { UserDefaults.standard.removeObject(forKey: clockKey) }
        let server = MockLicenseClient()
        server.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        let client = try makeClient(server: server, storedIssuedAt: Date().addingTimeInterval(86_400))

        #expect(try await client.validate() == .invalid)
    }
}

private extension ValidationStatus {
    var isValid: Bool {
        if case .valid = self { true } else { false }
    }
}
