@testable import AmoreLicensing

struct MockDeviceIdentity: DeviceIdentity {
    var deviceName: String = "Test Device"
    let identifier: String
}
