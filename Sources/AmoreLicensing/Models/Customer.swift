import Foundation

/// Identity of the customer a ``License`` was issued to.
public struct Customer: Hashable, Codable, Sendable {
    /// The email address the license was issued to.
    public var email: String
}
