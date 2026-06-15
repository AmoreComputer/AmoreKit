@testable import AmoreLicensing
import Foundation
import JWTKit
import Testing

@Suite("LicensePayload decode")
struct LicensePayloadDecodeTests {
    
    // Mirror JWTKit: payloads are decoded with .secondsSince1970, so every
    // embedded Date (iat/exp and subscription_state) reads as epoch seconds.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
    
    private func decodePayload(_ json: String) throws -> LicensePayload {
        try decoder.decode(LicensePayload.self, from: Data(json.utf8))
    }
    
    @Test func decodesPayloadWithRenewingSubscriptionState() throws {
        let json = """
        {
          "exp": 1800000000,
          "iat": 1779000000,
          "hardware_id": "hw-1",
          "license_id": "C7B53B0E-2C18-4F1D-8C9B-2B7B6A8B6A7E",
          "nonce": "n-1",
          "product": { "name": "Pro", "identifier": "pro" },
          "entitlements": [],
          "subscription_state": { "state": "renewing", "renews_at": 1780272000 }
        }
        """
        let payload = try decodePayload(json)
        guard case .renewing(let renewsAt) = payload.subscriptionState else {
            Issue.record("Expected .renewing, got \(String(describing: payload.subscriptionState))")
            return
        }
        #expect(renewsAt == Date(timeIntervalSince1970: 1_780_272_000))
    }
    
    @Test func decodesPayloadWithoutSubscriptionState() throws {
        let json = """
        {
          "exp": 1800000000,
          "iat": 1779000000,
          "hardware_id": "hw-1",
          "license_id": "C7B53B0E-2C18-4F1D-8C9B-2B7B6A8B6A7E",
          "nonce": "n-1",
          "product": { "name": "Pro", "identifier": "pro" },
          "entitlements": []
        }
        """
        let payload = try decodePayload(json)
        #expect(payload.subscriptionState == nil)
    }
    
    @Test func decodesPayloadWithPausedSubscriptionState() throws {
        let json = """
        {
          "exp": 1800000000,
          "iat": 1779000000,
          "hardware_id": "hw-1",
          "license_id": "C7B53B0E-2C18-4F1D-8C9B-2B7B6A8B6A7E",
          "nonce": "n-1",
          "product": { "name": "Pro", "identifier": "pro" },
          "entitlements": [],
          "subscription_state": { "state": "paused" }
        }
        """
        let payload = try decodePayload(json)
        #expect(payload.subscriptionState == .paused)
    }
    
    @Test func licenseFromPayloadCarriesSubscriptionState() throws {
        let json = """
        {
          "exp": 1800000000,
          "iat": 1779000000,
          "hardware_id": "hw-1",
          "license_id": "C7B53B0E-2C18-4F1D-8C9B-2B7B6A8B6A7E",
          "nonce": "n-1",
          "product": { "name": "Pro", "identifier": "pro" },
          "entitlements": [],
          "subscription_state": { "state": "lapsed" }
        }
        """
        let payload = try decodePayload(json)
        let license = License(from: payload)
        #expect(license.subscriptionState == .lapsed)
    }

    @Test func licenseFromPayloadCarriesCustomer() throws {
        let json = """
        {
          "exp": 1800000000,
          "iat": 1779000000,
          "hardware_id": "hw-1",
          "license_id": "C7B53B0E-2C18-4F1D-8C9B-2B7B6A8B6A7E",
          "nonce": "n-1",
          "product": { "name": "Pro", "identifier": "pro" },
          "entitlements": [],
          "customer": { "email": "buyer@example.com" }
        }
        """
        let payload = try decodePayload(json)
        let license = License(from: payload)
        #expect(license.customer?.email == "buyer@example.com")
    }

    // An older token (or any license issued without an email) has no `customer`
    // claim; the optional must decode to nil, not error.
    @Test func licenseHasNilCustomerWhenClaimAbsent() throws {
        let json = """
        {
          "exp": 1800000000,
          "iat": 1779000000,
          "hardware_id": "hw-1",
          "license_id": "C7B53B0E-2C18-4F1D-8C9B-2B7B6A8B6A7E",
          "nonce": "n-1",
          "product": { "name": "Pro", "identifier": "pro" },
          "entitlements": []
        }
        """
        let payload = try decodePayload(json)
        let license = License(from: payload)
        #expect(license.customer == nil)
    }
}
