import Crypto
import Foundation

/// Sync EdDSA (Ed25519) JWT sign and verify.
///
/// Only the EdDSA algorithm is supported. Header `alg` is pinned at
/// verification time to prevent algorithm-confusion attacks. The `exp`
/// claim is enforced by default; opt out with
/// ``verify(_:as:using:verifyTimeClaims:)``'s `verifyTimeClaims` flag for
/// callers that intentionally tolerate expired payloads.
package enum EdDSAJWTError: Error, Equatable {
    case malformedToken
    case unsupportedAlgorithm(String)
    case invalidSignature
    case headerDecodingFailed
    case payloadDecodingFailed
    case payloadEncodingFailed
    case claimsDecodingFailed
    case expired
}

package enum EdDSAJWT {
    private struct VerifyHeader: Decodable {
        let alg: String
    }
    
    private struct TimeClaims: Decodable {
        var exp: Date?
    }
    
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
    
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
    
    package static func verify<Payload: Decodable>(
        _ token: String,
        as: Payload.Type,
        using publicKey: Curve25519.Signing.PublicKey,
        verifyTimeClaims: Bool = true
    ) throws -> Payload {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw EdDSAJWTError.malformedToken }
        
        let headerString = String(parts[0])
        let payloadString = String(parts[1])
        let signatureString = String(parts[2])
        
        guard
            let headerData = headerString.base64URLDecodedData(),
            let payloadData = payloadString.base64URLDecodedData(),
            let signatureData = signatureString.base64URLDecodedData()
        else { throw EdDSAJWTError.malformedToken }
        
        let header: VerifyHeader
        do { header = try decoder.decode(VerifyHeader.self, from: headerData) }
        catch { throw EdDSAJWTError.headerDecodingFailed }
        
        guard header.alg == "EdDSA" else {
            throw EdDSAJWTError.unsupportedAlgorithm(header.alg)
        }
        
        let signingInput = Data("\(headerString).\(payloadString)".utf8)
        guard publicKey.isValidSignature(signatureData, for: signingInput) else {
            throw EdDSAJWTError.invalidSignature
        }
        
        if verifyTimeClaims {
            let claims: TimeClaims
            do { claims = try decoder.decode(TimeClaims.self, from: payloadData) }
            catch { throw EdDSAJWTError.claimsDecodingFailed }
            let now = Date()
            if let exp = claims.exp, exp <= now { throw EdDSAJWTError.expired }
        }
        
        do { return try decoder.decode(Payload.self, from: payloadData) }
        catch { throw EdDSAJWTError.payloadDecodingFailed }
    }
    
    package static func sign<Payload: Encodable>(
        _ payload: Payload,
        using privateKey: Curve25519.Signing.PrivateKey
    ) throws -> String {
        let headerString: String =
        Data(#"{"alg":"EdDSA","typ":"JWT"}"#.utf8).base64URLEncodedString()
        let payloadData: Data
        do { payloadData = try Self.encoder.encode(payload) }
        catch { throw EdDSAJWTError.payloadEncodingFailed }
        let payloadString = payloadData.base64URLEncodedString()
        
        let signingInput = Data("\(headerString).\(payloadString)".utf8)
        let signature = try privateKey.signature(for: signingInput)
        let signatureString = Data(signature).base64URLEncodedString()
        
        return "\(headerString).\(payloadString).\(signatureString)"
    }
}
