# Getting Started

This article describes how to get started with AmoreLicensing.

## Installation

In Xcode, go to **File → Add Package Dependencies…** and enter:

```
https://github.com/AmoreComputer/AmoreKit
```

Or add it to your `Package.swift`:

```swift
.package(url: "https://github.com/AmoreComputer/AmoreKit", from: "0.1")
```

## AmoreLicensing

To get started with AmoreLicensing, create an instance of ``AmoreLicensing`` with your public licensing key.

```swift
let licensing = try AmoreLicensing(
    publicKey: "sa92JNtsaYefYp0MIWQbKu1hpS9bSN89ta7b8mlPbI8=",
)
```

> Note: All methods on ``AmoreLicensing`` throw ``AmoreError`` with detailed information about what went wrong.

## Activation

To activate your user's license, call ``AmoreLicensing/activate(licenseKey:)`` with a valid license key.

## Validation

``AmoreLicensing`` validates the stored license once at launch and then whenever you call ``AmoreLicensing/validate()``. There is no background timer: ``ValidationFrequency`` is the staleness threshold that decides whether a ``AmoreLicensing/validate()`` call refreshes from the server or just verifies the cached token locally. Drive revalidation from your app's lifecycle to keep a long-running app fresh:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active { Task { try? await licensing.validate() } }
}
```


``AmoreLicensing`` is `@Observable` and plays nicely with the Observation framework and SwiftUI.

```swift
// Validate manually
try await licensing.validate()

// Observe status
switch licensing.status {
case .valid(let license):
    print("License is valid")
case .invalid:
    print("License is invalid")
case .gracePeriod(let license):
    print("Grace period until \(endDate)")
case .unknown:
    print("License status unknown")
}
```

## Deactivate

You can deactivate a user's license via ``AmoreLicensing/deactivate()``, remove the license activation on the server and delete the local copy.

## Entitlements

Use ``License/Entitlement`` to check what features a license grants. Define entitlements as static constants or as a custom enum:

```swift
// Static constants
extension License.Entitlement {
    static let pro: Self = "pro"
    static let teams: Self = "teams"
}

// Or a custom enum
enum AppEntitlement: String, EntitlementProtocol {
    case pro, teams
}

// Check entitlements on a valid license
if case .valid(let license) = licensing.status {
    let hasPro = license.validate(entitlement: .pro)
    let hasTeams = license.validate(entitlement: AppEntitlement.teams)
}
```
