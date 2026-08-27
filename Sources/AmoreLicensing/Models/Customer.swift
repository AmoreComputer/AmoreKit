import Foundation

/// Identity of the customer a ``License`` was issued to.
public struct Customer: Hashable, Codable, Sendable {
    /// The email address the license was issued to, or `nil` if the issuing
    /// token carries a customer without an email.
    public var email: String?
    /// The customer's name, or `nil` if the issuing token carries a customer
    /// without a name.
    public var name: String?
}
