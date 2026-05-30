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

Every purchasable ``Product`` carries a ``Product/checkoutURL``. Open it to send the customer to Stripe checkout.

```swift
NSWorkspace.shared.open(product.checkoutURL)
```
