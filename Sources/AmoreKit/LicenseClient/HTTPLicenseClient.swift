import Foundation

struct HTTPLicenseClient: LicenseClient {
    private let server: LicenseServer

    init(server: LicenseServer) {
        self.server = server
    }

    func activate(licenseKey: String, hardwareId: String, nonce: String) async throws -> String {
        let body = ActivateRequest(licenseKey: licenseKey, hardwareId: hardwareId, nonce: nonce)
        return try await post(path: server.activatePath, body: body)
    }

    func validate(token: String, nonce: String) async throws -> String {
        let body = ValidateRequest(token: token, nonce: nonce)
        return try await post(path: server.validatePath, body: body)
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> String {
        var request = URLRequest(url: server.url.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AmoreError.activationFailed("Server returned error")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }
}

private struct ActivateRequest: Encodable {
    let licenseKey: String
    let hardwareId: String
    let nonce: String
}

private struct ValidateRequest: Encodable {
    let token: String
    let nonce: String
}

private struct TokenResponse: Decodable {
    let token: String
}
