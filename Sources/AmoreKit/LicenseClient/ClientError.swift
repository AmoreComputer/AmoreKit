import Foundation

public enum ClientError: String, LocalizedError, Sendable, Decodable {
    case activationNotFound
    case appNotFound
    case deviceLimitReached
    case deviceNotActivated
    case invalidBundleIdentifier
    case invalidLicenseToken
    case licenseExpired
    case licenseNotFound
    case licensingNotConfigured
    case productNotFound
    
    public var errorDescription: String? {
        switch self {
        case .activationNotFound: "Activation not found."
        case .appNotFound: "App not found."
        case .deviceLimitReached: "Device limit reached."
        case .deviceNotActivated: "Device is not activated."
        case .invalidBundleIdentifier: "Invalid bundle identifier."
        case .invalidLicenseToken: "Invalid license token."
        case .licenseExpired: "License has expired."
        case .licenseNotFound: "License not found."
        case .licensingNotConfigured: "Licensing is not configured."
        case .productNotFound: "Product not found."
        }
    }
}
