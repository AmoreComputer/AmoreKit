# ``AmoreCheckout``

Embedded Stripe checkout with automatic license activation for macOS apps.

## Overview

AmoreCheckout is the checkout SDK for [Amore](https://amore.computer).

AmoreCheckout turns buying a license into three steps with zero context switches: click buy, pay in an in-app sheet, and the app unlocks itself. It bridges `AmoreStore` (products) and `AmoreLicensing` (activation): checkout completes, the license key is fetched from the server, and `AmoreLicensing.activate(licenseKey:)` runs automatically.

The core is the UI-independent ``AmoreCheckout`` object. Observe its ``AmoreCheckout/state`` to build a custom paywall, or run checkout entirely through the external browser. The sheet modifier and ``AmoreCheckoutView`` are thin layers over it.

## Topics

### Articles

- <doc:Getting-Started>
- <doc:Custom-Checkout-UI>

### Essentials

- ``AmoreCheckout``
- ``SwiftUICore/View/amoreCheckout(item:checkout:customerEmail:onResult:)``
- ``SwiftUICore/View/amoreCheckout(item:checkout:customerEmail:completedView:onResult:)``
- ``CheckoutResult``

### Customization

- ``AmoreCheckoutView``
- ``CheckoutCompletion``

### Observing the Flow

- ``CheckoutState``

### Errors

- ``CheckoutError``
- ``CheckoutClientError``
