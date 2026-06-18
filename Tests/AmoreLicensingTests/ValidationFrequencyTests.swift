import AmoreJWT
import Crypto
import Foundation
import Testing

@testable import AmoreLicensing

@MainActor
@Suite struct ValidationFrequencyTests {
    private let hardwareId = "TEST-SERIAL-123"
    private let bundleId = "com.test.amorekit"
    
    private func makeKeys() -> (Curve25519.Signing.PrivateKey, Curve25519.Signing.PublicKey) {
        let privateKey = Curve25519.Signing.PrivateKey()
        return (privateKey, privateKey.publicKey)
    }
    
    private func signToken(
        privateKey: Curve25519.Signing.PrivateKey,
        nonce: String,
        iat: Date = Date(),
        exp: Date = Date().addingTimeInterval(30 * 24 * 3600)
    ) throws -> String {
        let payload = LicensePayload(
            exp: exp,
            hardwareId: hardwareId,
            iat: iat,
            licenseId: UUID(),
            nonce: nonce,
            product: .testSample
        )
        return try EdDSAJWT.sign(payload, using: privateKey)
    }
    
    private func makeClient(
        publicKey: Curve25519.Signing.PublicKey,
        configuration: LicensingConfiguration,
        tokenStore: MockTokenStore = MockTokenStore(),
        licenseClient: MockLicenseClient = MockLicenseClient()
    ) -> (AmoreLicensing, MockTokenStore, MockLicenseClient) {
        let client = AmoreLicensing(
            publicKey: publicKey,
            bundleIdentifier: bundleId,
            configuration: configuration,
            tokenStore: tokenStore,
            hardwareIdentifier: MockHardwareIdentifier(identifier: hardwareId),
            licenseClient: licenseClient
        )
        return (client, tokenStore, licenseClient)
    }
    
    // MARK: - afterExpiration (default behavior)
    
    @Test func validTokenSkipsServerWhenAfterExpiration() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var serverCalled = false
        mock.onValidate = { _, _ in
            serverCalled = true
            throw URLError(.notConnectedToInternet)
        }
        
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: .default,
            tokenStore: store,
            licenseClient: mock
        )
        
        let result = try await client.validate()
        
        guard case .valid = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        #expect(!serverCalled)
    }
    
    // MARK: - Proactive refresh
    
    @Test func validTokenContactsServerWhenIntervalElapsed() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        // Token issued 2 days ago — daily check should trigger
        let token = try signToken(
            privateKey: privateKey, nonce: "old",
            iat: Date().addingTimeInterval(-2 * 86_400)
        )
        try store.store(token)
        
        let mock = MockLicenseClient()
        mock.onValidate = { [self] _, nonce in
            try signToken(privateKey: privateKey, nonce: nonce)
        }
        
        let config = LicensingConfiguration(validationFrequency: .daily)
        let (client, refreshedStore, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        let result = try await client.validate()
        
        guard case .valid = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        let newToken = try refreshedStore.retrieve()
        #expect(newToken != token)
    }
    
    @Test func validTokenSkipsServerWhenIntervalNotElapsed() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        // Token issued 1 hour ago — daily check should NOT trigger
        let token = try signToken(
            privateKey: privateKey, nonce: "fresh",
            iat: Date().addingTimeInterval(-3600)
        )
        try store.store(token)
        
        let mock = MockLicenseClient()
        var serverCalled = false
        mock.onValidate = { _, _ in
            serverCalled = true
            throw URLError(.notConnectedToInternet)
        }
        
        let config = LicensingConfiguration(validationFrequency: .daily)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        let result = try await client.validate()
        
        guard case .valid = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        #expect(!serverCalled)
    }
    
    @Test func proactiveCheckNetworkFailureKeepsValid() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signToken(
            privateKey: privateKey, nonce: "stored",
            iat: Date().addingTimeInterval(-2 * 86_400)
        )
        try store.store(token)
        
        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        
        let config = LicensingConfiguration(validationFrequency: .daily)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        let result = try await client.validate()
        
        guard case .valid = result else {
            Issue.record("Expected valid (network failure should not invalidate), got \(result)")
            return
        }
    }
    
    @Test func proactiveCheckServerRejectionSetsInvalid() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signToken(
            privateKey: privateKey, nonce: "stored",
            iat: Date().addingTimeInterval(-2 * 86_400)
        )
        try store.store(token)
        
        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in throw ClientError.licenseExpired }
        
        let config = LicensingConfiguration(validationFrequency: .daily)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        await #expect(throws: AmoreError.self) {
            try await client.validate()
        }
        #expect(client.status == .invalid)
    }
    
    @Test func everyLaunchAlwaysContactsServer() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signToken(privateKey: privateKey, nonce: "fresh")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var serverCalled = false
        mock.onValidate = { [self] _, nonce in
            serverCalled = true
            return try signToken(privateKey: privateKey, nonce: nonce)
        }
        
        let config = LicensingConfiguration(validationFrequency: .everyLaunch)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        let result = try await client.validate()
        
        guard case .valid = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        #expect(serverCalled)
    }
    
    // MARK: - Consumer-driven lifecycle
    
    @Test func manualFrequencyDoesNotRefresh() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var serverCalled = false
        mock.onValidate = { _, _ in
            serverCalled = true
            throw URLError(.notConnectedToInternet)
        }
        
        let config = LicensingConfiguration(validationFrequency: .manual)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        let result = try await client.validate()
        
        guard case .valid = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        #expect(!serverCalled)
    }
    
    @Test func deactivateResetsStatusToUnknown() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        mock.onDeactivate = { _ in }
        
        // .manual ⇒ no launch validation, so every status change is driven explicitly here.
        let config = LicensingConfiguration(validationFrequency: .manual)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        try await client.validate()
        guard case .valid = client.status else {
            Issue.record("Expected valid before deactivation, got \(client.status)")
            return
        }
        
        try await client.deactivate()
        #expect(client.status == .unknown)
    }
}

