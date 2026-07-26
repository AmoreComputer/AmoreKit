import Testing

@testable import AmoreLicensing

@Suite("DeviceIdentity.hashedIdentifier")
struct HashedIdentifierTests {
    private let identity = MockDeviceIdentity(identifier: "TEST-SERIAL-123")

    @Test func differsPerIdentifier() {
        let other = MockDeviceIdentity(identifier: "OTHER-SERIAL")
        #expect(identity.hashedIdentifier(salt: "com.test.a") != other.hashedIdentifier(salt: "com.test.a"))
    }

    @Test func differsPerSalt() {
        #expect(identity.hashedIdentifier(salt: "com.test.a") != identity.hashedIdentifier(salt: "com.test.b"))
    }

    /// Known-answer vector pinning the exact scheme (HMAC-SHA256, base64,
    /// `h1:` prefix). If this fails the wire format changed, which would orphan
    /// every activation made with the old scheme.
    @Test func matchesKnownVector() {
        #expect(
            identity.hashedIdentifier(salt: "com.test.a")
            == "h1:AideSWRk8IeW/FWbWvpzggwyKBJZwv8waJmcLKYiZII="
        )
    }
}
