import Foundation

/// Identity of the product a ``License`` belongs to.
public struct Product: Hashable, Codable, Sendable {
    /// Human-readable product name.
    public var name: String
    /// Stable, human-readable slug, unique per app. Used for code-level product matching.
    public var identifier: String
}

extension Product: Identifiable {
    
    public var id: String { identifier }
    
}
