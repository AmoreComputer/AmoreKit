import Foundation

/// Pricing information for a product as configured in Stripe.
public struct Price: Hashable, Codable, Sendable {
    /// Amount in the smallest unit of `currency` (e.g. cents for USD, yen for JPY).
    public var unitAmount: Int
    /// ISO 4217 currency code (e.g. `"USD"`).
    public var currency: String
    /// Billing interval for recurring prices, or `nil` for one-time purchases.
    public var recurringInterval: RecurringInterval?
    
    public init(unitAmount: Int, currency: String, recurringInterval: RecurringInterval?) {
        self.unitAmount = unitAmount
        self.currency = currency
        self.recurringInterval = recurringInterval
    }
}

extension Price {
    
    /// The decimal representation of the cost of the product in ``currency``.
    public var decimalAmount: Decimal {
        Decimal(unitAmount) / pow(Decimal(10), Self.fractionDigits(for: currency))
    }
    
    /// The localized string representation of the product price, suitable for display.
    public var displayPrice: String {
        decimalAmount.formatted(.currency(code: currency))
    }
    
    /// Minor-unit exponent for `currency` (2 for USD, 0 for JPY, 3 for BHD),
    private static func fractionDigits(for currency: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.maximumFractionDigits
    }
    
}

extension Price: CustomStringConvertible {
    
    public var description: String {
        displayPrice
    }
    
}
