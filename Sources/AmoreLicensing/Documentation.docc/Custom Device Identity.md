# Custom Device Identity

Bind a license to a device on platforms without a built-in identity.

## Overview

AmoreLicensing binds each license to the device it was activated on, identifying that device through a ``DeviceIdentity``. On macOS this is automatic: the ``AmoreLicensing`` initializer that takes no `deviceIdentity` uses a built-in implementation backed by the hardware serial number.

On every other platform there is no built-in identity, so you provide your own: conform to ``DeviceIdentity`` and pass it when creating ``AmoreLicensing``.

## Conforming to DeviceIdentity

``DeviceIdentity`` has two requirements:

- ``DeviceIdentity/identifier``: a stable, machine-unique string the license binds to.
- ``DeviceIdentity/deviceName``: a human-readable name shown in the licensing dashboard.

```swift
import AmoreLicensing

struct MyDeviceIdentity: DeviceIdentity {
    var identifier: String {
        // A stable, machine-unique id for this install.
    }

    var deviceName: String {
        // A human-readable name, for example the host name.
    }
}
```

## Injecting your identity

Pass your conformance through the `deviceIdentity` parameter. This initializer is available on every platform:

```swift
let licensing = try AmoreLicensing(
    publicKey: "sa92JNtsaYefYp0MIWQbKu1hpS9bSN89ta7b8mlPbI8=",
    deviceIdentity: MyDeviceIdentity()
)
```

On macOS you can use this initializer too, to override the built-in identity.

## Choosing an identifier

``DeviceIdentity/identifier`` is the value the license is bound to, so it must be:

- **Stable**: constant for the lifetime of the install. If it changes, the bound license stops validating and the user has to re-activate.
- **Unique**: distinct per device, so a license cannot be shared across machines.

On Linux, for example, you might read `/etc/machine-id`:

```swift
import Foundation

struct LinuxDeviceIdentity: DeviceIdentity {
    var deviceName: String { ProcessInfo.processInfo.hostName }

    var identifier: String {
        (try? String(contentsOfFile: "/etc/machine-id", encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
    }
}
```

> Important: Avoid values that change across reboots, OS updates, or network changes (such as IP addresses or dynamic host names), or licenses will repeatedly invalidate.
