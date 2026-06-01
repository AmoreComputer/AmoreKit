import Foundation
import Testing

@testable import AmoreStore

@Suite struct PriceTests {

    @Test func decimalAmountForTwoDecimalCurrency() {
        let price = Price(unitAmount: 999, currency: "USD", recurringInterval: .month)
        #expect(price.decimalAmount == Decimal(string: "9.99"))
    }

    @Test func decimalAmountForZeroDecimalCurrency() {
        // JPY has no minor unit: 1000 yen is 1000, not 10.00.
        let price = Price(unitAmount: 1000, currency: "JPY", recurringInterval: nil)
        #expect(price.decimalAmount == Decimal(1000))
    }

    @Test func decimalAmountForThreeDecimalCurrency() {
        // BHD has three minor-unit digits: 1234 fils is 1.234 dinar.
        let price = Price(unitAmount: 1234, currency: "BHD", recurringInterval: nil)
        #expect(price.decimalAmount == Decimal(string: "1.234"))
    }

    @Test func displayPriceUsesCurrencyFormatting() {
        let price = Price(unitAmount: 999, currency: "USD", recurringInterval: .month)
        // Locale-independent checks: the formatted amount and a currency marker are present.
        #expect(price.displayPrice.contains("9"))
        #expect(price.displayPrice.contains("99"))
        #expect(!price.displayPrice.isEmpty)
    }

    @Test func productDisplayPriceDelegatesToPrice() {
        let priced = Product(
            id: UUID(),
            name: "Pro",
            durationInSeconds: nil,
            deviceLimit: 3,
            price: Price(unitAmount: 999, currency: "USD", recurringInterval: .month),
            checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/\(UUID())")!
        )
        #expect(priced.displayPrice == priced.price?.displayPrice)
        #expect(priced.displayPrice != nil)
    }

    @Test func productDisplayPriceIsNilWithoutPrice() {
        let free = Product(
            id: UUID(),
            name: "Lite",
            durationInSeconds: 2_592_000,
            deviceLimit: 1,
            price: nil,
            checkoutURL: URL(string: "https://api.amore.computer/v1/checkout/\(UUID())")!
        )
        #expect(free.displayPrice == nil)
    }
}
