import AmoreJWT
import Crypto
import Foundation
import JWTKit
import Testing

/// Proves that tokens produced by JWTKit (what the server uses to sign)
/// decode correctly with the AmoreJWT parser shipped to clients. Catches
/// any drift in wire format (header bytes, base64url, claim shape)
/// between the two libraries.
@Suite("JWTKit ↔ AmoreJWT wire contract")
struct JWTKitContractTests {
    
    struct ContractPayload: JWTPayload, Codable, Equatable {
        var exp: ExpirationClaim
        var iat: IssuedAtClaim
        var sub: String
        
        func verify(using algorithm: some JWTAlgorithm) throws {}
        
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.sub == rhs.sub
            && abs(lhs.exp.value.timeIntervalSince(rhs.exp.value)) < 1
            && abs(lhs.iat.value.timeIntervalSince(rhs.iat.value)) < 1
        }
    }
    
    struct Decoded: Decodable, Equatable {
        var exp: Date
        var iat: Date
        var sub: String
    }
    
    @Test func jwtKitSignedTokenVerifiesWithAmoreJWT() async throws {
        let amoreKey = Curve25519.Signing.PrivateKey()
        let jwtKitKey = EdDSA.PrivateKey(backing: amoreKey)
        
        let exp = Date().addingTimeInterval(3600)
        let iat = Date()
        let payload = ContractPayload(
            exp: .init(value: exp),
            iat: .init(value: iat),
            sub: "user-42"
        )
        let keys = await JWTKeyCollection().add(eddsa: jwtKitKey)
        let token = try await keys.sign(payload)
        
        let decoded = try EdDSAJWT.verify(token, as: Decoded.self, using: amoreKey.publicKey)
        
        #expect(decoded.sub == "user-42")
        #expect(abs(decoded.exp.timeIntervalSince(exp)) < 1)
        #expect(abs(decoded.iat.timeIntervalSince(iat)) < 1)
    }
    
    @Test func rejectsJWTKitTokenSignedWithNonEdDSAAlgorithm() async throws {
        struct HMACPayload: JWTPayload {
            var sub: String
            func verify(using algorithm: some JWTAlgorithm) throws {}
        }
        let amoreKey = Curve25519.Signing.PrivateKey()
        let keys = await JWTKeyCollection().add(hmac: "secret", digestAlgorithm: .sha256)
        let token = try await keys.sign(HMACPayload(sub: "user-42"))
        
        #expect(throws: EdDSAJWTError.unsupportedAlgorithm("HS256")) {
            try EdDSAJWT.verify(token, as: HMACPayload.self, using: amoreKey.publicKey)
        }
    }
    
    @Test func amoreJWTSignedTokenVerifiesWithJWTKit() async throws {
        let amoreKey = Curve25519.Signing.PrivateKey()
        let jwtKitKey = EdDSA.PrivateKey(backing: amoreKey)
        
        let exp = Date().addingTimeInterval(3600)
        let iat = Date()
        let payload = ContractPayload(
            exp: .init(value: exp),
            iat: .init(value: iat),
            sub: "user-42"
        )
        let token = try EdDSAJWT.sign(payload, using: amoreKey)
        
        let keys = await JWTKeyCollection().add(eddsa: jwtKitKey)
        let decoded = try await keys.verify(token, as: ContractPayload.self)
        
        #expect(decoded.sub == "user-42")
        #expect(abs(decoded.exp.value.timeIntervalSince(exp)) < 1)
        #expect(abs(decoded.iat.value.timeIntervalSince(iat)) < 1)
    }
}
