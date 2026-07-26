import Foundation
import Testing

@testable import AmoreCheckout
@testable import AmoreLicensing
import struct AmoreStore.Product

/// `start()` resolves a persisted pending session before creating a new one,
/// so an interrupted purchase can never turn into a second charge.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct CheckoutResumeTests {
    private func makeProduct() -> Product {
        Product(
            id: UUID(),
            name: "Pro",
            durationInSeconds: nil,
            deviceLimit: 3,
            price: nil,
            checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/x")!
        )
    }

    private func makeSession() -> CheckoutSession {
        CheckoutSession(
            sessionId: "cs_new",
            checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_new")!,
            expiresAt: Date.now.addingTimeInterval(3600)
        )
    }

    private func makeStore() throws -> PendingCheckoutStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckoutResumeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return PendingCheckoutStore(directory: directory)
    }

    private func makeCheckout(
        client: MockCheckoutSessionClient,
        licensing: MockLicenseActivating,
        store: PendingCheckoutStore
    ) -> AmoreCheckout {
        AmoreCheckout(
            licensing: licensing,
            bundleIdentifier: "com.example.app",
            client: client,
            store: store,
            pollInterval: .milliseconds(1)
        )
    }

    private func savePending(
        to store: PendingCheckoutStore,
        productId: UUID = UUID(),
        age: TimeInterval = 0,
        expiresAt: Date? = nil
    ) throws {
        try store.save(PendingCheckout(
            sessionId: "cs_old",
            productId: productId,
            createdAt: Date.now.addingTimeInterval(-age),
            expiresAt: expiresAt
        ))
    }

    @Test func startActivatesACompletedPendingSessionInsteadOfCharging() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onStatus = { sessionId in
            #expect(sessionId == "cs_old")
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-OLD")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-OLD"])
        #expect(client.createCallCount == 0)
        #expect(store.load() == nil)
    }

    @Test func startResumesPollingAProcessingPendingSession() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .processing, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .processing, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-OLD"),
        ])
        client.onStatus = { _ in responses.next() }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-OLD"])
        #expect(client.createCallCount == 0)
        #expect(store.load() == nil)
    }

    /// A resumed session that is already being paid for polls as an
    /// activation, not as an open checkout: it is out of reach of the Close
    /// button, and out of reach of the expiry that bounds an unpaid session
    /// (`passedDeadlineWhileActivatingDoesNotExpireTheSession` covers the
    /// latter).
    @Test func aResumedProcessingSessionActivatesAndRefusesCancellation() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        let gate = Gate()
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .processing, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-OLD"),
        ])
        // The first call is the resume check; the poll that follows is held
        // open so the test can try to abandon a session already paid for.
        client.onStatus = { _ in
            let response = responses.next()
            if response.status == .complete { await gate.wait() }
            return response
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)
        let product = makeProduct()

        let flow = Task { await checkout.start(product) }
        await gate.waitForArrival()
        if case .activating = checkout.state {} else {
            Issue.record("Expected .activating, got \(checkout.state)")
        }
        checkout.cancel()
        await gate.open()

        let result = await flow.value
        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-OLD"])
    }

    @Test func aPaidSessionStopsPollingForALicenseThatNeverArrives() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        // The webhook that issues the license never lands.
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .processing, licenseKey: nil) }
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        let result = await checkout.start(makeProduct())

        guard case .failed(.licenseIssuanceTimedOut) = result else {
            Issue.record("Expected .failed(.licenseIssuanceTimedOut), got \(result)")
            return
        }
        // The resume check plus the bounded run of polls that followed it.
        #expect(client.statusCallCount == AmoreCheckout.maxActivationPolls + 1)
        #expect(client.createCallCount == 0)
        // The purchase survives the failure: a retry, or the next launch,
        // resumes the same session rather than charging again.
        #expect(store.load() != nil)
    }

    @Test func startReopensAnOpenPendingSessionForTheSameProduct() async throws {
        let store = try makeStore()
        let product = makeProduct()
        try savePending(
            to: store, productId: product.id, expiresAt: Date.now.addingTimeInterval(3600)
        )
        let client = MockCheckoutSessionClient()
        // The interrupted checkout is still open on the server; the flow
        // returns to that session instead of opening a second one.
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .open, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-OLD"),
        ])
        client.onStatus = { sessionId in
            #expect(sessionId == "cs_old")
            return responses.next()
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(product)

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-OLD"])
        #expect(client.createCallCount == 0)
        #expect(store.load() == nil)
    }

    @Test func startDoesNotReopenAnOpenSessionPastItsExpiry() async throws {
        let store = try makeStore()
        let product = makeProduct()
        try savePending(
            to: store, productId: product.id, expiresAt: Date.now.addingTimeInterval(-60)
        )
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { sessionId in
            sessionId == "cs_old"
                ? CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
                : CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-NEW")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(product)

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-NEW"])
        #expect(client.createCallCount == 1)
    }

    @Test func startWithAnOpenSessionForAnotherProductCreatesAFreshSession() async throws {
        let store = try makeStore()
        try savePending(to: store, expiresAt: Date.now.addingTimeInterval(3600))
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        // The open session belongs to a different product than the one being
        // bought now, so it is superseded; only the new session completes.
        client.onStatus = { sessionId in
            sessionId == "cs_old"
                ? CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
                : CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-NEW")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-NEW"])
        #expect(client.createCallCount == 1)
    }

    @Test func startWithAStalePendingRecordSkipsTheStatusCheck() async throws {
        let store = try makeStore()
        try savePending(to: store, age: 25 * 60 * 60)
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { sessionId in
            #expect(sessionId == "cs_new")
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-NEW")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-NEW"])
        #expect(client.statusCallCount == 1)
    }

    @Test func startWhileLicensedSkipsAnUnpaidPendingSessionAndChargesFresh() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        // A licensed user starting a checkout is a deliberate second
        // purchase; an unpaid leftover must not hijack or block it.
        client.onStatus = { sessionId in
            sessionId == "cs_old"
                ? CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
                : CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-NEW")
        }
        let licensing = MockLicenseActivating()
        licensing.status = .valid(.fixture)
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-NEW"])
        #expect(client.createCallCount == 1)
    }

    /// Holding a license says nothing about a record that was already paid
    /// for: a second product bought on the way out of the app leaves exactly
    /// that. Discarding it unchecked would charge for the same purchase twice.
    @Test func startWhileLicensedResolvesAPaidPendingSessionInsteadOfCharging() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { sessionId in
            #expect(sessionId == "cs_old")
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-OLD")
        }
        let licensing = MockLicenseActivating()
        licensing.status = .valid(.fixture)
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-OLD"])
        #expect(client.createCallCount == 0)
        #expect(store.load() == nil)
    }

    @Test func startFailsWhenThePendingStatusCheckFails() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in throw CheckoutClientError.network("connection lost") }
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        // The pending session might already be paid; charging again without
        // knowing would be the double purchase this guard exists to prevent.
        let result = await checkout.start(makeProduct())

        guard case .failed(.pendingSessionUnresolved) = result else {
            Issue.record("Expected .failed(.pendingSessionUnresolved), got \(result)")
            return
        }
        #expect(client.createCallCount == 0)
        #expect(store.load() != nil)
    }

    @Test func startFailsWhenAPaidPendingSessionHasNoLicenseKey() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        // A paid session whose key is missing contradicts the API contract, so
        // the flow fails rather than charging for a purchase already made. The
        // record survives for a retry, which picks the key up once it appears.
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: nil) }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .failed(.pendingSessionUnresolved) = result else {
            Issue.record("Expected .failed(.pendingSessionUnresolved), got \(result)")
            return
        }
        #expect(client.createCallCount == 0)
        #expect(licensing.activatedKeys.isEmpty)
        #expect(store.load() != nil)
    }

    @Test func startDiscardsAPendingSessionTheServerHasNoRecordOf() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        // A session the server never heard of cannot resolve on a retry the
        // way a transient failure can, so it is dropped rather than holding
        // every later purchase behind a check that can never pass.
        client.onStatus = { sessionId in
            if sessionId == "cs_old" { throw CheckoutClientError.httpStatus(404) }
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-NEW")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(client.createCallCount == 1)
        #expect(licensing.activatedKeys == ["KEY-NEW"])
        #expect(store.load() == nil)
    }

    @Test func retryAfterAnUnresolvedPendingSessionActivatesItInsteadOfCharging() async throws {
        let store = try makeStore()
        try savePending(to: store)
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in throw CheckoutClientError.network("connection lost") }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let first = await checkout.start(makeProduct())
        guard case .failed(.pendingSessionUnresolved) = first else {
            Issue.record("Expected .failed(.pendingSessionUnresolved), got \(first)")
            return
        }

        // Connectivity returns and the session turns out to have been paid all
        // along: the retry activates it, never reaching a second charge.
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-OLD") }
        let second = await checkout.start(makeProduct())

        guard case .completed = second else {
            Issue.record("Expected .completed, got \(second)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-OLD"])
        #expect(client.createCallCount == 0)
        #expect(store.load() == nil)
    }
}
