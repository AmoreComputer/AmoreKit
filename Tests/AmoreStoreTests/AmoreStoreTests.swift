import Foundation
import Testing

@testable import AmoreStore

@Suite struct AmoreStoreTests {
    private let bundleId = "com.test.amorekit"
    
    private func makeStore(client: MockProductsClient = MockProductsClient()) -> (AmoreStore, MockProductsClient) {
        (AmoreStore(bundleIdentifier: bundleId, productsClient: client), client)
    }
    
    @Test func returnsParsedProducts() async throws {
        let (store, mock) = makeStore()
        let expected = Product(
            id: UUID(),
            name: "Pro",
            durationInSeconds: nil,
            deviceLimit: 3,
            price: Price(unitAmount: 999, currency: "usd", recurringInterval: .month),
            checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/\(UUID())")!
        )
        mock.onFetch = { id in
            #expect(id == "com.test.amorekit")
            return [expected]
        }
        
        let result = try await store.products()
        
        #expect(result == [expected])
        #expect(result.first?.checkoutURL == expected.checkoutURL)
    }
    
    @Test func mapsClientErrorOnProducts() async throws {
        let (store, mock) = makeStore()
        mock.onFetch = { _ in throw StoreError.appNotFound }
        
        await #expect(throws: StoreError.appNotFound) {
            try await store.products()
        }
    }
    
    @Test func wrapsUnknownErrorOnProducts() async throws {
        let (store, mock) = makeStore()
        mock.onFetch = { _ in throw URLError(.notConnectedToInternet) }
        
        await #expect(throws: StoreError.self) {
            try await store.products()
        }
    }
    
    @Test func decodesServerJSON() throws {
        let json = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "name": "Pro",
            "durationInSeconds": null,
            "deviceLimit": 3,
            "price": { "unitAmount": 999, "currency": "usd", "recurringInterval": "month" },
            "checkoutURL": "https://api.amore.computer/v1/checkout/11111111-1111-1111-1111-111111111111"
          },
          {
            "id": "22222222-2222-2222-2222-222222222222",
            "name": "Lite",
            "durationInSeconds": 2592000,
            "deviceLimit": 1,
            "price": null,
            "checkoutURL": "https://api.amore.computer/v1/checkout/22222222-2222-2222-2222-222222222222"
          }
        ]
        """
        let decoded = try JSONDecoder().decode([Product].self, from: Data(json.utf8))
        
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "Pro")
        #expect(decoded[0].price?.unitAmount == 999)
        #expect(decoded[0].price?.recurringInterval == .month)
        #expect(decoded[0].checkoutURL == URL(string: "https://api.amore.computer/v1/checkout/11111111-1111-1111-1111-111111111111"))
        #expect(decoded[1].name == "Lite")
        #expect(decoded[1].price == nil)
        #expect(decoded[1].durationInSeconds == 2_592_000)
        #expect(decoded[1].checkoutURL == URL(string: "https://api.amore.computer/v1/checkout/22222222-2222-2222-2222-222222222222"))
    }
}
