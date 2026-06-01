import Foundation

@testable import AmoreStore

final class MockProductsClient: ProductsClient, @unchecked Sendable {
    var onFetch: ((String) async throws -> [Product])?

    func fetchProducts(bundleIdentifier: String) async throws -> [Product] {
        guard let handler = onFetch else { return [] }
        return try await handler(bundleIdentifier)
    }
}
