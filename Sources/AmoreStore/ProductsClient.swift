import Foundation

protocol ProductsClient: Sendable {
    func fetchProducts(bundleIdentifier: String) async throws -> [Product]
}
