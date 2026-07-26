import AmoreLicensing
import struct AmoreStore.Product
import SwiftUI

/// The checkout flow's UI: state-driven content around the embedded web view.
///
/// A thin rendering layer over ``AmoreCheckout``, embeddable in any container:
/// a popover, a custom window, a settings pane. The view starts the flow when
/// it appears idle, renders every ``AmoreCheckout/state`` including the
/// retry and license-key rescue UI on failure, and reports each attempt's
/// terminal result through `onResult`. Appearing while the flow holds a
/// terminal state renders that state rather than buying again; arm a new
/// purchase with ``AmoreCheckout/cancel()``.
///
/// The screen shown after a completed purchase is built in by default; pass
/// a `completedView` builder to replace it with a custom screen driven by
/// the same ``CheckoutCompletion``.
///
/// For the standard sheet presentation, use the
/// `amoreCheckout(item:checkout:customerEmail:onResult:)` view modifier
/// instead.
///
/// > Important: The view's lifetime drives the flow: removing it from the
/// > hierarchy cancels a checkout in progress. For a flow that outlives its
/// > UI, drive ``AmoreCheckout`` directly.
public struct AmoreCheckoutView<Completed: View>: View {
    private let checkout: AmoreCheckout
    // Builds the screen shown once the purchase completes. `nil` renders the
    // built-in one, which is what `Completed == EmptyView` stands for.
    private let completedView: ((CheckoutCompletion) -> Completed)?
    private let customerEmail: String?
    private let onDone: (() -> Void)?
    private let onResult: ((CheckoutResult) -> Void)?
    private let product: Product
    // Shows a waiting indicator instead of the web view while checkout
    // continues in the external browser.
    private let waitingForBrowser: Bool
    
    // The checkout page failed to load. The session is untouched and still
    // payable, so this is offered as a reload rather than a checkout failure.
    @State private var pageFailure: Error?
    // Counts purchase attempts, so each retry is a new pass of the same
    // view-owned task rather than work that outlives the view.
    @State private var attempt = 0
    
    /// Creates the checkout UI for one purchase attempt, with a custom
    /// success screen.
    /// - Parameters:
    ///   - checkout: The flow to start and render. Inject it idle; the view
    ///     starts it on appearance.
    ///   - product: The product to purchase, from `AmoreStore.products()`.
    ///   - customerEmail: Prefills the email field on the checkout page.
    ///   - completedView: Builds the success screen from the
    ///     ``CheckoutCompletion`` once the purchase completes.
    ///   - onDone: Called when the container should close: the user finished
    ///     with the success screen, or abandoned checkout. Dismiss the
    ///     container from here. Omitted, the success screen receives no Done
    ///     action, for a container that closes itself.
    ///   - onResult: Called with the terminal ``CheckoutResult`` of every
    ///     attempt, including retries after a failure.
    public init(
        checkout: AmoreCheckout,
        product: Product,
        customerEmail: String? = nil,
        @ViewBuilder completedView: @escaping (CheckoutCompletion) -> Completed,
        onDone: (() -> Void)? = nil,
        onResult: ((CheckoutResult) -> Void)? = nil
    ) {
        self.init(
            checkout: checkout,
            product: product,
            customerEmail: customerEmail,
            completedView: completedView,
            waitingForBrowser: false,
            onDone: onDone,
            onResult: onResult
        )
    }
    
    init(
        checkout: AmoreCheckout,
        product: Product,
        customerEmail: String?,
        completedView: ((CheckoutCompletion) -> Completed)?,
        waitingForBrowser: Bool,
        onDone: (() -> Void)?,
        onResult: ((CheckoutResult) -> Void)?
    ) {
        self.checkout = checkout
        self.completedView = completedView
        self.customerEmail = customerEmail
        self.onDone = onDone
        self.onResult = onResult
        self.product = product
        self.waitingForBrowser = waitingForBrowser
    }
    
    public var body: some View {
        content
            .task(id: attempt) {
                guard case .idle = checkout.state else { return }
                await run()
            }
    }
    
    // MARK: - Private
    
    private func run() async {
        pageFailure = nil
        let result = await checkout.start(product, customerEmail: customerEmail)
        onResult?(result)
        if case .cancelled = result, !Task.isCancelled { onDone?() }
    }
    
    @ViewBuilder
    private func completedContent(license: License, licenseKey: String) -> some View {
        let completion = CheckoutCompletion(
            license: license,
            licenseKey: licenseKey,
            onDone: onDone,
            product: product
        )
        if let completedView {
            completedView(completion)
        } else {
            CheckoutCompletedView(completion: completion)
        }
    }
    
    @ViewBuilder
    private var content: some View {
        switch checkout.state {
        case .idle, .preparing:
            ProgressView("Preparing checkout…")
        case .awaitingPayment(let url):
            if waitingForBrowser {
                browserWait
            } else if let pageFailure {
                CheckoutPageFailureView(error: pageFailure) { self.pageFailure = nil }
            } else {
                CheckoutWebView(url: url, checkout: checkout) { pageFailure = $0 }
            }
        case .activating:
            ProgressView("Activating…")
        case .completed(let license, let licenseKey):
            completedContent(license: license, licenseKey: licenseKey)
        case .failed(let error):
            CheckoutFailureView(error: error, portalURL: checkout.portalURL) {
                guard case .failed = checkout.state else { return }
                checkout.cancel()
                attempt += 1
            }
        }
    }
    
    private var browserWait: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Complete your purchase in the browser…")
        }
    }
}

extension AmoreCheckoutView where Completed == EmptyView {
    /// Creates the checkout UI for one purchase attempt, with the built-in
    /// success screen.
    /// - Parameters:
    ///   - checkout: The flow to start and render. Inject it idle; the view
    ///     starts it on appearance.
    ///   - product: The product to purchase, from `AmoreStore.products()`.
    ///   - customerEmail: Prefills the email field on the checkout page.
    ///   - onDone: Called when the container should close: the user finished
    ///     with the success screen, or abandoned checkout. Dismiss the
    ///     container from here. Omitted, the success screen renders without a
    ///     Done button, for a container that closes itself.
    ///   - onResult: Called with the terminal ``CheckoutResult`` of every
    ///     attempt, including retries after a failure.
    public init(
        checkout: AmoreCheckout,
        product: Product,
        customerEmail: String? = nil,
        onDone: (() -> Void)? = nil,
        onResult: ((CheckoutResult) -> Void)? = nil
    ) {
        self.init(
            checkout: checkout,
            product: product,
            customerEmail: customerEmail,
            completedView: nil,
            waitingForBrowser: false,
            onDone: onDone,
            onResult: onResult
        )
    }
}
