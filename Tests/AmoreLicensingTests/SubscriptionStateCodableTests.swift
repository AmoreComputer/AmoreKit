@testable import AmoreLicensing
import Foundation
import Testing

@Suite("SubscriptionState Codable (SDK contract)")
struct SubscriptionStateCodableTests {
    
    // Mirror JWTKit's coders: subscription_state only ever travels inside a JWT,
    // whose encoder/decoder use .secondsSince1970 for every Date.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
    
    private func roundTrip(_ value: SubscriptionState) throws -> SubscriptionState {
        let data = try encoder.encode(value)
        return try decoder.decode(SubscriptionState.self, from: data)
    }
    
    private func jsonObject(_ value: SubscriptionState) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    
    @Test func renewingRoundTrips() throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        let value: SubscriptionState = .renewing(renewsAt: date)
        let json = try jsonObject(value)
        #expect(json["state"] as? String == "renewing")
        #expect(json["renews_at"] as? Int == 1_780_000_000)
        #expect(try roundTrip(value) == value)
    }
    
    @Test func cancelingRoundTrips() throws {
        let ends = Date(timeIntervalSince1970: 1_780_000_000)
        let canceled = Date(timeIntervalSince1970: 1_779_000_000)
        let value: SubscriptionState = .canceling(endsAt: ends, canceledAt: canceled)
        let json = try jsonObject(value)
        #expect(json["state"] as? String == "canceling")
        #expect(json["ends_at"] as? Int == 1_780_000_000)
        #expect(json["canceled_at"] as? Int == 1_779_000_000)
        #expect(try roundTrip(value) == value)
    }
    
    @Test func trialingWithoutCancellationOmitsCanceledAt() throws {
        let trialEnd = Date(timeIntervalSince1970: 1_780_000_000)
        let value: SubscriptionState = .trialing(trialEndsAt: trialEnd, canceledAt: nil)
        let json = try jsonObject(value)
        #expect(json["state"] as? String == "trialing")
        #expect(json["trial_ends_at"] as? Int == 1_780_000_000)
        #expect(json["canceled_at"] == nil, "canceled_at must be omitted when nil")
        #expect(try roundTrip(value) == value)
    }
    
    @Test func trialingWithCancellationEncodesCanceledAt() throws {
        let trialEnd = Date(timeIntervalSince1970: 1_780_000_000)
        let canceled = Date(timeIntervalSince1970: 1_779_000_000)
        let value: SubscriptionState = .trialing(trialEndsAt: trialEnd, canceledAt: canceled)
        let json = try jsonObject(value)
        #expect(json["canceled_at"] as? Int == 1_779_000_000)
        #expect(try roundTrip(value) == value)
    }
    
    @Test func pastDueRoundTrips() throws {
        let grace = Date(timeIntervalSince1970: 1_780_000_000)
        let value: SubscriptionState = .pastDue(gracePeriodEndsAt: grace)
        let json = try jsonObject(value)
        #expect(json["state"] as? String == "past_due")
        #expect(json["grace_period_ends_at"] as? Int == 1_780_000_000)
        #expect(try roundTrip(value) == value)
    }
    
    @Test func pausedRoundTripsWithNoExtraKeys() throws {
        let value: SubscriptionState = .paused
        let json = try jsonObject(value)
        #expect(json["state"] as? String == "paused")
        #expect(json.count == 1)
        #expect(try roundTrip(value) == value)
    }
    
    @Test func lapsedRoundTripsWithNoExtraKeys() throws {
        let value: SubscriptionState = .lapsed
        let json = try jsonObject(value)
        #expect(json["state"] as? String == "lapsed")
        #expect(json.count == 1)
        #expect(try roundTrip(value) == value)
    }
    
    @Test func unknownStateRejected() {
        let json = Data(#"{"state":"flapping"}"#.utf8)
        #expect(throws: DecodingError.self) {
            _ = try self.decoder.decode(SubscriptionState.self, from: json)
        }
    }
    
    @Test func decodesServerEncodedRenewingFixture() throws {
        // Byte-for-byte fixture that the server emits; must decode here.
        let json = Data(#"{"state":"renewing","renews_at":1780272000}"#.utf8)
        let decoded = try decoder.decode(SubscriptionState.self, from: json)
        guard case .renewing(let date) = decoded else {
            Issue.record("Expected .renewing, got \(decoded)")
            return
        }
        #expect(date == Date(timeIntervalSince1970: 1_780_272_000))
    }
    
    @Test func decodesServerEncodedTrialingNullCanceledAtFixture() throws {
        let json = Data(#"{"state":"trialing","trial_ends_at":1780272000,"canceled_at":null}"#.utf8)
        let decoded = try decoder.decode(SubscriptionState.self, from: json)
        guard case .trialing(_, let canceledAt) = decoded else {
            Issue.record("Expected .trialing, got \(decoded)")
            return
        }
        #expect(canceledAt == nil)
    }
}
