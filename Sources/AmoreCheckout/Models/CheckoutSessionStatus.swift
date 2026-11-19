import struct AmoreStore.Price
import Foundation

/// Where a checkout session stands, as reported by the licensing server.
enum CheckoutSessionStatus: String, Codable, Sendable {
    case open
    case processing
    case complete
    case expired
}

/// Status poll response; `licenseKey` is present only once a license was issued.
struct CheckoutSessionStatusResponse: Codable, Equatable, Sendable {
    var status: CheckoutSessionStatus
    var licenseKey: String?
    /// The total of the completed checkout, sent only with `licenseKey`.
    var amountPaid: Price?
}
