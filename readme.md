# AmoreKit

A macOS JWT-based licensing SDK with offline-first validation and hardware ID binding for [amore.computer](https://amore.computer)

## Requirements

- macOS 14+

## Installation

Add AmoreLicensing via Swift Package Manager:

```swift
.package(url: "https://github.com/AmoreComputer/AmoreKit", from: "0.1")
```

## Quick Start

```swift
import AmoreLicensing

// Initialize with your Ed25519 public key from Amore
let licensing = try AmoreLicensing(publicKey: "your-ed25519-public-key")

// Activate a license
try await licensing.activate(licenseKey: "XXXX-XXXX-XXXX-XXXX")

// Observe status reactively in SwiftUI
struct ContentView: View {
    @State var licensing: AmoreLicensing

    var body: some View {
        switch licensing.status {
        case .valid(let license):
            Text("Licensed to \(license.name)")
        case .gracePeriod(let license):
            Text("License expired — grace period until \(license.expiresAt!)")
        case .invalid:
            Text("License invalid")
        case .unknown:
            Text("No license")
        }
    }
}

// Deactivate
try await licensing.deactivate()
```

## Configuration

```swift
let licensing = try AmoreLicensing(
    publicKey: "your-key",
    configuration: LicensingConfiguration(
        gracePeriod: .days(7),            // How long to allow usage after token expiry
        validationFrequency: .weekly      // How often to re-validate with the server
    )
)
```

When using `ValidationFrequency.manual`, call `licensing.validate()` yourself. All other frequencies trigger automatic background validation.

## Entitlements

Licenses can carry entitlements for feature gating:

```swift
// Using string literals
extension License.Entitlement {
    static let pro: Self = "pro"
    static let teams: Self = "teams"
}

if case .valid(let license) = licensing.status {
    if license.validate(entitlement: .pro) {
        // Unlock pro features
    }
}
```

Or define a typed enum:

```swift
enum AppEntitlement: String, EntitlementProtocol {
    case pro, teams
}

license.validate(entitlement: AppEntitlement.pro)
```
