import Foundation

@testable import AmoreCheckout
@testable import AmoreLicensing

final class MockCheckoutSessionClient: CheckoutSessionClient, @unchecked Sendable {
    /// The closures throw untyped so tests can write plain literals; anything
    /// that is not already a `CheckoutClientError` is narrowed to `.network`.
    var onCreate: (@Sendable (UUID, String?) async throws -> CheckoutSession)?
    var onStatus: (@Sendable (String) async throws -> CheckoutSessionStatusResponse)?
    private(set) var createCallCount = 0
    private(set) var statusCallCount = 0

    func createSession(productId: UUID, customerEmail: String?) async throws(CheckoutClientError) -> CheckoutSession {
        createCallCount += 1
        guard let onCreate else { throw CheckoutClientError.invalidResponse }
        return try await narrowing { try await onCreate(productId, customerEmail) }
    }

    func sessionStatus(sessionId: String) async throws(CheckoutClientError) -> CheckoutSessionStatusResponse {
        statusCallCount += 1
        guard let onStatus else { throw CheckoutClientError.invalidResponse }
        return try await narrowing { try await onStatus(sessionId) }
    }

    private func narrowing<T>(_ body: () async throws -> T) async throws(CheckoutClientError) -> T {
        do {
            return try await body()
        } catch let error as CheckoutClientError {
            throw error
        } catch {
            throw CheckoutClientError.network(error.localizedDescription)
        }
    }
}

@MainActor
final class MockLicenseActivating: LicenseActivating {
    var status: ValidationStatus = .unknown
    var activationError: AmoreError?
    /// When set, `activate(licenseKey:)` suspends here before doing anything
    /// else, so a test can interleave other coordinator calls mid-activation.
    var activateGate: Gate?
    private(set) var activatedKeys: [String] = []

    func activate(licenseKey: String) async throws(AmoreError) {
        if let activateGate {
            await activateGate.wait()
        }
        activatedKeys.append(licenseKey)
        if let activationError { throw activationError }
        status = .valid(.fixture)
    }
}

/// A one-shot suspension point for tests that need to pause a mock mid-call,
/// confirm the awaiting code actually reached that point, then release it and
/// observe how the resumed call is handled.
actor Gate {
    private var isOpen = false
    private var hasArrived = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivalWaiters: [CheckedContinuation<Void, Never>] = []

    /// Suspends the caller until `open()` is called.
    func wait() async {
        hasArrived = true
        releaseArrivalWaiters()
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Suspends the caller until some other task has called `wait()`, giving
    /// up after `timeout`.
    ///
    /// A flow that ends before it ever reaches the gate leaves nobody to
    /// announce an arrival, and a plain continuation would park the test until
    /// the whole run is killed. Giving up hands the failure to the assertions
    /// that follow, where it reads as the wrong result rather than a hang.
    func waitForArrival(timeout: Duration = .seconds(5)) async {
        if hasArrived { return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            await self?.releaseArrivalWaiters()
        }
        await withCheckedContinuation { arrivalWaiters.append($0) }
        timer.cancel()
    }

    /// Releases every caller currently suspended in `wait()`, and any future ones.
    func open() {
        isOpen = true
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume() }
    }

    private func releaseArrivalWaiters() {
        let pending = arrivalWaiters
        arrivalWaiters = []
        for waiter in pending { waiter.resume() }
    }
}

extension PendingCheckout {
    /// Builds the embedded session from its parts, so tests that only care
    /// about identity and age stay flat.
    init(sessionId: String, productId: UUID, createdAt: Date, expiresAt: Date? = nil) {
        self.init(
            session: CheckoutSession(
                sessionId: sessionId,
                checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/\(sessionId)")!,
                expiresAt: expiresAt
            ),
            productId: productId,
            createdAt: createdAt
        )
    }
}

extension License {
    /// A minimal valid license for coordinator tests. Uses the internal
    /// memberwise initializer via @testable import.
    ///
    /// Written as `License`/`Product` rather than the module-qualified
    /// `AmoreLicensing.License`/`AmoreLicensing.Product`: the `AmoreLicensing`
    /// module also declares a public type named `AmoreLicensing`, so within a
    /// file that imports the module, `AmoreLicensing.X` resolves to a member
    /// of that type rather than a member of the module and fails to compile.
    static let fixture = License(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        product: Product(name: "Pro", identifier: "pro"),
        expiresAt: nil,
        entitlements: [],
        subscriptionState: nil,
        customer: nil
    )
}
