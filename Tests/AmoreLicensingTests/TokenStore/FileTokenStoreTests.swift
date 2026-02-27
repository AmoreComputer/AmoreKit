import Foundation
import Testing

@testable import AmoreLicensing

@Suite(.serialized) final class FileTokenStoreTests {
    private let store: FileTokenStore
    private let tempDir: URL

    init() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = FileTokenStore(directory: tempDir)
        try? store.delete()
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir)
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
