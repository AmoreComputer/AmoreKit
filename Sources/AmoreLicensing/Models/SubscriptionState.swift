import Foundation

/// State of a subscription that backs a ``License``.
///
/// Returned inside ``License/subscriptionState``. `nil` indicates a perpetual
/// or one-time-purchase license with no subscription.
public enum SubscriptionState: Sendable, Hashable {
    /// Auto-renews on `renewsAt`. Happy path.
    case renewing(renewsAt: Date)
    
    /// Cancellation scheduled. Access works until `endsAt`.
    case canceling(endsAt: Date, canceledAt: Date)
    
    /// In trial. Converts to paid on `trialEndsAt` unless `canceledAt != nil`,
    /// in which case access stops at `trialEndsAt` with no charge.
    case trialing(trialEndsAt: Date, canceledAt: Date?)
    
    /// Payment failed, Stripe retrying. Access typically allowed
    /// until `gracePeriodEndsAt`.
    case pastDue(gracePeriodEndsAt: Date)
    
    /// Subscription paused.
    case paused
    
    /// Terminal: canceled, unpaid, expired, or any unrecoverable state.
    case lapsed
    
}

extension SubscriptionState: Codable {
    
    private enum CodingKeys: String, CodingKey {
        case state
        case renewsAt = "renews_at"
        case endsAt = "ends_at"
        case canceledAt = "canceled_at"
        case trialEndsAt = "trial_ends_at"
        case gracePeriodEndsAt = "grace_period_ends_at"
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .renewing(let renewsAt):
            try container.encode("renewing", forKey: .state)
            try container.encode(renewsAt, forKey: .renewsAt)
        case .canceling(let endsAt, let canceledAt):
            try container.encode("canceling", forKey: .state)
            try container.encode(endsAt, forKey: .endsAt)
            try container.encode(canceledAt, forKey: .canceledAt)
        case .trialing(let trialEndsAt, let canceledAt):
            try container.encode("trialing", forKey: .state)
            try container.encode(trialEndsAt, forKey: .trialEndsAt)
            try container.encodeIfPresent(canceledAt, forKey: .canceledAt)
        case .pastDue(let gracePeriodEndsAt):
            try container.encode("past_due", forKey: .state)
            try container.encode(gracePeriodEndsAt, forKey: .gracePeriodEndsAt)
        case .paused:
            try container.encode("paused", forKey: .state)
        case .lapsed:
            try container.encode("lapsed", forKey: .state)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let state = try container.decode(String.self, forKey: .state)
        switch state {
        case "renewing":
            self = .renewing(renewsAt: try container.decode(Date.self, forKey: .renewsAt))
        case "canceling":
            self = .canceling(
                endsAt: try container.decode(Date.self, forKey: .endsAt),
                canceledAt: try container.decode(Date.self, forKey: .canceledAt)
            )
        case "trialing":
            self = .trialing(
                trialEndsAt: try container.decode(Date.self, forKey: .trialEndsAt),
                canceledAt: try container.decodeIfPresent(Date.self, forKey: .canceledAt)
            )
        case "past_due":
            self = .pastDue(gracePeriodEndsAt: try container.decode(Date.self, forKey: .gracePeriodEndsAt))
        case "paused":
            self = .paused
        case "lapsed":
            self = .lapsed
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .state, in: container,
                debugDescription: "Unknown subscription state: \(state)"
            )
        }
    }
    
}
