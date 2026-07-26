import Foundation
import Testing

@testable import AmoreCheckout
@testable import AmoreLicensing
// Scoped import, not `import AmoreStore`: the AmoreStore module also declares
// a public type named `AmoreStore`, so within a file that imports the module,
// `AmoreStore.Product` resolves to a member of that type rather than a member
// of the module and fails to compile. Importing just `Product` sidesteps that
// and still resolves unambiguously against `AmoreLicensing`'s own `Product`.
import struct AmoreStore.Product

/// Returns queued responses one at a time, repeating the last one.
final class ResponseSequence: @unchecked Sendable {
    private var responses: [CheckoutSessionStatusResponse]

    init(_ responses: [CheckoutSessionStatusResponse]) {
        self.responses = responses
    }

    func next() -> CheckoutSessionStatusResponse {
        responses.count > 1 ? responses.removeFirst() : responses[0]
    }
}

@MainActor
// The polling loop is what ends most of these tests, and it is cancellable, so
// a bound that regresses into retrying forever fails here on the time limit
// rather than parking the run until someone kills it.
@Suite(.timeLimit(.minutes(1))) struct CheckoutFlowTests {
    private let baseURL = URL(string: "https://api.amore.computer")!

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

    private nonisolated func makeSession(
        expiresAt: Date? = Date.now.addingTimeInterval(3600)
    ) -> CheckoutSession {
        CheckoutSession(
            sessionId: "cs_1",
            checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_1")!,
            expiresAt: expiresAt
        )
    }

    private func makeStore() throws -> PendingCheckoutStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckoutFlowTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return PendingCheckoutStore(directory: directory)
    }

    /// A store whose containing directory cannot be created, because a regular
    /// file already occupies the path, so every save throws.
    private func makeUnwritableStore() throws -> PendingCheckoutStore {
        let blocker = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckoutFlowTests-blocked-\(UUID().uuidString)")
        try Data().write(to: blocker)
        return PendingCheckoutStore(directory: blocker.appendingPathComponent("store"))
    }

    private func makeCheckout(
        client: MockCheckoutSessionClient,
        licensing: MockLicenseActivating,
        store: PendingCheckoutStore,
        baseURL: URL? = nil
    ) -> AmoreCheckout {
        AmoreCheckout(
            licensing: licensing,
            bundleIdentifier: "com.example.app",
            baseURL: baseURL ?? self.baseURL,
            client: client,
            store: store,
            pollInterval: .milliseconds(1)
        )
    }

    // MARK: - Happy path

    @Test func happyPathActivatesAndCompletes() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .open, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1"),
        ])
        client.onStatus = { _ in responses.next() }
        let licensing = MockLicenseActivating()
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        #expect(licensing.activatedKeys == ["KEY-1"])
        guard case .completed(let license, let licenseKey) = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(license.id == License.fixture.id)
        // The issued key travels with the terminal payload so the success
        // screen can show it.
        #expect(licenseKey == "KEY-1")
        guard case .completed(_, licenseKey: let stateKey) = checkout.state else {
            Issue.record("Expected .completed state, got \(checkout.state)")
            return
        }
        #expect(stateKey == "KEY-1")
        #expect(store.load() == nil)
    }

    @Test func startPersistsThePendingSession() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        // Session never completes; the first status response reports expired
        // so start() returns instead of polling forever.
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .expired, licenseKey: nil) }
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        await checkout.start(makeProduct())

        // The pending record was written when checkout opened and survives
        // expiry for the recovery path to clean up.
        #expect(store.load()?.sessionId == "cs_1")
    }

    // MARK: - Failure paths

    @Test func sessionCreationFailureIsTerminal() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { _, _ in throw CheckoutClientError.httpStatus(502) }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        let result = await checkout.start(makeProduct())

        guard case .failed(.sessionCreationFailed) = result else {
            Issue.record("Expected .failed(.sessionCreationFailed), got \(result)")
            return
        }
        guard case .failed(.sessionCreationFailed) = checkout.state else {
            Issue.record("Expected .failed state, got \(checkout.state)")
            return
        }
    }

    @Test func pastExpiryStopsPollingWithSessionExpired() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession(expiresAt: Date.now.addingTimeInterval(-60))] _, _ in
            session
        }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .open, licenseKey: nil) }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        let result = await checkout.start(makeProduct())

        guard case .failed(.sessionExpired) = result else {
            Issue.record("Expected .failed(.sessionExpired), got \(result)")
            return
        }
        #expect(client.statusCallCount == 0)
    }

    @Test func aPaidSessionOutlivesTheSessionDeadline() async throws {
        let client = MockCheckoutSessionClient()
        // The deadline runs from the moment the session is created, which is
        // the last step before the poll that reads it, so none of its window
        // is spent getting the flow that far.
        client.onCreate = { [self] _, _ in
            makeSession(expiresAt: Date.now.addingTimeInterval(0.1))
        }
        let gate = Gate()
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .open, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1"),
        ])
        client.onStatus = { _ in
            await gate.wait()
            return responses.next()
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        // Payment succeeds in the web view, then the session deadline passes
        // while the first status response is still in flight. Webhook lag must
        // not turn the paid session into .sessionExpired.
        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        checkout.handleSuccessRedirect()
        try await Task.sleep(for: .milliseconds(300))
        await gate.open()
        let result = await startTask.value

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    /// Checkout finished in the browser has no web view to report the success
    /// redirect, so the server status is the only signal that payment landed.
    /// Reading it keeps a paid session out of reach of the expiry that bounds
    /// an unpaid one, on every surface rather than just the embedded sheet.
    @Test func aServerReportedPaymentOutlivesTheSessionDeadline() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [self] _, _ in
            makeSession(expiresAt: Date.now.addingTimeInterval(0.1))
        }
        let gate = Gate()
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .processing, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1"),
        ])
        // The session deadline passes while the response that reports the
        // payment is still in flight.
        client.onStatus = { _ in
            let response = responses.next()
            if response.status == .processing { await gate.wait() }
            return response
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        try await Task.sleep(for: .milliseconds(300))
        await gate.open()
        let result = await startTask.value

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    @Test func missingExpiryStillPollsToCompletion() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession(expiresAt: nil)] _, _ in session }
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .open, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1"),
        ])
        client.onStatus = { _ in responses.next() }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        await checkout.start(makeProduct())

        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    @Test func expiredStatusStopsPolling() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .expired, licenseKey: nil) }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        let result = await checkout.start(makeProduct())

        guard case .failed(.sessionExpired) = result else {
            Issue.record("Expected .failed(.sessionExpired), got \(result)")
            return
        }
    }

    @Test func transientPollErrorsAreSwallowed() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let failures = FailOnceThenComplete()
        client.onStatus = { _ in try failures.next() }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        await checkout.start(makeProduct())

        #expect(licensing.activatedKeys == ["KEY-1"])
        #expect(client.statusCallCount == 2)
    }

    @Test func rateLimitedPollContinuesAndCompletes() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let failures = FailOnceThenComplete(error: .rateLimited)
        client.onStatus = { _ in try failures.next() }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        await checkout.start(makeProduct())

        #expect(licensing.activatedKeys == ["KEY-1"])
        #expect(client.statusCallCount == 2)
    }

    @Test func aPaidSessionWaitsForALicenseTheServerHasNotIssuedYet() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let responses = ResponseSequence([
            CheckoutSessionStatusResponse(status: .complete, licenseKey: nil),
            CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1"),
        ])
        client.onStatus = { _ in responses.next() }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        // Payment lands before the license exists, the seconds of webhook lag
        // every real purchase passes through: the flow keeps waiting for the
        // key rather than failing a purchase that succeeded.
        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
        #expect(client.statusCallCount == 2)
    }

    @Test func anUnreachableServerEndsAnUnpaidCheckout() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in throw CheckoutClientError.network("offline") }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        // Nothing has been paid, so the transport failure is reported rather
        // than retried until the session expires and blamed on the expiry.
        let result = await checkout.start(makeProduct())

        guard case .failed(.pollingFailed(let underlying)) = result else {
            Issue.record("Expected .failed(.pollingFailed), got \(result)")
            return
        }
        #expect(underlying == .network("offline"))
        #expect(client.statusCallCount == AmoreCheckout.maxPollingFailures + 1)
    }

    @Test func aSessionTheServerHasLostIsReportedAsExpired() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in throw CheckoutClientError.httpStatus(404) }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        // A session the server has no record of will not come back on a later
        // tick, and to the user it is an expired one.
        let result = await checkout.start(makeProduct())

        guard case .failed(.sessionExpired) = result else {
            Issue.record("Expected .failed(.sessionExpired), got \(result)")
            return
        }
        #expect(client.statusCallCount == 1)
    }

    @Test func aPaidSessionKeepsPollingThroughNetworkFailures() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let responses = OfflineAfterPayment(failures: AmoreCheckout.maxPollingFailures + 4)
        client.onStatus = { _ in try responses.next() }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        // The bound that protects an unpaid checkout must not apply once
        // payment lands: giving up here would report a transport error for a
        // purchase that succeeded.
        let result = await checkout.start(makeProduct())

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    @Test func activationFailureCarriesTheLicenseKey() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1") }
        let licensing = MockLicenseActivating()
        licensing.activationError = .client(.deviceLimitReached)
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let result = await checkout.start(makeProduct())

        guard case .failed(.activationFailed(let key, let underlying)) = result else {
            Issue.record("Expected .failed(.activationFailed), got \(result)")
            return
        }
        #expect(key == "KEY-1")
        #expect(underlying == .client(.deviceLimitReached))
        guard case .failed(.activationFailed) = checkout.state else {
            Issue.record("Expected .failed state, got \(checkout.state)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
        // The payment went through, so the pending record has to outlive the
        // failed activation: it is what the next launch's recovery picks up.
        #expect(store.load() != nil)
    }

    @Test func startRearmsFromAFailedState() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { _, _ in throw CheckoutClientError.httpStatus(502) }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        let first = await checkout.start(makeProduct())
        guard case .failed = first else {
            Issue.record("Expected .failed, got \(first)")
            return
        }

        // The server recovers; a plain second start() must run a fresh attempt.
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-2") }
        let second = await checkout.start(makeProduct())

        guard case .completed = second else {
            Issue.record("Expected .completed, got \(second)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-2"])
    }

    @Test func reentrantStartJoinsTheFlowInProgress() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let gate = Gate()
        client.onStatus = { _ in
            await gate.wait()
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        // A double-clicked retry calls start() again mid-flight; the second
        // call must join the running attempt, not crash or report .cancelled.
        let first = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        let second = Task { await checkout.start(makeProduct()) }
        await gate.open()
        let firstResult = await first.value
        let secondResult = await second.value

        guard case .completed = firstResult else {
            Issue.record("Expected .completed, got \(firstResult)")
            return
        }
        guard case .completed = secondResult else {
            Issue.record("Expected .completed, got \(secondResult)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    // MARK: - Recovery

    @Test func recoverPendingPurchaseUsesTheInjectedClientAndStore() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-9") }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(license?.id == License.fixture.id)
        #expect(licensing.activatedKeys == ["KEY-9"])
        #expect(store.load() == nil)
    }

    // MARK: - Navigation interception

    @Test func navigationMatchingRoutesServerPages() throws {
        let checkout = makeCheckout(
            client: MockCheckoutSessionClient(), licensing: MockLicenseActivating(), store: try makeStore()
        )

        let success = URL(string: "https://api.amore.computer/checkout/success?session_id=cs_1&product=x")!
        let cancel = URL(string: "https://api.amore.computer/checkout/cancel")!
        let stripe = URL(string: "https://checkout.stripe.com/c/pay/cs_1")!
        let unrelated = URL(string: "https://api.amore.computer/portal")!
        let wrongHostSuccess = URL(string: "https://evil.example.com/checkout/success")!
        let wrongSchemeSuccess = URL(string: "http://api.amore.computer/checkout/success")!

        #expect(checkout.navigationAction(for: success) == .interceptSuccess)
        #expect(checkout.navigationAction(for: cancel) == .interceptCancel)
        #expect(checkout.navigationAction(for: stripe) == .allow)
        #expect(checkout.navigationAction(for: unrelated) == .allow)
        #expect(checkout.navigationAction(for: wrongHostSuccess) == .allow)
        #expect(checkout.navigationAction(for: wrongSchemeSuccess) == .allow)
    }

    @Test func navigationMatchingRespectsBaseURLPath() throws {
        let checkout = makeCheckout(
            client: MockCheckoutSessionClient(),
            licensing: MockLicenseActivating(),
            store: try makeStore(),
            baseURL: URL(string: "https://staging.example.com/api")!
        )

        let success = URL(string: "https://staging.example.com/api/checkout/success?session_id=1")!
        let wrongPath = URL(string: "https://staging.example.com/checkout/success")!

        #expect(checkout.navigationAction(for: success) == .interceptSuccess)
        #expect(checkout.navigationAction(for: wrongPath) == .allow)
    }

    // MARK: - Cancellation

    @Test func cancelEndsAnInFlightStartWithCancelled() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let gate = Gate()
        client.onStatus = { _ in
            await gate.wait()
            return CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
        }
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        checkout.cancel()
        await gate.open()
        let result = await startTask.value

        guard case .cancelled = result else {
            Issue.record("Expected .cancelled, got \(result)")
            return
        }
        guard case .idle = checkout.state else {
            Issue.record("Expected .idle, got \(checkout.state)")
            return
        }
        // Unlike the cancel redirect, a plain cancel is ambiguous (the user
        // may still pay in a browser tab), so the record stays recoverable.
        #expect(store.load() != nil)
    }

    @Test func cancelDuringActivationIsRefused() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1") }
        let licensing = MockLicenseActivating()
        let gate = Gate()
        licensing.activateGate = gate
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        // Payment already succeeded; cancelling mid-activation is refused so
        // the paid session always reaches a terminal state.
        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        checkout.cancel()
        guard case .activating = checkout.state else {
            Issue.record("Expected cancel to be refused in .activating, got \(checkout.state)")
            return
        }
        await gate.open()
        let result = await startTask.value

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    @Test func cancelClearsATerminalStateSoTheNextStartBeginsFresh() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { _, _ in throw CheckoutClientError.httpStatus(502) }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        await checkout.start(makeProduct())
        guard case .failed = checkout.state else {
            Issue.record("Expected .failed, got \(checkout.state)")
            return
        }
        checkout.cancel()
        guard case .idle = checkout.state else {
            Issue.record("Expected .idle, got \(checkout.state)")
            return
        }
    }

    @Test func surroundingTaskCancellationAfterActivationStillCompletes() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1") }
        let licensing = MockLicenseActivating()
        let gate = Gate()
        licensing.activateGate = gate
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        // The hosting view leaves the hierarchy mid-activation. The license is
        // activated anyway, so the purchase is reported as completed and its
        // pending record cleared: reporting .cancelled here would leave the
        // record behind for the next launch to activate a second time.
        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        startTask.cancel()
        await gate.open()
        let result = await startTask.value

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        guard case .completed = checkout.state else {
            Issue.record("Expected .completed, got \(checkout.state)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
        #expect(store.load() == nil)
    }

    @Test func anUnrecordableSessionStopsCheckoutBeforePayment() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeUnwritableStore()
        )

        let result = await checkout.start(makeProduct())

        guard case .failed(.checkoutNotRecordable) = result else {
            Issue.record("Expected .failed(.checkoutNotRecordable), got \(result)")
            return
        }
        // A session that was never recorded cannot be recovered, so the user
        // must never reach a page they could pay on.
        #expect(checkout.checkoutURL == nil)
        #expect(client.statusCallCount == 0)
    }

    @Test func surroundingTaskCancellationEndsTheFlow() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let gate = Gate()
        client.onStatus = { _ in
            await gate.wait()
            return CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
        }
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: try makeStore())

        // The hosting view leaves the hierarchy while checkout is polling: the
        // task is cancelled directly and the flow must end on its own.
        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        startTask.cancel()
        await gate.open()
        let result = await startTask.value

        guard case .cancelled = result else {
            Issue.record("Expected .cancelled, got \(result)")
            return
        }
        guard case .idle = checkout.state else {
            Issue.record("Expected .idle, got \(checkout.state)")
            return
        }
    }

    @Test func cancelRedirectAbandonsTheFlowButKeepsThePendingRecord() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let gate = Gate()
        client.onStatus = { _ in
            await gate.wait()
            return CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
        }
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        #expect(checkout.checkoutURL != nil)
        checkout.handleCancelRedirect()
        await gate.open()
        let result = await startTask.value

        guard case .cancelled = result else {
            Issue.record("Expected .cancelled, got \(result)")
            return
        }
        guard case .idle = checkout.state else {
            Issue.record("Expected .idle, got \(checkout.state)")
            return
        }
        // The cancel page ends the flow but is not proof the payment failed,
        // so the record survives for the next start() to resolve against the
        // server.
        #expect(store.load() != nil)
    }

    @Test func cancelRedirectAfterPaymentKeepsTheFlowAndThePendingRecord() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1") }
        let licensing = MockLicenseActivating()
        let gate = Gate()
        licensing.activateGate = gate
        let store = try makeStore()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        // The user reaches the cancel page after paying, by going back or by
        // the page redirecting late. Abandoning here would clear the record
        // that makes the payment recoverable, so the redirect is ignored and
        // the flow runs to its terminal state.
        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        checkout.handleCancelRedirect()
        if case .activating = checkout.state {} else {
            Issue.record("Expected the cancel redirect to be ignored in .activating, got \(checkout.state)")
        }
        #expect(store.load() != nil)
        await gate.open()
        let result = await startTask.value

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
        #expect(licensing.activatedKeys == ["KEY-1"])
    }

    @Test func successRedirectMovesToActivating() async throws {
        let client = MockCheckoutSessionClient()
        client.onCreate = { [session = makeSession()] _, _ in session }
        let gate = Gate()
        client.onStatus = { _ in
            await gate.wait()
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: try makeStore())

        let startTask = Task { await checkout.start(makeProduct()) }
        await gate.waitForArrival()
        checkout.handleSuccessRedirect()
        guard case .activating = checkout.state else {
            Issue.record("Expected .activating, got \(checkout.state)")
            return
        }
        await gate.open()
        let result = await startTask.value

        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
    }

    @Test func successRedirectOutsideAFlowIsIgnored() async throws {
        let checkout = makeCheckout(
            client: MockCheckoutSessionClient(), licensing: MockLicenseActivating(), store: try makeStore()
        )

        checkout.handleSuccessRedirect()

        guard case .idle = checkout.state else {
            Issue.record("Expected .idle, got \(checkout.state)")
            return
        }
    }
}

/// Reports payment, then fails a run of status checks before issuing the key.
final class OfflineAfterPayment: @unchecked Sendable {
    private var hasReportedPayment = false
    private var remainingFailures: Int

    init(failures: Int) {
        remainingFailures = failures
    }

    func next() throws(CheckoutClientError) -> CheckoutSessionStatusResponse {
        if !hasReportedPayment {
            hasReportedPayment = true
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: nil)
        }
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw .network("offline")
        }
        return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1")
    }
}

/// Throws once, then reports completion. Exercises the swallow-and-retry path.
final class FailOnceThenComplete: @unchecked Sendable {
    private let error: CheckoutClientError
    private var hasFailed = false

    init(error: CheckoutClientError = .network("connection lost")) {
        self.error = error
    }

    func next() throws(CheckoutClientError) -> CheckoutSessionStatusResponse {
        if !hasFailed {
            hasFailed = true
            throw error
        }
        return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1")
    }
}
