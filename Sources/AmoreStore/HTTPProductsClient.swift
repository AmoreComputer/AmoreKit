import Foundation

struct HTTPProductsClient: ProductsClient {
    private let baseURL: URL
    
    init(baseURL: URL) {
        self.baseURL = baseURL
    }
    
    func fetchProducts(bundleIdentifier: String) async throws -> [Product] {
        let url = baseURL
            .appendingPathComponent("v1/public/apps")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("products")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw StoreError.network(error.localizedDescription)
        }
        
        guard let http = response as? HTTPURLResponse else {
            throw StoreError.network("Invalid response from server")
        }
        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode([Product].self, from: data)
            } catch {
                throw StoreError.network("Could not decode product list: \(error.localizedDescription)")
            }
        case 404:
            throw StoreError.appNotFound
        case 429:
            throw StoreError.rateLimited
        default:
            throw StoreError.serverError(statusCode: http.statusCode)
        }
    }
}
