import Foundation

/// A checkout session that was started but not yet resolved, persisted so a
/// purchase survives the app quitting mid-checkout. Embeds the full server
/// session so an interrupted checkout can be reopened at its original URL
/// and judged against its real expiry.
struct PendingCheckout: Codable, Equatable, Sendable {
    var session: CheckoutSession
    var productId: UUID
    var createdAt: Date
    
    var sessionId: String { session.sessionId }
}

/// Persists the pending checkout as a JSON file in Application Support, using
/// the same per-bundle-identifier directory scheme as `FileTokenStore`.
struct PendingCheckoutStore: Sendable {
    static let fileName = "pending-checkout.json"
    
    private let fileURL: URL
    
    init(bundleIdentifier: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = appSupport
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent(Self.fileName)
    }
    
    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }
    
    func save(_ pending: PendingCheckout) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(pending).write(to: fileURL, options: .atomic)
    }
    
    func load() -> PendingCheckout? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PendingCheckout.self, from: data)
    }
    
    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
