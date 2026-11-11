import Foundation

/// A Stripe Checkout Session created by the licensing server.
struct CheckoutSession: Codable, Equatable, Sendable {
    var sessionId: String
    var checkoutURL: URL
    var expiresAt: Date?
}

extension CheckoutSession {
    // The checkout URL opens in the web view and the browser, and arrives
    // from the server or from a file other processes can write, so only an
    // HTTPS URL decodes.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        checkoutURL = try container.decode(URL.self, forKey: .checkoutURL)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        guard checkoutURL.scheme == "https" else {
            throw DecodingError.dataCorruptedError(
                forKey: .checkoutURL, in: container, debugDescription: "Checkout URL is not HTTPS"
            )
        }
    }

    /// The moment polling gives up on the session. Stripe sessions live at
    /// most 24 hours, so when the server omits `expiresAt` that ceiling
    /// bounds the poll instead.
    func pollDeadline(from start: Date) -> Date {
        expiresAt ?? start.addingTimeInterval(24 * 60 * 60)
    }
}
