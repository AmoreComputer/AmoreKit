import AmoreJWT
import Crypto
import Foundation
import Testing

@Suite("EdDSAJWT")
struct EdDSAJWTTests {
    
    struct Sample: Codable, Equatable {
        var sub: String
        var iat: Date
        var exp: Date
    }
    
    private let key = Curve25519.Signing.PrivateKey()
    private var publicKey: Curve25519.Signing.PublicKey { key.publicKey }
    
    private func sample() -> Sample {
        let now = floor(Date().timeIntervalSince1970)
        return Sample(
            sub: "user-42",
            iat: Date(timeIntervalSince1970: now - 60),
            exp: Date(timeIntervalSince1970: now + 3600)
        )
    }
    
    @Test func roundTripsPayload() throws {
        let payload = sample()
        let token = try EdDSAJWT.sign(payload, using: key)
        let decoded = try EdDSAJWT.verify(token, as: Sample.self, using: publicKey)
        #expect(decoded == payload)
    }
    
    @Test func rejectsTamperedSignature() throws {
        let token = try EdDSAJWT.sign(sample(), using: key)
        let parts = token.split(separator: ".").map(String.init)
        var sigBytes = parts[2].base64URLDecodedData()!
        sigBytes[0] ^= 0x01
        let tampered = "\(parts[0]).\(parts[1]).\(sigBytes.base64URLEncodedString())"
        
        #expect(throws: EdDSAJWTError.invalidSignature) {
            try EdDSAJWT.verify(tampered, as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsTamperedPayload() throws {
        let token = try EdDSAJWT.sign(sample(), using: key)
        let parts = token.split(separator: ".").map(String.init)
        var payloadBytes = parts[1].base64URLDecodedData()!
        payloadBytes[0] ^= 0x01
        let tampered = "\(parts[0]).\(payloadBytes.base64URLEncodedString()).\(parts[2])"
        
        #expect(throws: EdDSAJWTError.invalidSignature) {
            try EdDSAJWT.verify(tampered, as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsMalformedToken() {
        #expect(throws: EdDSAJWTError.malformedToken) {
            try EdDSAJWT.verify("not.a.valid.jwt", as: Sample.self, using: publicKey)
        }
        #expect(throws: EdDSAJWTError.malformedToken) {
            try EdDSAJWT.verify("only-one-segment", as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsTokenWithEmptyTrailingSegment() {
        // `omittingEmptySubsequences: false` keeps the empty trailing segment, so a
        // trailing dot is four parts and fails the three-part check instead of being
        // read as a valid three-segment token.
        #expect(throws: EdDSAJWTError.malformedToken) {
            try EdDSAJWT.verify("a.b.c.", as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsNonEdDSAAlgorithm() throws {
        let headerJSON = #"{"alg":"none","typ":"JWT"}"#
        let payloadJSON = "{}"
        let header = Data(headerJSON.utf8).base64URLEncodedString()
        let payload = Data(payloadJSON.utf8).base64URLEncodedString()
        let signature = Data().base64URLEncodedString()
        let token = "\(header).\(payload).\(signature)"
        
        #expect(throws: EdDSAJWTError.unsupportedAlgorithm("none")) {
            try EdDSAJWT.verify(token, as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsWrongPublicKey() throws {
        let other = Curve25519.Signing.PrivateKey()
        let token = try EdDSAJWT.sign(sample(), using: key)
        
        #expect(throws: EdDSAJWTError.invalidSignature) {
            try EdDSAJWT.verify(token, as: Sample.self, using: other.publicKey)
        }
    }
    
    @Test func rejectsMalformedBase64URLSegments() {
        #expect(throws: EdDSAJWTError.malformedToken) {
            try EdDSAJWT.verify("***.***.***", as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsValidBase64ButInvalidHeaderJSON() throws {
        let badHeader = Data("not json".utf8).base64URLEncodedString()
        let payload = Data("{}".utf8).base64URLEncodedString()
        let signature = Data().base64URLEncodedString()
        let token = "\(badHeader).\(payload).\(signature)"
        
        #expect(throws: EdDSAJWTError.headerDecodingFailed) {
            try EdDSAJWT.verify(token, as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsPayloadThatDoesNotMatchSchema() throws {
        struct Other: Encodable { let unrelated: Int }
        let token = try EdDSAJWT.sign(Other(unrelated: 1), using: key)
        
        #expect(throws: EdDSAJWTError.payloadDecodingFailed) {
            try EdDSAJWT.verify(token, as: Sample.self, using: publicKey)
        }
    }
    
    @Test func rejectsExpiredPayload() throws {
        struct Expiring: Codable { var exp: Date }
        let token = try EdDSAJWT.sign(
            Expiring(exp: Date().addingTimeInterval(-3600)),
            using: key
        )
        #expect(throws: EdDSAJWTError.expired) {
            try EdDSAJWT.verify(token, as: Expiring.self, using: publicKey)
        }
    }
    
    @Test func rejectsMalformedExpirationClaim() throws {
        struct BadExp: Codable { var exp: String }
        let token = try EdDSAJWT.sign(BadExp(exp: "not-a-number"), using: key)
        #expect(throws: EdDSAJWTError.claimsDecodingFailed) {
            try EdDSAJWT.verify(token, as: BadExp.self, using: publicKey)
        }
    }
    
    @Test func skipsTimeChecksWhenDisabled() throws {
        struct Expiring: Codable { var exp: Date }
        let expired = Date(timeIntervalSince1970: 1_700_000_000)
        let token = try EdDSAJWT.sign(Expiring(exp: expired), using: key)
        let decoded = try EdDSAJWT.verify(
            token, as: Expiring.self, using: publicKey,
            verifyTimeClaims: false
        )
        #expect(decoded.exp == expired)
    }
    
    @Test func acceptsPayloadWithoutTimeClaims() throws {
        struct NoClaims: Codable, Equatable { var sub: String }
        let payload = NoClaims(sub: "user-42")
        let token = try EdDSAJWT.sign(payload, using: key)
        let decoded = try EdDSAJWT.verify(token, as: NoClaims.self, using: publicKey)
        #expect(decoded == payload)
    }
    
    @Test func surfacesPayloadEncodingFailure() {
        struct Boom: Encodable {
            func encode(to encoder: Encoder) throws {
                throw EncodingError.invalidValue(
                    self,
                    .init(codingPath: [], debugDescription: "boom")
                )
            }
        }
        
        #expect(throws: EdDSAJWTError.payloadEncodingFailed) {
            try EdDSAJWT.sign(Boom(), using: key)
        }
    }
}

@Suite("Base64URL")
struct Base64URLTests {
    
    @Test func roundTripsArbitraryBytes() {
        let data = Data((0..<256).map { UInt8($0) })
        let encoded = data.base64URLEncodedString()
        #expect(!encoded.contains("="))
        #expect(!encoded.contains("+"))
        #expect(!encoded.contains("/"))
        #expect(encoded.base64URLDecodedData() == data)
    }
    
    @Test func decodesWithoutPadding() {
        // "Many hands" base64url-encoded is "TWFueSBoYW5kcw"
        let decoded = "TWFueSBoYW5kcw".base64URLDecodedData()
        #expect(decoded == Data("Many hands".utf8))
    }
    
    @Test func decodesEmpty() {
        #expect("".base64URLDecodedData() == Data())
    }
}
