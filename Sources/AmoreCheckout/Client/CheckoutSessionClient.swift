import Foundation

typealias CheckoutTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Creates checkout sessions and reads their status from the licensing server.
protocol CheckoutSessionClient: Sendable {
    func createSession(productId: UUID, customerEmail: String?) async throws(CheckoutClientError) -> CheckoutSession
    func sessionStatus(sessionId: String) async throws(CheckoutClientError) -> CheckoutSessionStatusResponse
}

struct HTTPCheckoutSessionClient: CheckoutSessionClient {
    private let baseURL: URL
    private let bundleIdentifier: String
    private let transport: CheckoutTransport
    
    init(
        baseURL: URL,
        bundleIdentifier: String,
        transport: @escaping CheckoutTransport = { try await URLSession.shared.data(for: $0) }
    ) {
        self.baseURL = baseURL
        self.bundleIdentifier = bundleIdentifier
        self.transport = transport
    }
    
    func createSession(productId: UUID, customerEmail: String?) async throws(CheckoutClientError) -> CheckoutSession {
        struct Body: Encodable {
            let productId: UUID
            let customerEmail: String?
        }
        var request = URLRequest(url: sessionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONEncoder().encode(Body(productId: productId, customerEmail: customerEmail))
        } catch {
            throw .network("Could not encode request: \(error.localizedDescription)")
        }
        return try await perform(request)
    }
    
    func sessionStatus(sessionId: String) async throws(CheckoutClientError) -> CheckoutSessionStatusResponse {
        var request = URLRequest(url: sessionsURL.appendingPathComponent(sessionId))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }
    
    // MARK: - Private
    
    private var sessionsURL: URL {
        baseURL
            .appendingPathComponent("v1/public/apps")
            .appendingPathComponent(bundleIdentifier)
            .appendingPathComponent("checkout/sessions")
    }
    
    private func perform<Response: Decodable>(_ request: URLRequest) async throws(CheckoutClientError) -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw .network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .invalidResponse
        }
        switch http.statusCode {
        case 200...299:
            break
        case 429:
            throw .rateLimited
        default:
            throw .httpStatus(http.statusCode)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw .network("Could not decode response: \(error.localizedDescription)")
        }
    }
}
