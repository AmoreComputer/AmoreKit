public protocol EntitlementProtocol: Hashable, Sendable, Codable, RawRepresentable where RawValue == String {}

extension EntitlementProtocol {
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
}

public extension License {
    
    struct Entitlement: EntitlementProtocol, ExpressibleByStringLiteral {
        
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
    
    public func validate(entitlement: Entitlement) -> Bool {
        entitlements.contains { $0.rawValue == entitlement.rawValue }
    }
    
    public func validate<Value: EntitlementProtocol>(entitlement: Value) -> Bool {
        entitlements.contains { $0.rawValue == entitlement.rawValue }
    }
    
}
