import struct AmoreStore.Product
import Foundation

extension AmoreCheckout {
    
    /// Abandons the checkout and returns to ``CheckoutState/idle``: a flow in
    /// progress ends with a pending ``start(_:customerEmail:)`` returning
    /// `.cancelled`, and a terminal state is cleared so the next start begins
    /// fresh. Refused during ``CheckoutState/activating``
    /// (``CheckoutState/isCancellable`` is `false`), so a paid session always
    /// runs to a terminal state.
    public func cancel() {
        if case .activating = state { return }
        flow?.cancel()
        state = .idle
    }
    
    /// Runs a checkout for `product` to its terminal result: creates a
    /// session, polls until payment resolves, and activates the purchased
    /// license.
    ///
    /// ``state`` tracks progress for observers and settles on the matching
    /// terminal state before the result is returned, so the two can never
    /// disagree. Calling from ``CheckoutState/completed(_:licenseKey:)`` or
    /// ``CheckoutState/failed(_:)`` starts a fresh attempt, so a Try Again
    /// button is just another `await checkout.start(product)`. Calling while
    /// an attempt is already in progress joins it and returns that attempt's
    /// result, whichever product it was for, so a surface offering several
    /// products should disable its buy buttons on ``isInProgress``.
    /// Cancelling the surrounding task, or calling ``cancel()``, ends the
    /// flow with `.cancelled`.
    ///
    /// A purchase interrupted after payment is picked up instead of charged
    /// again: a persisted pending session that completed activates its
    /// license, and one still processing is polled to its result. Only an
    /// unpaid, expired, or stale pending session is superseded by a fresh one.
    /// A ``recoverPendingPurchase()`` still in flight is awaited first, and if
    /// it activated the interrupted purchase the attempt ends `.cancelled`
    /// rather than opening a checkout for a product now owned.
    /// - Parameters:
    ///   - product: The product to purchase, from `AmoreStore.products()`.
    ///   - customerEmail: Prefills the email field on the checkout page.
    @discardableResult
    public func start(
        _ product: Product,
        customerEmail: String? = nil
    ) async -> CheckoutResult {
        // A re-entrant start (a double-clicked retry, two surfaces driving
        // one checkout) joins the attempt in progress instead of reporting a
        // false .cancelled for a flow that is still running.
        if let flow, isInProgress {
            return await flow.value
        }
        state = .preparing
        
        let flow = Task { await run(product: product, customerEmail: customerEmail) }
        self.flow = flow
        let result = await withTaskCancellationHandler {
            await flow.value
        } onCancel: {
            flow.cancel()
        }
        // A flow ended by cancelling the surrounding task still owns the state
        // and returns it to idle; once cancel() or a newer start() has taken
        // over, it keeps its hands off.
        if case .cancelled = result, self.flow == flow, isInProgress {
            state = .idle
        }
        return result
    }
    
    // MARK: - Private
    
    private func run(product: Product, customerEmail: String?) async -> CheckoutResult {
        if let recovery {
            _ = await recovery.value
            if case .valid = licensing.status { return .cancelled }
        }
        if let resumed = await resumePendingSession(for: product) { return resumed }
        let session: CheckoutSession
        do {
            session = try await client.createSession(
                productId: product.id, customerEmail: customerEmail
            )
        } catch {
            guard !Task.isCancelled else { return .cancelled }
            return fail(.sessionCreationFailed(underlying: error))
        }
        guard !Task.isCancelled else { return .cancelled }
        do {
            try store.save(PendingCheckout(
                session: session, productId: product.id, createdAt: .now
            ))
        } catch {
            store.clear()
            return fail(.checkoutNotRecordable)
        }
        state = .awaitingPayment(session.checkoutURL)
        return await poll(
            sessionId: session.sessionId, paymentDeadline: session.pollDeadline(from: .now)
        )
    }
    
