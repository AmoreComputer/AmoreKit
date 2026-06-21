import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct HTTPLicenseClient: LicenseClient {
    private let server: LicenseServer
    
    init(server: LicenseServer) {
        self.server = server
    }
    
    func activate(licenseKey: String, hardwareId: String, nonce: String, name: String?) async throws -> String {
        let body = ActivateRequest(licenseKey: licenseKey, hardwareId: hardwareId, nonce: nonce, name: name)
        return try await post(body, to: server.activateURL)
    }
    
    func deactivate(token: String) async throws {
        let body = DeactivateRequest(token: token)
        try await postVoid(body, to: server.deactivateURL)
    }
    
    func validate(token: String, nonce: String) async throws -> String {
        let body = ValidateRequest(token: token, nonce: nonce)
        return try await post(body, to: server.validateURL)
    }
    
    private func post<T: Encodable>(_ body: T, to url: URL) async throws -> String {
        let (data, response) = try await send(body, to: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw serverError(from: data, response: response)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }
    
    private func postVoid<T: Encodable>(_ body: T, to url: URL) async throws {
        let (data, response) = try await send(body, to: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw serverError(from: data, response: response)
        }
    }

    private func serverError(from data: Data, response: URLResponse) -> any Error {
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            return NetworkError.rateLimited
        }
        guard let body = try? JSONDecoder().decode(ErrorResponse.self, from: data) else {
            return NetworkError.requestFailed("An unknown error occurred")
        }
        if let clientError = ClientError(rawValue: body.error) {
            return clientError
        }
        return NetworkError.requestFailed(body.message)
    }
    
    private func send<T: Encodable>(_ body: T, to url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await URLSession.shared.data(for: request)
    }
}

private struct ActivateRequest: Encodable {
    let licenseKey: String
    let hardwareId: String
    let nonce: String
    let name: String?
}

private struct DeactivateRequest: Encodable {
    let token: String
}

private struct ValidateRequest: Encodable {
    let token: String
    let nonce: String
}

private struct TokenResponse: Decodable {
    let token: String
}

private struct ErrorResponse: Decodable {
    let error: String
    let message: String
}
