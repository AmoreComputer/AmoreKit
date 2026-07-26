import Foundation

/// A Stripe Checkout Session created by the licensing server.
struct CheckoutSession: Codable, Equatable, Sendable {
    var sessionId: String
    var checkoutURL: URL
    var expiresAt: Date?
}

extension CheckoutSession {
    /// The moment polling gives up on the session. Stripe sessions live at
    /// most 24 hours, so when the server omits `expiresAt` that ceiling
    /// bounds the poll instead.
    func pollDeadline(from start: Date) -> Date {
        expiresAt ?? start.addingTimeInterval(24 * 60 * 60)
    }
}
