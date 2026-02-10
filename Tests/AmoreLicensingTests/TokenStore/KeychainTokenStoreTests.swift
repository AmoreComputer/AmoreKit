import Testing

@testable import AmoreLicensing

@Suite(.serialized) struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(bundleIdentifier: "computer.amore.test.amorekit.keychain")

    init() throws {
        try? store.delete()
    }

    @Test func storeAndRetrieve() throws {
        try store.store("test-token-123")
        let retrieved = try store.retrieve()
        #expect(retrieved == "test-token-123")
        try? store.delete()
    }

    @Test func retrieveWhenEmpty() throws {
        let retrieved = try store.retrieve()
        #expect(retrieved == nil)
    }

    @Test func delete() throws {
        try store.store("token")
        try store.delete()
        let retrieved = try store.retrieve()
        #expect(retrieved == nil)
    }

    @Test func overwrite() throws {
        try store.store("first")
        try store.store("second")
        let retrieved = try store.retrieve()
        #expect(retrieved == "second")
        try? store.delete()
    }
}
