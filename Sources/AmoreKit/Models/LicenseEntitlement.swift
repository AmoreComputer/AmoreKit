public struct LicenseEntitlement: Hashable, Codable, RawRepresentable, ExpressibleByStringLiteral, Sendable {
    
    public var rawValue: String
    
    public init?(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(stringLiteral: String) {
        self.init(rawValue: stringLiteral)!
    }
    
}
