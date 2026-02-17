import Testing
import Foundation

@testable import AmoreLicensing

@Suite
struct EntitlementTests {
    
    @Test
    func `Correctly encodes License.Entitlement`() throws {
        let entitlement: License.Entitlement = "test"
        
        let data = try JSONEncoder().encode(entitlement)
        let string = String(decoding: data, as: UTF8.self)
        #expect(string == "\"test\"")
        
        let decodedEntitlement = try JSONDecoder().decode(License.Entitlement.self, from: data)
        #expect(entitlement == decodedEntitlement)
    }
    
    @Test
    func `Entitlements are Equatable`() async throws {
        let a: License.Entitlement = "a"
        let b: License.Entitlement = "b"
        let c: License.Entitlement = "c"
        
        let entitlements = [a, b]
        
        #expect(entitlements.contains(a))
        #expect(entitlements.contains(b))
        #expect(!entitlements.contains(c))
    }
    
    public enum AppEntitlement: String, EntitlementProtocol {
        case a
        case b
    }
    
    @Test
    func `Use EntitlementProtocol Enum`() {
        let license = License(id: UUID(), name: "Amore", entitlements: ["a"])
        #expect(license.validate(entitlement: AppEntitlement.a))
        #expect(!license.validate(entitlement: AppEntitlement.b))
    }
    
    @Test
    func `Use License.Entitlement extension`() {
        let license = License(id: UUID(), name: "Amore", entitlements: [.dmg])
        #expect(license.validate(entitlement: .dmg))
        #expect(!license.validate(entitlement: .s3))
    }
    
}

extension License.Entitlement {
    
    static let dmg: Self = "dmg"
    static let s3: Self = "s3"
    
}
