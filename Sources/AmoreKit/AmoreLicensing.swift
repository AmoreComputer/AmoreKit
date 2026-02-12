import Foundation
import JWTKit

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
    
    public func activate(licenseKey: String) async throws(AmoreError) {
        let nonce = UUID().uuidString
        let token: String
        do {
            token = try await licenseClient.activate(
                licenseKey: licenseKey, hardwareId: hardwareIdentifier.identifier, nonce: nonce,
                name: Host.current().localizedName
            )
        } catch let error as ClientError {
            throw .client(error)
        } catch let error as AmoreError {
            throw error
        } catch {
            throw .network(NetworkError(message: error.localizedDescription))
        }
        let payload = try await verifyToken(token, expectedNonce: nonce)
        do { try tokenStore.store(token) } catch { throw .keychain(error) }
        status = .valid(License(from: payload))
    }
    
    public func deactivate() async throws(AmoreError) {
        let stored: String?
        do { stored = try tokenStore.retrieve() } catch { throw .keychain(error) }
        guard let token = stored else { throw .noStoredToken }
        do {
            try await licenseClient.deactivate(token: token)
        } catch let error as ClientError {
            throw .client(error)
        } catch let error as AmoreError {
            throw error
        } catch {
            throw .network(NetworkError(message: error.localizedDescription))
        }
        do { try tokenStore.delete() } catch { throw .keychain(error) }
        status = .unknown
    }
    
    @discardableResult
    public func validate() async throws(AmoreError) -> ValidationStatus {
        let stored: String?
        do { stored = try tokenStore.retrieve() } catch { throw .keychain(error) }
        guard let token = stored else {
            status = .unknown
            throw .noStoredToken
        }
        
        let keys = await JWTKeyCollection().add(eddsa: publicKey)
        
        do {
            let payload = try await keys.verify(token, as: LicensePayload.self)
            guard payload.hardwareId == hardwareIdentifier.identifier else {
                status = .invalid
                throw AmoreError.hardwareIdMismatch
            }
            status = .valid(License(from: payload))
            return status
        } catch let error as AmoreError {
            throw error
        } catch {
            // Token expired or invalid signature — try refresh
            return try await handleExpiredToken(token, keys: keys)
        }
    }
    
    // MARK: - Private
    
    private func applyGracePeriod(token: String, keys: JWTKeyCollection) -> ValidationStatus {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let payloadData = Data(base64URLDecoded: String(parts[1]))
        else {
            status = .invalid
            return .invalid
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let payload = try? decoder.decode(LicensePayload.self, from: payloadData) else {
            status = .invalid
            return .invalid
        }
        
        let graceEnd = payload.exp.value.addingTimeInterval(configuration.gracePeriod.timeInterval)
        var license = License(from: payload)
        license.expiresAt = graceEnd
        
        if graceEnd > Date() {
            status = .gracePeriod(license)
            return status
        } else {
            status = .invalid
            return .invalid
        }
    }
    
    private func handleExpiredToken(_ token: String, keys: JWTKeyCollection) async throws(AmoreError) -> ValidationStatus {
        let nonce = UUID().uuidString
        do {
            let newToken = try await licenseClient.validate(
                token: token, nonce: nonce
            )
            let payload = try await verifyToken(newToken, expectedNonce: nonce)
            do { try tokenStore.store(newToken) } catch { throw AmoreError.keychain(error) }
            status = .valid(License(from: payload))
            return status
        } catch let error as ClientError {
            throw .client(error)
        } catch let error as AmoreError {
            throw error
        } catch {
            return applyGracePeriod(token: token, keys: keys)
        }
    }
    
    @discardableResult
    private func verifyToken(_ token: String, expectedNonce: String) async throws(AmoreError) -> LicensePayload {
        let keys = await JWTKeyCollection().add(eddsa: publicKey)
        let payload: LicensePayload
        do {
            payload = try await keys.verify(token, as: LicensePayload.self)
        } catch {
            throw .invalidSignature
        }
        guard payload.nonce == expectedNonce else { throw .nonceMismatch }
        guard payload.hardwareId == hardwareIdentifier.identifier else { throw .hardwareIdMismatch }
        return payload
    }
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
