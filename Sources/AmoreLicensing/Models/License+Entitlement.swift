/// A type that represents a license entitlement backed by a raw string value.
///
/// Conform a `String`-backed enum to this protocol for compile-time safety:
///
/// ```swift
/// enum AppEntitlement: String, EntitlementProtocol {
///     case pro, teams
/// }
/// ```
public protocol EntitlementProtocol: Hashable, Sendable, Codable, RawRepresentable where RawValue == String {}

extension EntitlementProtocol {
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
}

public extension License {
    
    /// A lightweight entitlement value that can be created from string literals.
    ///
    /// Define static constants for easy reuse:
    ///
    /// ```swift
    /// extension License.Entitlement {
    ///     static let pro: Self = "pro"
    /// }
    /// ```
    struct Entitlement: EntitlementProtocol, ExpressibleByStringLiteral {

        /// The underlying string identifier for this entitlement.
        public var rawValue: String
        
        public init?(rawValue: String) {
            self.rawValue = rawValue
        }
        
        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self.rawValue = value
        }
        
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
        
        public init(stringLiteral: String) {
            self.init(rawValue: stringLiteral)!
        }
        
    }
    
}

extension License {
    
    /// Returns whether this license contains the given entitlement.
    public func validate(entitlement: Entitlement) -> Bool {
        entitlements.contains { $0.rawValue == entitlement.rawValue }
    }

    /// Returns whether this license contains the given custom entitlement type.
    public func validate<Value: EntitlementProtocol>(entitlement: Value) -> Bool {
        entitlements.contains { $0.rawValue == entitlement.rawValue }
    }
    
}
