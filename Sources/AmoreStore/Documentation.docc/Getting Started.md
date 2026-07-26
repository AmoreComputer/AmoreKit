# Getting Started

This article describes how to get started with AmoreStore.

## Installation

In Xcode, go to **File → Add Package Dependencies…** and enter:

```
https://github.com/AmoreComputer/AmoreKit
```

Or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/AmoreComputer/AmoreKit", from: "0.1")
```

## AmoreStore

To get started with AmoreStore, create an instance of ``AmoreStore``. By default it uses your app's `Bundle.main.bundleIdentifier`.

```swift
let store = AmoreStore()
```

## Fetching Products

Call ``AmoreStore/products()`` to fetch the products configured for your app.

```swift
let products = try await store.products()
```

> Note: ``AmoreStore/products()`` throws ``StoreError`` with detailed information about what went wrong.

## Displaying Prices

Each ``Product`` carries an optional ``Product/price`` with a localized, display-ready string.

```swift
ForEach(products) { product in
    HStack {
        Text(product.name)
        Spacer()
        if let displayPrice = product.displayPrice {
            Text(displayPrice)
        }
    }
}
```

Use ``Price/recurringInterval`` to tell one-time purchases from subscriptions.

## Checkout

Prefer the `AmoreCheckout` module: one view modifier presents Stripe checkout
in-app and activates the purchased license automatically.

```swift
@State private var buying: Product?

Button("Buy Pro") { buying = product }
    .amoreCheckout(item: $buying, checkout: checkout)
```

Alternatively, every purchasable ``Product`` carries a ``Product/checkoutURL``
you can open in the browser for the classic flow (pay, receive the key by
email, enter it in the app):

```swift
NSWorkspace.shared.open(product.checkoutURL)
```
