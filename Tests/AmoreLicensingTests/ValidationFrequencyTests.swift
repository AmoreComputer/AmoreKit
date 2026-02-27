import Foundation
import JWTKit
import Testing

@testable import AmoreLicensing

@MainActor
@Suite struct ValidationFrequencyTests {
    private let hardwareId = "TEST-SERIAL-123"
    private let bundleId = "com.test.amorekit"
    
    private func makeKeys() throws -> (EdDSA.PrivateKey, EdDSA.PublicKey) {
        let privateKey = try EdDSA.PrivateKey(curve: .ed25519)
        return (privateKey, privateKey.publicKey)
    }
    
    private func signToken(
        privateKey: EdDSA.PrivateKey,
        nonce: String,
        iat: Date = Date(),
        exp: Date = Date().addingTimeInterval(30 * 24 * 3600)
    ) async throws -> String {
        let payload = LicensePayload(
            exp: .init(value: exp),
            hardwareId: hardwareId,
            iat: .init(value: iat),
            licenseId: UUID(),
            nonce: nonce
        )
        let keys = await JWTKeyCollection().add(eddsa: privateKey)
        return try await keys.sign(payload)
    }
    
    private func makeClient(
        publicKey: EdDSA.PublicKey,
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
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, nonce: "stored")
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
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        // Token issued 2 days ago — daily check should trigger
        let token = try await signToken(
            privateKey: privateKey, nonce: "old",
            iat: Date().addingTimeInterval(-2 * 86_400)
        )
        try store.store(token)
        
        let mock = MockLicenseClient()
        mock.onValidate = { [self] _, nonce in
            try await signToken(privateKey: privateKey, nonce: nonce)
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
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        // Token issued 1 hour ago — daily check should NOT trigger
        let token = try await signToken(
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
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(
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
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(
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
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, nonce: "fresh")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var serverCalled = false
        mock.onValidate = { [self] _, nonce in
            serverCalled = true
            return try await signToken(privateKey: privateKey, nonce: nonce)
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
    
    // MARK: - Auto-validate scheduling
    
    @Test func autoValidateSchedulesAfterActivation() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        var validateCallCount = 0
        
        mock.onActivate = { [self] _, hwId, nonce in
            try await signToken(privateKey: privateKey, nonce: nonce)
        }
        mock.onValidate = { [self] _, nonce in
            validateCallCount += 1
            return try await signToken(privateKey: privateKey, nonce: nonce)
        }
        
        let config = LicensingConfiguration(validationFrequency: .seconds(0.05))
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            licenseClient: mock
        )
        
        // Before activation — no periodic checks should happen
        try await Task.sleep(for: .seconds(0.15))
        #expect(validateCallCount == 0)
        
        // Activate — this should start the periodic task
        try await client.activate(licenseKey: "KEY")
        try await Task.sleep(for: .seconds(0.3))
        
        guard case .valid = client.status else {
            Issue.record("Expected valid, got \(client.status)")
            return
        }
        #expect(validateCallCount >= 2)
    }
    
    @Test func autoValidateSchedulesAfterValidate() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var validateCallCount = 0
        mock.onValidate = { [self] _, nonce in
            validateCallCount += 1
            return try await signToken(privateKey: privateKey, nonce: nonce)
        }
        
        let config = LicensingConfiguration(validationFrequency: .seconds(0.05))
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        // Trigger validate with a stored token — should start periodic task
        try await client.validate()
        try await Task.sleep(for: .seconds(0.3))
        
        guard case .valid = client.status else {
            Issue.record("Expected valid, got \(client.status)")
            return
        }
        #expect(validateCallCount >= 2)
    }
    
    @Test func autoValidateNoScheduleForAfterExpiration() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var callCount = 0
        mock.onValidate = { _, _ in
            callCount += 1
            throw URLError(.notConnectedToInternet)
        }
        
        let config = LicensingConfiguration(validationFrequency: .afterExpiration)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        // Trigger validate to attempt auto-validation start
        try await client.validate()
        try await Task.sleep(for: .seconds(0.2))
        
        guard case .valid = client.status else {
            Issue.record("Expected valid, got \(client.status)")
            return
        }
        #expect(callCount == 0)
    }
    
    @Test func autoValidateStopsOnServerRejection() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var validateCallCount = 0
        mock.onValidate = { [self] _, nonce in
            validateCallCount += 1
            if validateCallCount >= 3 {
                throw ClientError.licenseExpired
            }
            return try await signToken(privateKey: privateKey, nonce: nonce)
        }
        
        let config = LicensingConfiguration(validationFrequency: .seconds(0.05))
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        // Start periodic validation
        try await client.validate()
        // Wait for rejection to happen
        try await Task.sleep(for: .seconds(0.5))
        
        #expect(client.status == .invalid)
        // Record count after rejection, wait more, verify no additional calls
        let countAfterRejection = validateCallCount
        try await Task.sleep(for: .seconds(0.2))
        #expect(validateCallCount == countAfterRejection)
    }
    
    @Test func manualFrequencyDoesNotAutoValidate() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let store = MockTokenStore()
        let token = try await signToken(privateKey: privateKey, nonce: "stored")
        try store.store(token)
        
        let mock = MockLicenseClient()
        var callCount = 0
        mock.onValidate = { _, _ in
            callCount += 1
            throw URLError(.notConnectedToInternet)
        }
        
        let config = LicensingConfiguration(validationFrequency: .manual)
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            tokenStore: store,
            licenseClient: mock
        )
        
        try await client.validate()
        try await Task.sleep(for: .seconds(0.2))
        
        guard case .valid = client.status else {
            Issue.record("Expected valid, got \(client.status)")
            return
        }
        #expect(callCount == 0)
    }
    
    @Test func autoValidateStopsOnDeactivation() async throws {
        let (privateKey, publicKey) = try makeKeys()
        let mock = MockLicenseClient()
        var validateCallCount = 0
        
        mock.onActivate = { [self] _, hwId, nonce in
            try await signToken(privateKey: privateKey, nonce: nonce)
        }
        mock.onDeactivate = { _ in }
        mock.onValidate = { [self] _, nonce in
            validateCallCount += 1
            return try await signToken(privateKey: privateKey, nonce: nonce)
        }
        
        let config = LicensingConfiguration(validationFrequency: .seconds(0.05))
        let (client, _, _) = makeClient(
            publicKey: publicKey,
            configuration: config,
            licenseClient: mock
        )
        
        try await client.activate(licenseKey: "KEY")
        try await Task.sleep(for: .seconds(0.2))
        #expect(validateCallCount >= 1)
        
        // Deactivate — task should stop
        try await client.deactivate()
        let countAfterDeactivation = validateCallCount
        try await Task.sleep(for: .seconds(0.2))
        #expect(validateCallCount == countAfterDeactivation)
        #expect(client.status == .unknown)
    }
}
