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
        validationFrequency: .weekly      // Staleness threshold before validate() refreshes from the server
    )
)
```

AmoreLicensing validates once at launch (for every frequency except `.manual`). It does **not** run a background timer: `ValidationFrequency` is the staleness threshold that decides whether a `validate()` call refreshes from the server or just verifies the cached token locally. To keep a long-running app fresh, call `licensing.validate()` from your own lifecycle, e.g. when the window comes to the foreground:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .active { Task { try? await licensing.validate() } }
}
```

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
