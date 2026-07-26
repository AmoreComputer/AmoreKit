# Getting Started

This article describes how to get started with AmoreCheckout.

## Installation

In Xcode, go to **File → Add Package Dependencies…** and enter:

```
https://github.com/AmoreComputer/AmoreKit
```

Or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/AmoreComputer/AmoreKit", from: "0.1")
```

## Requirements

Checkout runs in an embedded web view, so sandboxed apps need the outgoing-connections entitlement:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

> Note: Payment can always finish in the external browser, which Apple Pay requires. The app activates the license either way.

## AmoreCheckout

To get started with AmoreCheckout, create an instance of ``AmoreCheckout`` with the `AmoreLicensing` instance that activates purchased keys.

```swift
let licensing = try AmoreLicensing(
    publicKey: "sa92JNtsaYefYp0MIWQbKu1hpS9bSN89ta7b8mlPbI8=",
)
let checkout = AmoreCheckout(licensing: licensing)
```

You own the ``AmoreCheckout`` object: create it once where you create `AmoreLicensing`, and pass it down. One instance serves every product, and its lifetime is yours, so nothing is re-created behind your back on view updates.

## Presenting Checkout

Fetch products with `AmoreStore`, then set the product to buy. The ``SwiftUICore/View/amoreCheckout(item:checkout:customerEmail:onResult:)`` modifier presents checkout for whatever the binding holds.

```swift
import AmoreCheckout
import SwiftUI
import struct AmoreStore.Product

struct PaywallView: View {
    let checkout: AmoreCheckout
    let products: [Product]
    @State private var buying: Product?

    var body: some View {
        VStack {
            ForEach(products) { product in
                Button("Buy \(product.name)") { buying = product }
            }
        }
        .amoreCheckout(item: $buying, checkout: checkout)
    }
}
```

> Note: `AmoreLicensing` and `AmoreStore` both declare a type named `Product`, so importing both modules whole leaves the name ambiguous. Import the one checkout takes directly, as above.

When payment completes, the license is activated on this device and `licensing.status` flips to `.valid`, so gated UI unlocks reactively.

## Handling Results

Pass `onResult` to receive the terminal ``CheckoutResult`` of every attempt, including retries after a failure.

```swift
.amoreCheckout(item: $buying, checkout: checkout) { result in
    switch result {
    case .completed(let license, let licenseKey):
        print("Unlocked \(license.product.name) with \(licenseKey)")
    case .cancelled:
        break
    case .failed(.activationFailed(let licenseKey, _)):
        print("Activate manually with \(licenseKey)")
    case .failed(let error):
        print(error.localizedDescription)
    }
}
```

> Tip: The sheet already shows the license key on success, and on ``CheckoutError/activationFailed(licenseKey:underlying:)`` it shows the key with a copy button. The result carries it for your own UI too, and the key is never persisted beyond the flow.

## Recovering Interrupted Purchases

If the app quits mid-checkout after the user paid, resolve the purchase once at launch:

```swift
await checkout.recoverPendingPurchase()
```

``AmoreCheckout/start(_:customerEmail:)`` guards the same interrupted purchase, so a customer cannot be charged twice by buying again before recovery runs: a session that already completed activates its license, one still processing is polled to its result, and an open session for the same product reopens where it left off.

> Important: When that session cannot be checked at all, the flow fails with ``CheckoutError/pendingSessionUnresolved(underlying:)`` rather than charging again. Retrying is safe and re-checks the session.
