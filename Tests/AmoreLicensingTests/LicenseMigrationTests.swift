import Crypto
import Foundation
import Testing

@testable import AmoreLicensing

@MainActor
@Suite struct LicenseMigrationTests {
    private let hardwareId = "TEST-SERIAL-123"
    private let bundleId = "com.test.amorekit"
    
    private func makeKeys() -> (Curve25519.Signing.PrivateKey, Curve25519.Signing.PublicKey) {
        let privateKey = Curve25519.Signing.PrivateKey()
        return (privateKey, privateKey.publicKey)
    }
    
    private func makeClient(
        publicKey: Curve25519.Signing.PublicKey,
        tokenStore: MockTokenStore = MockTokenStore(),
        licenseClient: MockLicenseClient = MockLicenseClient()
    ) -> AmoreLicensing {
        AmoreLicensing(
            publicKey: publicKey,
            bundleIdentifier: bundleId,
            tokenStore: tokenStore,
            deviceIdentity: MockDeviceIdentity(identifier: hardwareId),
            licenseClient: licenseClient
        )
    }
    
    @Test func licenseNameReturnsProductName() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let token = try signV2Token(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "n", product: .testSample
        )
        try store.store(token)
        let client = makeClient(publicKey: publicKey, tokenStore: store)
        
        let result = try await client.validate()
        
        guard case .valid(let license) = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        #expect(license.name == license.product.name)
        #expect(license.name == "Amore")
        #expect(license.product.identifier == "pro")
    }
    
    @Test func v1CachedTokenUpgradesToV2Online() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let v1 = try signV1Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "old")
        try store.store(v1)
        
        let mock = MockLicenseClient()
        var validateCalled = false
        mock.onValidate = { _, nonce in
            validateCalled = true
            return try signV2Token(privateKey: privateKey, hardwareId: self.hardwareId, nonce: nonce)
        }
        let client = makeClient(publicKey: publicKey, tokenStore: store, licenseClient: mock)
        
        let result = try await client.validate()
        
        guard case .valid(let license) = result else {
            Issue.record("Expected valid after upgrade, got \(result)")
            return
        }
        #expect(validateCalled, "expected the SDK to refresh against the server, not throw .invalid")
        #expect(license.product.id == Product.testSample.id)
        #expect(license.product.name == Product.testSample.name)
        #expect(license.product.identifier == Product.testSample.identifier)
    }
    
    @Test func v1CachedTokenOfflineDegradesThenRecovers() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let v1 = try signV1Token(privateKey: privateKey, hardwareId: hardwareId, nonce: "old")
        try store.store(v1)
        
        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in throw URLError(.notConnectedToInternet) }
        let client = makeClient(publicKey: publicKey, tokenStore: store, licenseClient: mock)
        
        // Offline: local decode of the v1 token fails (object product), refresh
        // fails (network), grace decode of the v1 token also fails → .invalid.
        let offline = try await client.validate()
        #expect(offline == .invalid)
        
        // Server reachable again, returns a v2 token → self-heals.
        mock.onValidate = { _, nonce in
            try signV2Token(privateKey: privateKey, hardwareId: self.hardwareId, nonce: nonce)
        }
        let recovered = try await client.validate()
        guard case .valid = recovered else {
            Issue.record("Expected valid after recovery, got \(recovered)")
            return
        }
    }
    
    @Test func v2CachedTokenValidatesWithoutCallingServer() async throws {
        let (privateKey, publicKey) = makeKeys()
        let store = MockTokenStore()
        let v2 = try signV2Token(
            privateKey: privateKey, hardwareId: hardwareId, nonce: "stored", iat: Date()
        )
        try store.store(v2)
        
        let mock = MockLicenseClient()
        mock.onValidate = { _, _ in
            Issue.record("validate() must not call the server for a fresh v2 token")
            throw URLError(.badServerResponse)
        }
        let client = makeClient(publicKey: publicKey, tokenStore: store, licenseClient: mock)
        
        let result = try await client.validate()
        
        guard case .valid(let license) = result else {
            Issue.record("Expected valid, got \(result)")
            return
        }
        #expect(license.product.identifier == Product.testSample.identifier)
    }
}
