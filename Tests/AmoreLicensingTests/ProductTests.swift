import Foundation
import Testing

@testable import AmoreLicensing

@Suite struct ProductTests {
    
    @Test func encodesToIdNameIdentifierKeys() throws {
        let product = Product(name: "Amore", identifier: "pro")
        let data = try JSONEncoder().encode(product)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        
        #expect(json.keys.sorted() == ["identifier", "name"])
        #expect(json["name"] as? String == "Amore")
        #expect(json["identifier"] as? String == "pro")
    }
    
    @Test func decodesFromV2ProductClaimJSON() throws {
        let jsonString = #"{"name":"Amore","identifier":"pro"}"#
        let product = try JSONDecoder().decode(Product.self, from: Data(jsonString.utf8))
        
        #expect(product.name == "Amore")
        #expect(product.identifier == "pro")
    }
}
