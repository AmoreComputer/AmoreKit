import AmoreLicensing
import Foundation
import Observation

/// Drives Stripe hosted checkout: session creation, status polling, and
/// automatic license activation.
///
/// Create one instance per app, alongside `AmoreLicensing`, and pass the
/// product to buy to each ``start(_:customerEmail:)`` call. `AmoreCheckout`
/// is UI-independent: observe ``state`` to render any purchase UI, or use the
/// built-in surfaces, which are thin layers over this object: the
/// `amoreCheckout(item:checkout:customerEmail:onResult:)` sheet modifier
/// or an embedded ``AmoreCheckoutView``.
///
/// Purchases interrupted by the app quitting are recovered with
/// ``recoverPendingPurchase()``, typically at launch. See <doc:Getting-Started>
/// for full setup and <doc:Custom-Checkout-UI> for surfaces of your own,
/// including a browser-only flow with no embedded web view.
@Observable @MainActor
public final class AmoreCheckout {
    
    /// The current state of the flow. Terminal states persist until the next
    /// ``start(_:customerEmail:)``.
    public internal(set) var state: CheckoutState = .idle
    
    let baseURL: URL
    let licensing: any LicenseActivating
    let client: any CheckoutSessionClient
    let store: PendingCheckoutStore
    let pollInterval: Duration
    @ObservationIgnored
    var flow: Task<CheckoutResult, Never>?
    @ObservationIgnored
    var recovery: Task<License?, Never>?
    
    /// Creates the app's checkout flow. One instance serves every product;
    /// pass the product being purchased to ``start(_:customerEmail:)``.
    /// - Parameters:
    ///   - licensing: The licensing instance that activates purchased keys.
    ///   - bundleIdentifier: The app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier`.
    ///   - baseURL: The licensing server base URL.
    public convenience init(
        licensing: AmoreLicensing,
        bundleIdentifier: String? = nil,
        baseURL: URL = .amoreServer
    ) {
        self.init(
            licensing: licensing as any LicenseActivating,
            bundleIdentifier: bundleIdentifier,
            baseURL: baseURL
        )
    }
    
    init(
        licensing: any LicenseActivating,
        bundleIdentifier: String? = nil,
        baseURL: URL = .amoreServer,
        client: (any CheckoutSessionClient)? = nil,
        store: PendingCheckoutStore? = nil,
        pollInterval: Duration = .seconds(3)
    ) {
        let resolved = Self.resolveBundleIdentifier(bundleIdentifier)
        self.licensing = licensing
        self.baseURL = baseURL
        self.client = client ?? HTTPCheckoutSessionClient(
            baseURL: baseURL, bundleIdentifier: resolved
        )
        self.store = store ?? PendingCheckoutStore(bundleIdentifier: resolved)
        self.pollInterval = pollInterval
    }
    
    /// Whether a checkout is running (any non-terminal state except ``CheckoutState/idle``).
    public var isInProgress: Bool {
        switch state {
        case .preparing, .awaitingPayment, .activating: true
        case .idle, .completed, .failed: false
        }
    }
    
    /// The hosted checkout URL while payment is awaited, `nil` otherwise.
    public var checkoutURL: URL? {
        if case .awaitingPayment(let url) = state { return url }
        return nil
    }
    
    /// The customer portal on the configured server, for manual license management.
    public var portalURL: URL {
        baseURL.appending(path: "portal")
    }
    
    // MARK: - Internal
    
    // A missing identifier only shows up later as a confusing server 404,
    // so assert here where it can actually be fixed.
    private static func resolveBundleIdentifier(_ bundleIdentifier: String?) -> String {
        if let bundleIdentifier { return bundleIdentifier }
        guard let main = Bundle.main.bundleIdentifier else {
            assertionFailure("No bundle identifier available. Pass bundleIdentifier explicitly.")
            return ""
        }
        return main
    }
}
