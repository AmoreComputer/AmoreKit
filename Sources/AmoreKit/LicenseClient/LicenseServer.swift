import Foundation

public struct LicenseServer: Sendable {
    public let url: URL
    public let activatePath: String
    public let deactivatePath: String
    public let validatePath: String

    public init(url: URL, activatePath: String, deactivatePath: String, validatePath: String) {
        self.url = url
        self.activatePath = activatePath
        self.deactivatePath = deactivatePath
        self.validatePath = validatePath
    }

    public static func amore(bundleIdentifier: String) -> LicenseServer {
        let base = "v1/apps/\(bundleIdentifier)/licenses"
        return LicenseServer(
            url: .amoreServer,
            activatePath: "\(base)/activate",
            deactivatePath: "\(base)/deactivate",
            validatePath: "\(base)/validate"
        )
    }
}
