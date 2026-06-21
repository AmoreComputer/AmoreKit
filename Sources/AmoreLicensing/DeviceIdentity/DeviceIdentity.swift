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
    /// This value must stay constant for the lifetime of the install: if it
    /// changes, the bound license stops validating and a re-activation is required.
    var identifier: String { get }
}
