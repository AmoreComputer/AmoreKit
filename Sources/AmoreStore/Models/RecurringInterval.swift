/// Billing intervals supported by Stripe recurring prices.
public enum RecurringInterval: String, Hashable, Codable, Sendable {
    case day
    case week
    case month
    case year
}
