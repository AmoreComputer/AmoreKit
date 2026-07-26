import Foundation
import Testing

@testable import AmoreCheckout

@Suite struct PendingCheckoutStoreTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingCheckoutStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingCheckoutStore(directory: directory)
        let pending = PendingCheckout(
            sessionId: "cs_1",
            productId: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_752_000_000)
        )

        try store.save(pending)

        #expect(store.load() == pending)
    }

    @Test func loadReturnsNilWhenNothingStored() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingCheckoutStore(directory: directory)

        #expect(store.load() == nil)
    }

    @Test func loadReturnsNilForCorruptFile() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingCheckoutStore(directory: directory)
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent(PendingCheckoutStore.fileName)
        )

        #expect(store.load() == nil)
    }

    @Test func clearRemovesTheStoredCheckout() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingCheckoutStore(directory: directory)
        try store.save(PendingCheckout(sessionId: "cs_1", productId: UUID(), createdAt: .now))

        store.clear()

        #expect(store.load() == nil)
    }

    @Test func clearIsIdempotent() throws {
        let directory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PendingCheckoutStore(directory: directory)

        store.clear()
        store.clear()

        #expect(store.load() == nil)
    }
}
