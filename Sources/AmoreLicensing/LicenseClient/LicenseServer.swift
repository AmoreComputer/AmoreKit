import Foundation

/// Configuration pointing to a licensing server and its API endpoints.
public struct LicenseServer: Sendable {
    /// The URL for license activation requests.
    public let activateURL: URL
    /// The URL for license deactivation requests.
    public let deactivateURL: URL
    /// The URL for license validation requests.
    public let validateURL: URL
    
    /// Creates a license server configuration with explicit endpoint URLs.
    public init(activateURL: URL, deactivateURL: URL, validateURL: URL) {
        self.activateURL = activateURL
        self.deactivateURL = deactivateURL
        self.validateURL = validateURL
    }
    
    /// Creates a license server configuration with a base URL and custom paths.
    public init(baseURL: URL, activatePath: String, deactivatePath: String, validatePath: String) {
        self.activateURL = baseURL.appendingPathComponent(activatePath)
        self.deactivateURL = baseURL.appendingPathComponent(deactivatePath)
        self.validateURL = baseURL.appendingPathComponent(validatePath)
    }
    
    /// Creates a server configuration using the default Amore API paths for the given bundle identifier.
    public static func amore(for bundleIdentifier: String, baseURL: URL = .amoreServer) -> LicenseServer {
        let base = "v1/apps/\(bundleIdentifier)/licenses"
        return LicenseServer(
            baseURL: baseURL,
            activatePath: "\(base)/activate",
            deactivatePath: "\(base)/deactivate",
            validatePath: "\(base)/validate"
        )
    }
}
