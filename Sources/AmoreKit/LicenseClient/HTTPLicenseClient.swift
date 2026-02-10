import Foundation

struct HTTPLicenseClient: LicenseClient {
    private let serverURL: URL

    init(serverURL: URL) {
        self.serverURL = serverURL
    }

    func activate(licenseKey: String, hardwareId: String, nonce: String) async throws -> String {
        let body = ActivateRequest(licenseKey: licenseKey, hardwareId: hardwareId, nonce: nonce)
        return try await post(path: "/activate", body: body)
    }

    func refresh(hardwareId: String, oldToken: String, nonce: String) async throws -> String {
        let body = RefreshRequest(hardwareId: hardwareId, oldToken: oldToken, nonce: nonce)
        return try await post(path: "/refresh", body: body)
    }

    private func post<T: Encodable>(path: String, body: T) async throws -> String {
        var request = URLRequest(url: serverURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder.default.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AmoreError.activationFailed("Server returned error")
        }
        let tokenResponse = try JSONDecoder.default.decode(TokenResponse.self, from: data)
        return tokenResponse.token
    }
}

private struct ActivateRequest: Encodable {
    let licenseKey: String
    let hardwareId: String
    let nonce: String
}

private struct RefreshRequest: Encodable {
    let hardwareId: String
    let oldToken: String
    let nonce: String
}

private struct TokenResponse: Decodable {
    let token: String
}

private extension JSONDecoder {
    static let `default`: JSONDecoder = {
        let decoder = JSONDecoder()
        return decoder
    }()
}

private extension JSONEncoder {
    static let `default`: JSONEncoder = {
        let encoder = JSONEncoder()
        return encoder
    }()
}
