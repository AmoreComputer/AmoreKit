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

    func deactivate(token: String) async throws {
        let body = DeactivateRequest(token: token)
        try await postVoid(path: server.deactivatePath, body: body)
    }

    func validate(token: String, nonce: String) async throws -> String {
        let body = ValidateRequest(token: token, nonce: nonce)
        return try await post(path: server.validatePath, body: body)
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> String {
        let (data, response) = try await send(path: path, body: body)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AmoreError.activationFailed(serverMessage(from: data))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data).token
    }

    private func postVoid<T: Encodable>(path: String, body: T) async throws {
        let (data, response) = try await send(path: path, body: body)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AmoreError.deactivationFailed(serverMessage(from: data))
        }
    }

    private func serverMessage(from data: Data) -> String {
        (try? JSONDecoder().decode(ErrorResponse.self, from: data).message)
            ?? "An unknown error occurred"
    }

    private func send<T: Encodable>(path: String, body: T) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: server.url.appendingPathComponent(path))
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
    let message: String
}
