import Foundation
import Testing

@testable import AmoreCheckout
@testable import AmoreLicensing
import struct AmoreStore.Price
import struct AmoreStore.Product

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

    @Test(arguments: ["http://checkout.example/pay", "file:///Applications/Calculator.app"])
    func rejectsSessionWhoseCheckoutURLIsNotHTTPS(_ url: String) {
        let json = #"{ "checkoutURL": "\#(url)", "sessionId": "cs_1" }"#

        #expect(throws: DecodingError.self) {
            try decoder.decode(CheckoutSession.self, from: Data(json.utf8))
        }
    }

    @Test func decodesCompleteStatusWithKey() throws {
        let json = """
        { "licenseKey": "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE-FFFFF-00000-11111", "status": "complete" }
        """
        let status = try decoder.decode(CheckoutSessionStatusResponse.self, from: Data(json.utf8))

        #expect(status.status == .complete)
        #expect(status.licenseKey == "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE-FFFFF-00000-11111")
    }

    @Test func decodesTheAmountPaid() throws {
        let json = """
        { "amountPaid": { "currency": "EUR", "unitAmount": 569 }, "licenseKey": "KEY-1", "status": "complete" }
        """
        let status = try decoder.decode(CheckoutSessionStatusResponse.self, from: Data(json.utf8))

        #expect(status.amountPaid == Price(unitAmount: 569, currency: "EUR", recurringInterval: nil))
    }

    @Test func statusWithoutAnAmountHasNoAmountPaid() throws {
        // A server that predates the amount does not send it.
        let json = """
        { "licenseKey": "KEY-1", "status": "complete" }
        """
        let status = try decoder.decode(CheckoutSessionStatusResponse.self, from: Data(json.utf8))

        #expect(status.amountPaid == nil)
    }

    // MARK: - Receipt price

    private func completion(amountPaid: Price?, license: License = .fixture, price: Price?) -> CheckoutCompletion {
        CheckoutCompletion(
            amountPaid: amountPaid,
            license: license,
            licenseKey: "KEY-1",
            product: Product(
                id: UUID(), name: "Pro", durationInSeconds: nil, deviceLimit: 3, price: price,
                checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/x")!
            )
        )
    }

    @Test func completionCarriesEverythingThePurchaseHolds() {
        let paid = Price(unitAmount: 569, currency: "EUR", recurringInterval: nil)
        let purchase = CheckoutPurchase(amountPaid: paid, license: .fixture, licenseKey: "KEY-1")
        let product = Product(
            id: UUID(), name: "Pro", durationInSeconds: nil, deviceLimit: 3,
            price: Price(unitAmount: 600, currency: "USD", recurringInterval: nil),
            checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/x")!
        )

        let completion = CheckoutCompletion(purchase: purchase, onDone: nil, product: product)

        #expect(completion.amountPaid == paid)
        #expect(completion.license == purchase.license)
        #expect(completion.licenseKey == purchase.licenseKey)
        #expect(completion.product == product)
        // The receipt shows what was charged, not the product's price.
        #expect(completion.displayPrice == paid.displayPrice)
    }

    @Test func receiptShowsTheAmountPaidOverTheProductPrice() {
        let usd = Price(unitAmount: 600, currency: "USD", recurringInterval: nil)
        let eur = Price(unitAmount: 569, currency: "EUR", recurringInterval: nil)

        #expect(completion(amountPaid: eur, price: usd).displayPrice == eur.displayPrice)
        #expect(eur.displayPrice != usd.displayPrice)
    }

    @Test func receiptShowsAFullDiscountAsZero() {
        let usd = Price(unitAmount: 600, currency: "USD", recurringInterval: nil)
        let free = Price(unitAmount: 0, currency: "USD", recurringInterval: nil)

        #expect(completion(amountPaid: free, price: usd).displayPrice == free.displayPrice)
    }

    @Test func receiptFallsBackToTheProductPriceWhenTheAmountIsUnknown() {
        let usd = Price(unitAmount: 600, currency: "USD", recurringInterval: nil)

        #expect(completion(amountPaid: nil, price: usd).displayPrice == usd.displayPrice)
        #expect(completion(amountPaid: nil, price: nil).displayPrice == nil)
    }

    @Test func receiptShowsNoPriceForASubscriptionThatChargesLater() {
        let usd = Price(unitAmount: 600, currency: "USD", recurringInterval: .month)
        let free = Price(unitAmount: 0, currency: "IDR", recurringInterval: nil)
        var renewing = License.fixture
        renewing.subscriptionState = .renewing(renewsAt: .now.addingTimeInterval(30 * 86400))

        #expect(completion(amountPaid: free, license: .trialFixture, price: usd).displayPrice == nil)
        #expect(completion(amountPaid: nil, license: .trialFixture, price: usd).displayPrice == nil)
        // A coupon that made the first period free.
        #expect(completion(amountPaid: free, license: renewing, price: usd).displayPrice == nil)
        #expect(completion(amountPaid: usd, license: renewing, price: usd).displayPrice == usd.displayPrice)
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
        #expect(!CheckoutState.completed(CheckoutPurchase(license: .fixture, licenseKey: "KEY-1")).isCancellable)
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
