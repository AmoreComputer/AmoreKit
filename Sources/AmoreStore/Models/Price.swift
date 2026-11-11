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
    
    /// Minor-unit exponent Stripe uses for `currency` (2 for USD, 0 for JPY, 3 for BHD).
    /// Stripe counts some currencies in hundredths that Foundation gives no
    /// minor unit (ISK, UGX, HUF), so Foundation's currency metadata does not apply.
    private static func fractionDigits(for currency: String) -> Int {
        switch currency.uppercased() {
        case "BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "VND", "VUV", "XAF", "XOF", "XPF": 0
        case "BHD", "JOD", "KWD", "OMR", "TND": 3
        default: 2
        }
    }
    
}

extension Price: CustomStringConvertible {
    
    public var description: String {
        displayPrice
    }
    
}