    // A pending session persisted by an earlier interrupted purchase is
    // resolved before any new session is created, so the customer cannot be
    // charged twice: a completed session activates its license, one still
    // processing is polled to its result, and an open one for the same
    // product is reopened at its original URL. Only an unpaid session falls
    // through to a fresh checkout: one for another product, an expired or
    // stale one, one the server has no record of, or a leftover held by an
    // already-licensed user.
    private func resumePendingSession(for product: Product) async -> CheckoutResult? {
        guard let pending = store.load() else { return nil }
        guard pending.createdAt.addingTimeInterval(Self.maxPendingAge) > .now else {
            store.clear()
            return nil
        }
        let status: CheckoutSessionStatusResponse
        do {
            status = try await client.sessionStatus(sessionId: pending.sessionId)
        } catch {
            guard !Task.isCancelled else { return .cancelled }
            if case .httpStatus(404) = error {
                store.clear()
                return nil
            }
            return fail(.pendingSessionUnresolved(underlying: error))
        }
        guard !Task.isCancelled else { return .cancelled }
        switch status.status {
        case .complete:
            guard let key = status.licenseKey else {
                return fail(.pendingSessionUnresolved(underlying: nil))
            }
            return await activate(licenseKey: key)
        case .processing:
            state = .activating
            return await poll(sessionId: pending.sessionId, paymentDeadline: nil)
        case .expired:
            store.clear()
            return nil
        case .open:
            if case .valid = licensing.status {
                store.clear()
                return nil
            }
            // The session's own expiry bounds the reopened wait, falling back
            // to the pending-age ceiling when the server omitted one.
            let expiry = pending.session.pollDeadline(from: pending.createdAt)
            guard pending.productId == product.id, expiry > .now else { return nil }
            state = .awaitingPayment(pending.session.checkoutURL)
            return await poll(sessionId: pending.sessionId, paymentDeadline: expiry)
        }
    }
    
    // The wait for payment is bounded by the session's own expiry; the wait
    // for the license that follows it is bounded by the number of requests
    // instead, so a server that never issues one cannot be polled
    // indefinitely. A nil `paymentDeadline` is a session already paid for.
    private func poll(sessionId: String, paymentDeadline: Date?) async -> CheckoutResult {
        var deadline = paymentDeadline
        var activationPolls = 0
        var consecutiveFailures = 0
        while !Task.isCancelled {
            if case .activating = state { deadline = nil }
            if let deadline {
                if deadline <= .now { return fail(.sessionExpired) }
            } else {
                activationPolls += 1
                if activationPolls > Self.maxActivationPolls {
                    return fail(.licenseIssuanceTimedOut)
                }
            }
            do {
                let status = try await client.sessionStatus(sessionId: sessionId)
                guard !Task.isCancelled else { return .cancelled }
                consecutiveFailures = 0
                switch status.status {
                case .complete:
                    if let key = status.licenseKey {
                        return await activate(licenseKey: key)
                    }
                    // Payment landed; the license is still being issued.
                    state = .activating
                case .processing:
                    state = .activating
                case .expired:
                    return fail(.sessionExpired)
                case .open:
                    break
                }
            } catch {
                consecutiveFailures += 1
                if state != .activating {
                    if case .httpStatus(404) = error { return fail(.sessionExpired) }
                    if consecutiveFailures > Self.maxPollingFailures {
                        return fail(.pollingFailed(underlying: error))
                    }
                }
            }
            try? await Task.sleep(for: pollInterval * (1 << min(consecutiveFailures, 3)))
        }
        return .cancelled
    }
    
    private func activate(licenseKey: String) async -> CheckoutResult {
        state = .activating
        do {
            try await licensing.activate(licenseKey: licenseKey)
        } catch {
            guard !Task.isCancelled else { return .cancelled }
            return fail(.activationFailed(licenseKey: licenseKey, underlying: error))
        }
        store.clear()
        guard case .valid(let license) = licensing.status else {
            return fail(.activationFailed(licenseKey: licenseKey, underlying: .invalidToken))
        }
        state = .completed(license, licenseKey: licenseKey)
        return .completed(license, licenseKey: licenseKey)
    }
    
    private func fail(_ error: CheckoutError) -> CheckoutResult {
        state = .failed(error)
        return .failed(error)
    }
}
