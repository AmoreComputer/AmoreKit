# Custom Checkout UI

Replace the success screen, embed checkout in your own container, or run it in the external browser.

## Overview

The sheet modifier is a thin layer over ``AmoreCheckout``, which is UI-independent. Every surface below drives the same object and activates the purchased license the same way.

## Custom Success Screens

The sheet ends with a receipt-style success screen summarizing the activated license. Replace it with a screen of your own, built from the same ``CheckoutCompletion``, and call its ``CheckoutCompletion/onDone`` to close the sheet.

```swift
.amoreCheckout(item: $buying, checkout: checkout, completedView: { completion in
    VStack {
        Text("Welcome to \(completion.product.name)!")
        Button("Start") { completion.onDone?() }
    }
})
```

> Note: `onDone` is `nil` in a container that closes itself, so a custom screen omits its button just as the default receipt does.

## Custom Containers

Embed ``AmoreCheckoutView`` in a container of your own and close it from `onDone`, which the success screen's button calls.

```swift
AmoreCheckoutView(
    checkout: checkout,
    product: product,
    onDone: { isPresented = false }
)
```

`onDone` covers both ways checkout ends for good: the success screen's button calls it, and so does abandoning checkout through the page's cancel link. Pass `onResult` as well to act on the outcome itself.

``AmoreCheckoutView`` takes the same `completedView` builder as the sheet modifier.

> Important: The view's lifetime drives the flow. Removing it from the hierarchy cancels a checkout in progress. For a flow that outlives its UI, drive ``AmoreCheckout`` directly.

## Browser-Only Checkout

Skip the embedded web view entirely and hand the URL to the browser as soon as the session opens.

```swift
Button("Buy") {
    Task {
        switch await checkout.start(product) {
        case .completed(let license, _):
            print("Unlocked \(license.product.name)")
        case .cancelled:
            break
        case .failed(let error):
            print(error.localizedDescription)
        }
    }
}
.disabled(checkout.isInProgress)
.onChange(of: checkout.checkoutURL) { _, url in
    if let url { NSWorkspace.shared.open(url) }
}
```

``AmoreCheckout/isInProgress`` is observed, so the button comes back by itself once the attempt reaches a terminal state, and a retry is another tap.

> Important: A surface offering several products needs that guard. ``AmoreCheckout/start(_:customerEmail:)`` joins an attempt already running rather than starting a second one, and returns that attempt's result whichever product it was for. The sheet modifier presents one product at a time and needs nothing.

## Observing State

``AmoreCheckout`` is `@Observable`, so a paywall built from no supplied views at all reads ``AmoreCheckout/state`` directly.

```swift
switch checkout.state {
case .idle, .preparing:
    ProgressView()
case .awaitingPayment(let url):
    Link("Pay", destination: url)
case .activating:
    Text("Activating…")
case .completed(let license, _):
    Text("Unlocked \(license.product.name)")
case .failed(let error):
    Text(error.localizedDescription)
}
```

``CheckoutState`` settles on the matching terminal case before ``AmoreCheckout/start(_:customerEmail:)`` returns, so the two can never disagree. Use ``CheckoutState/isCancellable`` to hide a cancel button once payment is detected.
