import Foundation
import Testing

@testable import AmoreCheckout

/// Captures the URLRequest a stubbed transport received.
private final class CapturedRequest: @unchecked Sendable {
    var request: URLRequest?
}

@Suite struct CheckoutSessionClientTests {
    private let baseURL = URL(string: "https://api.amore.computer")!
    private let bundleId = "com.example.app"

    private func makeClient(
        status: Int = 200,
        body: String,
        captured: CapturedRequest = CapturedRequest()
    ) -> HTTPCheckoutSessionClient {
        HTTPCheckoutSessionClient(
            baseURL: baseURL,
            bundleIdentifier: bundleId,
            transport: { request in
                captured.request = request
                let response = HTTPURLResponse(
                    url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
                )!
                return (Data(body.utf8), response)
            }
        )
    }

    @Test func createSessionBuildsRequestAndDecodesResponse() async throws {
        let captured = CapturedRequest()
        let client = makeClient(
            status: 201,
            body: """
            {
              "checkoutURL": "https://checkout.stripe.com/c/pay/cs_1",
              "expiresAt": "2026-07-18T10:00:00Z",
              "sessionId": "cs_1"
            }
            """,
            captured: captured
        )
        let productId = UUID()

        let session = try await client.createSession(productId: productId, customerEmail: "b@example.com")

        #expect(session.sessionId == "cs_1")
        #expect(session.checkoutURL == URL(string: "https://checkout.stripe.com/c/pay/cs_1"))

        let request = try #require(captured.request)
        #expect(request.url?.absoluteString
            == "https://api.amore.computer/v1/public/apps/com.example.app/checkout/sessions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["productId"] == productId.uuidString)
        #expect(json["customerEmail"] == "b@example.com")
    }

    @Test func createSessionOmitsNilEmail() async throws {
        let captured = CapturedRequest()
        let client = makeClient(
            status: 201,
            body: #"{ "checkoutURL": "https://c.example/s", "sessionId": "cs_1" }"#,
            captured: captured
        )

        _ = try await client.createSession(productId: UUID(), customerEmail: nil)

        let body = try #require(captured.request?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(json["customerEmail"] == nil)
    }

    @Test func sessionStatusBuildsRequestAndDecodesResponse() async throws {
        let captured = CapturedRequest()
        let client = makeClient(
            status: 200,
            body: #"{ "licenseKey": "KEY-1", "status": "complete" }"#,
            captured: captured
        )

        let status = try await client.sessionStatus(sessionId: "cs_42")

        #expect(status.status == .complete)
        #expect(status.licenseKey == "KEY-1")
        let request = try #require(captured.request)
        #expect(request.url?.absoluteString
            == "https://api.amore.computer/v1/public/apps/com.example.app/checkout/sessions/cs_42")
        #expect(request.httpMethod == "GET")
    }

    @Test func throwsOnNon2xxStatus() async throws {
        let client = makeClient(status: 502, body: "")

        await #expect(throws: CheckoutClientError.httpStatus(502)) {
            try await client.sessionStatus(sessionId: "cs_1")
        }
    }

    @Test func throwsRateLimitedOn429() async throws {
        let client = makeClient(status: 429, body: "")

        await #expect(throws: CheckoutClientError.rateLimited) {
            try await client.sessionStatus(sessionId: "cs_1")
        }
    }

    @Test func wrapsTransportFailuresAsNetworkError() async throws {
        let client = HTTPCheckoutSessionClient(
            baseURL: baseURL,
            bundleIdentifier: bundleId,
            transport: { _ in throw URLError(.notConnectedToInternet) }
        )

        await #expect(throws: CheckoutClientError.network(
            URLError(.notConnectedToInternet).localizedDescription
        )) {
            try await client.sessionStatus(sessionId: "cs_1")
        }
    }

    @Test func throwsOnNonHTTPResponse() async throws {
        let client = HTTPCheckoutSessionClient(
            baseURL: baseURL,
            bundleIdentifier: bundleId,
            transport: { request in (Data(), URLResponse(
                url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil
            )) }
        )

        await #expect(throws: CheckoutClientError.invalidResponse) {
            try await client.sessionStatus(sessionId: "cs_1")
        }
    }
}
