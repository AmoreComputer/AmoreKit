import Foundation
import JWTKit

@MainActor
@Observable
public final class AmoreLicensing: Licensing {
    public private(set) var status: ValidationStatus = .unknown

    private let bundleIdentifier: String
    private let configuration: LicensingConfiguration
    private let hardwareIdentifier: HardwareIdentifier
    private let licenseClient: LicenseClient
    private let publicKey: EdDSA.PublicKey
    private let tokenStore: TokenStore

    public init(
        publicKey: String,
        bundleIdentifier: String? = nil,
        autoValidate: Bool = false,
        configuration: LicensingConfiguration = .default,
        server: LicenseServer? = nil,
    ) throws {
        let bid = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? publicKey
        self.configuration = configuration
        self.publicKey = try EdDSA.PublicKey(x: publicKey, curve: .ed25519)
        self.bundleIdentifier = bid
        self.tokenStore = KeychainTokenStore(bundleIdentifier: bid)
        self.hardwareIdentifier = MacHardwareIdentifier()
        self.licenseClient = HTTPLicenseClient(server: server ?? .amore(bundleIdentifier: bid))

        if autoValidate {
            Task { try? await validate() }
        }
    }

    internal init(
        publicKey: EdDSA.PublicKey,
        bundleIdentifier: String,
        configuration: LicensingConfiguration = .default,
        tokenStore: TokenStore,
        hardwareIdentifier: HardwareIdentifier,
        licenseClient: LicenseClient
    ) {
        self.configuration = configuration
        self.publicKey = publicKey
        self.bundleIdentifier = bundleIdentifier
        self.tokenStore = tokenStore
        self.hardwareIdentifier = hardwareIdentifier
        self.licenseClient = licenseClient
    }

    public func activate(licenseKey: String) async throws {
        let nonce = UUID().uuidString
        let token: String
        do {
            token = try await licenseClient.activate(
                licenseKey: licenseKey, hardwareId: hardwareIdentifier.identifier, nonce: nonce
            )
        } catch {
            throw AmoreError.networkError(error.localizedDescription)
        }
        let payload = try await verifyToken(token, expectedNonce: nonce)
        try tokenStore.store(token)
        status = .valid(until: payload.exp.value)
    }

    @discardableResult
    public func validate() async throws -> ValidationStatus {
        guard let token = try tokenStore.retrieve() else {
            status = .unknown
            throw AmoreError.noStoredToken
        }

        let keys = await JWTKeyCollection().add(eddsa: publicKey)

        do {
            let payload = try await keys.verify(token, as: LicensePayload.self)
            guard payload.hardwareId == hardwareIdentifier.identifier else {
                status = .invalid
                throw AmoreError.hardwareIdMismatch
            }
            let validUntil = payload.exp.value
            status = .valid(until: validUntil)
            return .valid(until: validUntil)
        } catch let error as AmoreError {
            throw error
        } catch {
            // Token expired or invalid signature — try refresh
            return try await handleExpiredToken(token, keys: keys)
        }
    }

    // MARK: - Private

    private func applyGracePeriod(token: String, keys: JWTKeyCollection) throws -> ValidationStatus {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLDecoded: String(parts[1]))
        else {
            status = .invalid
            return .invalid
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let payload = try? decoder.decode(GracePeriodPayload.self, from: payloadData) else {
            status = .invalid
            return .invalid
        }

        let graceEnd = payload.exp.addingTimeInterval(configuration.gracePeriod.timeInterval)

        if graceEnd > Date() {
            status = .gracePeriod(until: graceEnd)
            return .gracePeriod(until: graceEnd)
        } else {
            status = .invalid
            return .invalid
        }
    }

    private func handleExpiredToken(_ token: String, keys: JWTKeyCollection) async throws -> ValidationStatus {
        let nonce = UUID().uuidString
        do {
            let newToken = try await licenseClient.validate(
                token: token, nonce: nonce
            )
            let payload = try await verifyToken(newToken, expectedNonce: nonce)
            try tokenStore.store(newToken)
            let validUntil = payload.exp.value
            status = .valid(until: validUntil)
            return .valid(until: validUntil)
        } catch let error as AmoreError {
            throw error
        } catch {
            return try applyGracePeriod(token: token, keys: keys)
        }
    }

    @discardableResult
    private func verifyToken(_ token: String, expectedNonce: String) async throws -> LicensePayload {
        let keys = await JWTKeyCollection().add(eddsa: publicKey)
        let payload: LicensePayload
        do {
            payload = try await keys.verify(token, as: LicensePayload.self)
        } catch {
            throw AmoreError.invalidSignature
        }
        guard payload.nonce == expectedNonce else { throw AmoreError.nonceMismatch }
        guard payload.hardwareId == hardwareIdentifier.identifier else { throw AmoreError.hardwareIdMismatch }
        return payload
    }
}

private struct GracePeriodPayload: Decodable {
    let exp: Date
}

private extension Data {
    init?(base64URLDecoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }
}
