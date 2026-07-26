import Crypto
import Foundation

/// Identifies the device a license is bound to.
///
/// AmoreLicensing ships a built-in implementation for macOS. On every other
/// platform, provide your own conformance and inject it when creating an
/// ``AmoreLicensing`` instance.
public protocol DeviceIdentity: Sendable {
    /// A human-readable name for this device, sent to the server on activation so
    /// the device can be recognised in the licensing dashboard.
    var deviceName: String { get }
    
    /// A stable, machine-unique identifier used to bind a license to this device.
    ///
    /// Return the raw, stable value; AmoreLicensing hashes it (salted with the
    /// app's bundle identifier) before it leaves the device, so the raw value is
    /// never sent to the server.
    ///
    /// This value must stay constant for the lifetime of the install: if it
    /// changes, the bound license stops validating and a re-activation is required.
    var identifier: String { get }
}

extension DeviceIdentity {
    /// The identifier as it leaves the device: an HMAC-SHA256 of ``identifier``
    /// keyed with `salt` (the app's bundle identifier), so the raw value never
    /// reaches the server and the same device yields a different ID per app.
    func hashedIdentifier(salt: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(identifier.utf8),
            using: SymmetricKey(data: Data(salt.utf8))
        )
        return "h1:" + Data(mac).base64EncodedString()
    }
}
