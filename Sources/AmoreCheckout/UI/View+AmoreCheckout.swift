import struct AmoreStore.Product
import SwiftUI

extension View {
    /// Presents Stripe hosted checkout for `item` in an in-app sheet and
    /// activates the purchased license automatically.
    ///
    /// Setting `item` to a product presents checkout for it; the binding
    /// returns to `nil` when the sheet closes. One modifier serves any number
    /// of products:
    ///
    /// ```swift
    /// @State private var buying: Product?
    ///
    /// VStack {
    ///     Button("Buy Pro")  { buying = pro }
    ///     Button("Buy Team") { buying = team }
    /// }
    /// .amoreCheckout(item: $buying, checkout: checkout)
    /// ```
    ///
    /// On completion the license is activated on this device and
    /// `AmoreLicensing.status` flips to `.valid`, so gated UI unlocks
    /// reactively.
    ///
    /// See <doc:Getting-Started> for required entitlements and recovery of
    /// interrupted purchases.
    /// - Parameters:
    ///   - item: The product to purchase, from `AmoreStore.products()`.
    ///     Non-`nil` presents the checkout sheet for that product.
    ///   - checkout: The app's checkout flow. Inject it idle; the sheet
    ///     starts it on presentation and rearms it to idle on dismissal.
    ///   - customerEmail: Prefills the email field on the checkout page.
    ///   - onResult: Called with the terminal ``CheckoutResult`` of every
    ///     attempt, including retries after a failure.
    @MainActor public func amoreCheckout(
        item: Binding<Product?>,
        checkout: AmoreCheckout,
        customerEmail: String? = nil,
        onResult: ((CheckoutResult) -> Void)? = nil
    ) -> some View {
        modifier(AmoreCheckoutModifier<EmptyView>(
            item: item,
            checkout: checkout,
            completedView: nil,
            customerEmail: customerEmail,
            onResult: onResult
        ))
    }
    
    /// Presents Stripe hosted checkout for `item` in an in-app sheet with a
    /// custom success screen, and activates the purchased license
    /// automatically.
    ///
    /// Behaves like
    /// ``amoreCheckout(item:checkout:customerEmail:onResult:)``, but the
    /// screen shown after a completed purchase is built by `completedView`
    /// instead of the built-in one:
    ///
    /// ```swift
    /// .amoreCheckout(item: $buying, checkout: checkout, completedView: { completion in
    ///     VStack {
    ///         Text("Welcome aboard!")
    ///         Button("Continue") { completion.onDone?() }
    ///     }
    /// })
    /// ```
    ///
    /// - Parameters:
    ///   - item: The product to purchase, from `AmoreStore.products()`.
    ///     Non-`nil` presents the checkout sheet for that product.
    ///   - checkout: The app's checkout flow. Inject it idle; the sheet
    ///     starts it on presentation and rearms it to idle on dismissal.
    ///   - customerEmail: Prefills the email field on the checkout page.
    ///   - completedView: Builds the success screen from the
    ///     ``CheckoutCompletion`` once the purchase completes. The sheet stays
    ///     open until the screen calls ``CheckoutCompletion/onDone``, which is
    ///     always supplied here.
    ///   - onResult: Called with the terminal ``CheckoutResult`` of every
    ///     attempt, including retries after a failure.
    @MainActor public func amoreCheckout<Completed: View>(
        item: Binding<Product?>,
        checkout: AmoreCheckout,
        customerEmail: String? = nil,
        @ViewBuilder completedView: @escaping (CheckoutCompletion) -> Completed,
        onResult: ((CheckoutResult) -> Void)? = nil
    ) -> some View {
        modifier(AmoreCheckoutModifier(
            item: item,
            checkout: checkout,
            completedView: completedView,
            customerEmail: customerEmail,
            onResult: onResult
        ))
    }
}

@MainActor
private struct AmoreCheckoutModifier<Completed: View>: ViewModifier {
    @Binding var item: Product?
    let checkout: AmoreCheckout
    let completedView: ((CheckoutCompletion) -> Completed)?
    let customerEmail: String?
    let onResult: ((CheckoutResult) -> Void)?
    
    func body(content: Content) -> some View {
        content.sheet(item: $item, onDismiss: checkout.cancel) { product in
            CheckoutSheet(
                checkout: checkout,
                completedView: completedView,
                customerEmail: customerEmail,
                onResult: { onResult?($0) },
                product: product
            )
        }
    }
}
