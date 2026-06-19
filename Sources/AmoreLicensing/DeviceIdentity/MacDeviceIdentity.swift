#if os(macOS)
import Foundation
import IOKit
import SystemConfiguration

struct MacDeviceIdentity: DeviceIdentity {
    var deviceName: String {
        (SCDynamicStoreCopyComputerName(nil, nil) as String?)
        ?? ProcessInfo.processInfo.hostName
    }
    
    var identifier: String {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        defer { IOObjectRelease(service) }
        
        guard let data = IORegistryEntryCreateCFProperty(
            service,
            "IOPlatformSerialNumber" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return "unknown"
        }
        return data
    }
}
#endif