/// Pure, timing-free coverage of the staleness policy that drives ``AmoreLicensing/validate()``.
@Suite struct ValidationFrequencyPolicyTests {
    private func daysAgo(_ days: Double) -> Date {
        Date().addingTimeInterval(-days * 86_400)
    }
    
    @Test func manualNeverRefreshes() {
        #expect(!ValidationFrequency.manual.isRefreshDue(issuedAt: daysAgo(365)))
    }
    
    @Test func afterExpirationNeverRefreshesProactively() {
        #expect(!ValidationFrequency.afterExpiration.isRefreshDue(issuedAt: daysAgo(365)))
    }
    
    @Test func everyLaunchAlwaysRefreshes() {
        #expect(ValidationFrequency.everyLaunch.isRefreshDue(issuedAt: Date()))
    }
    
    @Test func dailyRefreshesOnlyAfterADay() {
        #expect(ValidationFrequency.daily.isRefreshDue(issuedAt: daysAgo(2)))
        #expect(!ValidationFrequency.daily.isRefreshDue(issuedAt: daysAgo(0.5)))
    }
    
    @Test func weeklyRefreshesOnlyAfterAWeek() {
        #expect(ValidationFrequency.weekly.isRefreshDue(issuedAt: daysAgo(8)))
        #expect(!ValidationFrequency.weekly.isRefreshDue(issuedAt: daysAgo(3)))
    }
    
    @Test func monthlyRefreshesOnlyAfterAMonth() {
        #expect(ValidationFrequency.monthly.isRefreshDue(issuedAt: daysAgo(31)))
        #expect(!ValidationFrequency.monthly.isRefreshDue(issuedAt: daysAgo(15)))
    }
    
    @Test func secondsRefreshesAfterCustomInterval() {
        #expect(ValidationFrequency.seconds(60).isRefreshDue(issuedAt: Date().addingTimeInterval(-120)))
        #expect(!ValidationFrequency.seconds(60).isRefreshDue(issuedAt: Date().addingTimeInterval(-10)))
    }
    
    @Test func shouldValidateAtLaunchForEveryFrequencyExceptManual() {
        #expect(ValidationFrequency.weekly.shouldValidateAtLaunch)
        #expect(ValidationFrequency.daily.shouldValidateAtLaunch)
        #expect(ValidationFrequency.monthly.shouldValidateAtLaunch)
        #expect(ValidationFrequency.everyLaunch.shouldValidateAtLaunch)
        #expect(ValidationFrequency.afterExpiration.shouldValidateAtLaunch)
        #expect(ValidationFrequency.seconds(1).shouldValidateAtLaunch)
        #expect(!ValidationFrequency.manual.shouldValidateAtLaunch)
    }
}
