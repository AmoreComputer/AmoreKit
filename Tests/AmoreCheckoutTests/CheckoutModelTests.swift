import Foundation
import Testing

@testable import AmoreCheckout
@testable import AmoreLicensing

@Suite struct CheckoutModelTests {
    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @Test func decodesCheckoutSession() throws {
        let json = """
        {
          "checkoutURL": "https://checkout.stripe.com/c/pay/cs_test_123",
          "expiresAt": "2026-07-18T10:00:00Z",
          "sessionId": "cs_test_123"
        }
        """
        let session = try decoder.decode(CheckoutSession.self, from: Data(json.utf8))

        #expect(session.sessionId == "cs_test_123")
        #expect(session.checkoutURL == URL(string: "https://checkout.stripe.com/c/pay/cs_test_123"))
        #expect(session.expiresAt == ISO8601DateFormatter().date(from: "2026-07-18T10:00:00Z"))
    }

    @Test func decodesSessionWithoutExpiry() throws {
        let json = """
        { "checkoutURL": "https://checkout.stripe.com/c/pay/cs_1", "sessionId": "cs_1" }
        """
        let session = try decoder.decode(CheckoutSession.self, from: Data(json.utf8))

        #expect(session.expiresAt == nil)
    }

    @Test func decodesCompleteStatusWithKey() throws {
        let json = """
        { "licenseKey": "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE-FFFFF-00000-11111", "status": "complete" }
        """
        let status = try decoder.decode(CheckoutSessionStatusResponse.self, from: Data(json.utf8))

        #expect(status.status == .complete)
        #expect(status.licenseKey == "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE-FFFFF-00000-11111")
    }

    @Test func decodesOpenStatusWithoutKey() throws {
        let json = """
        { "status": "open" }
        """
        let status = try decoder.decode(CheckoutSessionStatusResponse.self, from: Data(json.utf8))

        #expect(status.status == .open)
        #expect(status.licenseKey == nil)
    }

    @Test func onlyPrePaymentStatesAreCancellable() {
        let url = URL(string: "https://checkout.stripe.com/c/pay/cs_1")!
        #expect(CheckoutState.preparing.isCancellable)
        #expect(CheckoutState.awaitingPayment(url).isCancellable)
        #expect(!CheckoutState.idle.isCancellable)
        #expect(!CheckoutState.activating.isCancellable)
        #expect(!CheckoutState.completed(.fixture, licenseKey: "KEY-1").isCancellable)
        #expect(!CheckoutState.failed(.sessionExpired).isCancellable)
    }

    @Test func sessionCreationFailureSurfacesTheClientMessage() {
        let error = CheckoutError.sessionCreationFailed(underlying: .rateLimited)
        #expect(error.errorDescription == "Too many requests. Please try again later.")
    }

    @Test func unresolvedPendingSessionReadsAsAVerificationFailure() {
        // Distinct from .sessionCreationFailed: an earlier purchase could not
        // be verified, so the message must not read as a failure to start.
        let withUnderlying = CheckoutError.pendingSessionUnresolved(underlying: .rateLimited)
        let withoutUnderlying = CheckoutError.pendingSessionUnresolved(underlying: nil)
        let expected = "Your previous purchase could not be confirmed. Please try again."

        #expect(withUnderlying.errorDescription == expected)
        #expect(withoutUnderlying.errorDescription == expected)
    }

    @Test func pollDeadlineUsesTheServerExpiry() {
        let expiry = Date.now.addingTimeInterval(600)
        let session = CheckoutSession(
            sessionId: "cs_1",
            checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_1")!,
            expiresAt: expiry
        )
        #expect(session.pollDeadline(from: .now) == expiry)
    }

    @Test func pollDeadlineWithoutServerExpiryIsBoundedByTheSessionCeiling() {
        let start = Date.now
        let session = CheckoutSession(
            sessionId: "cs_1",
            checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_1")!,
            expiresAt: nil
        )
        #expect(session.pollDeadline(from: start) == start.addingTimeInterval(24 * 60 * 60))
    }

    @Test func decodesAllStatusValues() throws {
        for (raw, expected) in [
            ("open", CheckoutSessionStatus.open),
            ("processing", .processing),
            ("complete", .complete),
            ("expired", .expired),
        ] {
            let json = #"{ "status": "\#(raw)" }"#
            let status = try decoder.decode(CheckoutSessionStatusResponse.self, from: Data(json.utf8))
            #expect(status.status == expected)
        }
    }
}
