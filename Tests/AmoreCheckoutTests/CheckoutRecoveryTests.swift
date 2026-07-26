import Foundation
import Testing

@testable import AmoreCheckout
@testable import AmoreLicensing
import struct AmoreStore.Product

@MainActor
@Suite(.timeLimit(.minutes(1))) struct CheckoutRecoveryTests {
    private func makeProduct(id: UUID) -> Product {
        Product(
            id: id,
            name: "Pro",
            durationInSeconds: nil,
            deviceLimit: 3,
            price: nil,
            checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/x")!
        )
    }

    private func makeStore() throws -> PendingCheckoutStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CheckoutRecoveryTests-\(UUID().uuidString)")
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

    @Test func activatesCompletedPendingSession() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { sessionId in
            #expect(sessionId == "cs_9")
            return CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-9")
        }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(licensing.activatedKeys == ["KEY-9"])
        #expect(license?.id == License.fixture.id)
        #expect(store.load() == nil)
    }

    @Test func clearsExpiredPendingSession() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .expired, licenseKey: nil) }
        let licensing = MockLicenseActivating()
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(license == nil)
        #expect(store.load() == nil)
        #expect(licensing.activatedKeys.isEmpty)
    }

    @Test func clearsStalePendingWithoutNetworkCall() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(
            sessionId: "cs_9",
            productId: UUID(),
            createdAt: Date.now.addingTimeInterval(-25 * 60 * 60)
        ))
        let client = MockCheckoutSessionClient()
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(license == nil)
        #expect(store.load() == nil)
        #expect(client.statusCallCount == 0)
    }

    @Test func clearsAnUnpaidPendingSessionWhenAlreadyLicensed() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .open, licenseKey: nil) }
        let licensing = MockLicenseActivating()
        licensing.status = .valid(.fixture)
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(license == nil)
        #expect(licensing.activatedKeys.isEmpty)
        // The abandoned record would otherwise be re-checked on every launch.
        #expect(store.load() == nil)
    }

    /// A license for one product says nothing about a paid record for another,
    /// so recovery resolves the record instead of discarding it: dropping it
    /// would leave the purchase to be charged a second time.
    @Test func activatesAPaidPendingSessionWhenAlreadyLicensed() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-9") }
        let licensing = MockLicenseActivating()
        licensing.status = .valid(.fixture)
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(licensing.activatedKeys == ["KEY-9"])
        #expect(license?.id == License.fixture.id)
        #expect(store.load() == nil)
    }

    @Test func leavesOpenPendingSessionInPlace() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .open, licenseKey: nil) }
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        let license = await checkout.recoverPendingPurchase()

        #expect(license == nil)
        #expect(store.load()?.sessionId == "cs_9")
    }

    @Test func reportsAnActivationThatWillNotSucceed() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-9") }
        let licensing = MockLicenseActivating()
        licensing.activationError = .client(.deviceLimitReached)
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let license = await checkout.recoverPendingPurchase()

        // Silence would retry this at every launch and then discard the record
        // at maxPendingAge, leaving a customer who paid with nothing to show.
        #expect(license == nil)
        guard case .failed(.activationFailed(let key, let underlying)) = checkout.state else {
            Issue.record("Expected .failed(.activationFailed), got \(checkout.state)")
            return
        }
        #expect(key == "KEY-9")
        #expect(underlying == .client(.deviceLimitReached))
        #expect(store.load() != nil)
    }

    @Test func leavesThePendingRecordWhenTheStatusCheckFails() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in throw CheckoutClientError.network("offline") }
        let checkout = makeCheckout(client: client, licensing: MockLicenseActivating(), store: store)

        let license = await checkout.recoverPendingPurchase()

        // An unreachable server says nothing about the purchase, so recovery
        // stays quiet and leaves the record for the next launch.
        #expect(license == nil)
        #expect(store.load()?.sessionId == "cs_9")
        guard case .idle = checkout.state else {
            Issue.record("Expected .idle, got \(checkout.state)")
            return
        }
    }

    @Test func returnsNilWhenNothingIsPending() async throws {
        let client = MockCheckoutSessionClient()
        let checkout = makeCheckout(
            client: client, licensing: MockLicenseActivating(), store: try makeStore()
        )

        let license = await checkout.recoverPendingPurchase()

        #expect(license == nil)
        #expect(client.statusCallCount == 0)
    }

    // MARK: - Concurrency

    @Test func aSecondRecoveryJoinsTheOneInFlight() async throws {
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: UUID(), createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-9") }
        let licensing = MockLicenseActivating()
        let gate = Gate()
        licensing.activateGate = gate
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        let first = Task { await checkout.recoverPendingPurchase() }
        await gate.waitForArrival()
        let second = Task { await checkout.recoverPendingPurchase() }
        await gate.open()
        let firstLicense = await first.value
        let secondLicense = await second.value

        #expect(licensing.activatedKeys == ["KEY-9"])
        #expect(firstLicense == secondLicense)
    }

    @Test func recoveringDuringACheckoutWaitsForItInsteadOfActivatingTwice() async throws {
        let store = try makeStore()
        let client = MockCheckoutSessionClient()
        client.onCreate = { _, _ in
            CheckoutSession(
                sessionId: "cs_new",
                checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_new")!,
                expiresAt: Date.now.addingTimeInterval(3600)
            )
        }
        client.onStatus = { _ in CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-1") }
        let licensing = MockLicenseActivating()
        let gate = Gate()
        licensing.activateGate = gate
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        // The app recovers on foregrounding while a checkout is mid-activation.
        // Recovery waits for the flow rather than reading the same pending
        // record and activating its key a second time.
        let buying = Task { await checkout.start(makeProduct(id: UUID())) }
        await gate.waitForArrival()
        let recovering = Task { await checkout.recoverPendingPurchase() }
        await gate.open()
        let result = await buying.value
        let license = await recovering.value

        #expect(licensing.activatedKeys == ["KEY-1"])
        #expect(license?.id == License.fixture.id)
        guard case .completed = result else {
            Issue.record("Expected .completed, got \(result)")
            return
        }
    }

    @Test func buyingDuringRecoveryWaitsForItInsteadOfChargingAgain() async throws {
        let productId = UUID()
        let store = try makeStore()
        try store.save(PendingCheckout(sessionId: "cs_9", productId: productId, createdAt: .now))
        let client = MockCheckoutSessionClient()
        client.onCreate = { _, _ in
            CheckoutSession(
                sessionId: "cs_new",
                checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/cs_new")!,
                expiresAt: Date.now.addingTimeInterval(3600)
            )
        }
        client.onStatus = { sessionId in
            sessionId == "cs_9"
                ? CheckoutSessionStatusResponse(status: .complete, licenseKey: "KEY-9")
                : CheckoutSessionStatusResponse(status: .open, licenseKey: nil)
        }
        let licensing = MockLicenseActivating()
        let gate = Gate()
        licensing.activateGate = gate
        let checkout = makeCheckout(client: client, licensing: licensing, store: store)

        // The buy button is tapped while launch recovery is mid-activation, so
        // the paywall is still up for a purchase that has already been paid
        // for. The flow waits for recovery, then stops on the license it
        // activated: the same key is never activated twice, and the customer is
        // never shown a second checkout for a product they now own. `onCreate`
        // is wired so that lapse would show up as a session rather than a crash.
        let recovering = Task { await checkout.recoverPendingPurchase() }
        await gate.waitForArrival()
        let buying = Task { await checkout.start(makeProduct(id: productId)) }
        await gate.open()
        #expect(await recovering.value != nil)
        let result = await buying.value

        #expect(licensing.activatedKeys == ["KEY-9"])
        #expect(client.createCallCount == 0)
        #expect(checkout.state == .idle)
        guard case .cancelled = result else {
            Issue.record("Expected .cancelled, got \(result)")
            return
        }
    }
}
