#if DEBUG
import AmoreLicensing
import struct AmoreStore.Price
import struct AmoreStore.Product
import Foundation

extension Product {
    /// A subscription product for previews.
    static let preview = Product(
        id: UUID(uuidString: "2B9F0C51-7A64-4E0B-9C3D-6F1A8E5D2C47")!,
        name: "Acme Pro",
        durationInSeconds: nil,
        deviceLimit: 3,
        price: Price(unitAmount: 4900, currency: "USD", recurringInterval: .year),
        checkoutURL: URL(string: "https://checkout.stripe.com/c/pay/preview")!
    )
}

extension License {
    /// An active subscription license for previews.
    ///
    /// Decoded rather than initialized: `License`'s memberwise initializer is
    /// internal to `AmoreLicensing`, so `Codable` is the only way in from here.
    static let preview: License = {
        let renewsAt = Date(timeIntervalSinceNow: 60 * 60 * 24 * 365)
        let json = """
        {
          "id": "3A17E7E8-7B5C-4E9D-9E4A-0B2C1D3E4F50",
          "product": { "name": "Acme Pro", "identifier": "pro" },
          "entitlements": ["pro"],
          "customer": { "email": "grace@example.com" },
          "subscriptionState": {
            "state": "renewing",
            "renews_at": \(renewsAt.timeIntervalSinceReferenceDate)
          }
        }
        """
        return try! JSONDecoder().decode(License.self, from: Data(json.utf8))
    }()
}
#endif
