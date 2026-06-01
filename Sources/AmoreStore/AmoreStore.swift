import Foundation

extension URL {
    /// Default Amore licensing server. Internal to `AmoreStore` so it does not
    /// collide with the public `URL.amoreServer` declared in `AmoreLicensing`.
    static let amoreServer = URL(string: "https://api.amore.computer")!
}

/// Lists the products configured for an Amore-licensed app.
///
/// Fetch products with ``products()``, then read ``Product/checkoutURL`` on a
/// returned product to send a customer to Stripe checkout. Use this to build
/// paywalls, pickers, or any view that displays the products and prices
/// configured in the licensing dashboard.
public struct AmoreStore: Sendable {
    private let bundleIdentifier: String
    private let productsClient: ProductsClient

    /// Creates a store client for the given bundle identifier, targeting the Amore server.
    /// - Parameter bundleIdentifier: The app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier`.
    public init(bundleIdentifier: String? = nil) {
        self.init(bundleIdentifier: bundleIdentifier, baseURL: .amoreServer)
    }
    
    /// Creates a store client for the given bundle identifier and server URL.
    /// - Parameters:
    ///   - bundleIdentifier: The app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier`.
    ///   - baseURL: The licensing server base URL.
    public init(bundleIdentifier: String? = nil, baseURL: URL) {
        self.bundleIdentifier = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? ""
        self.productsClient = HTTPProductsClient(baseURL: baseURL)
    }

    init(bundleIdentifier: String, productsClient: ProductsClient) {
        self.bundleIdentifier = bundleIdentifier
        self.productsClient = productsClient
    }

    /// Returns the products configured for this app. Purchasable products carry a
    /// non-`nil` ``Product/checkoutURL``.
    /// - Throws: ``StoreError`` if the request fails.
    public func products() async throws(StoreError) -> [Product] {
        do {
            return try await productsClient.fetchProducts(bundleIdentifier: bundleIdentifier)
        } catch let error as StoreError {
            throw error
        } catch {
            throw .network(error.localizedDescription)
        }
    }
}
