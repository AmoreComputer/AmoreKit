import Foundation

/// Configuration pointing to a licensing server and its API paths.
public struct LicenseServer: Sendable {
    /// The base URL of the licensing server.
    public let url: URL
    /// The path for license activation requests.
    public let activatePath: String
    /// The path for license deactivation requests.
    public let deactivatePath: String
    /// The path for license validation requests.
    public let validatePath: String

    /// Creates a license server configuration with custom paths.
    public init(url: URL, activatePath: String, deactivatePath: String, validatePath: String) {
        self.url = url
        self.activatePath = activatePath
        self.deactivatePath = deactivatePath
        self.validatePath = validatePath
    }

    /// Creates a server configuration using the default Amore API paths for the given bundle identifier.
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
