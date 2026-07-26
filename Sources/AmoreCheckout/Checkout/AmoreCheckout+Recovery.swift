import AmoreLicensing
import Foundation

extension AmoreCheckout {
    /// Pending sessions older than this are discarded without a network call.
    static let maxPendingAge: TimeInterval = 24 * 60 * 60
    
    /// How many times a paid session asks for its license before the flow
    /// stops waiting. Bounding the requests rather than the elapsed time keeps
    /// a server that never issues the license from being polled indefinitely.
    static let maxActivationPolls = 100
    
    /// How many status checks in a row may fail before a checkout that has not
    /// been paid for gives up. A paid one keeps polling to its own bound.
    static let maxPollingFailures = 8
    
    /// Resolves a checkout interrupted by the app quitting after payment: if
    /// the persisted pending session completed, the license is activated
    /// silently and returned. Call once at launch.
    ///
    /// Payment that succeeded but could not be activated on this device is
    /// reported through ``state`` as
    /// ``CheckoutError/activationFailed(licenseKey:underlying:)``, which
    /// carries the license key, rather than resolved silently.
    ///
    /// A second call made while the first is still running joins it rather
    /// than resolving the same pending session twice, and the two entry points
    /// wait for each other: ``start(_:customerEmail:)`` waits for a recovery in
    /// flight before reading the pending session, and a recovery started during
    /// a checkout waits for that checkout, so neither order activates the same
    /// key twice.
    @discardableResult
    public func recoverPendingPurchase() async -> License? {
        if let recovery { return await recovery.value }
        // A checkout in progress resolves the same pending session before it
        // creates anything new, so recovery waits for its result instead of
        // reading that session too.
        if let flow, isInProgress {
            guard case .completed(let license, _) = await flow.value else { return nil }
            return license
        }
        let recovery = Task { await resolvePendingPurchase() }
        self.recovery = recovery
        let license = await recovery.value
        if self.recovery == recovery { self.recovery = nil }
        return license
    }
    
    // MARK: - Private
    
    private func resolvePendingPurchase() async -> License? {
        guard let pending = store.load() else { return nil }
        guard Date.now.timeIntervalSince(pending.createdAt) < Self.maxPendingAge else {
            store.clear()
            return nil
        }
        let status: CheckoutSessionStatusResponse
        do {
            status = try await client.sessionStatus(sessionId: pending.sessionId)
        } catch {
            // An unreachable server says nothing about the purchase, so the
            // pending session is left for the next launch.
            return nil
        }
        switch status.status {
        case .complete:
            guard let key = status.licenseKey else { return nil }
            return await activateRecovered(licenseKey: key)
        case .expired:
            store.clear()
        case .open:
            if case .valid = licensing.status { store.clear() }
        case .processing:
            break
        }
        return nil
    }
    
    // A key the server issued that this device cannot activate fails the same
    // way at every launch, so the failure is surfaced while the key is still
    // recoverable: retrying in silence would end at `maxPendingAge` discarding
    // the record, and with it the only copy of a key the customer paid for.
    private func activateRecovered(licenseKey: String) async -> License? {
        do {
            try await licensing.activate(licenseKey: licenseKey)
        } catch {
            state = .failed(.activationFailed(licenseKey: licenseKey, underlying: error))
            return nil
        }
        store.clear()
        if case .valid(let license) = licensing.status { return license }
        return nil
    }
}
