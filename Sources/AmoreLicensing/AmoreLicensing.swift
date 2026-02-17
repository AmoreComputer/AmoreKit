import Foundation
import JWTKit

@Observable
public final class AmoreLicensing: Licensing {
    public private(set) var status: ValidationStatus = .unknown
    
    private let autoValidate: Bool
    private let bundleIdentifier: String
    private let configuration: LicensingConfiguration
    private let hardwareIdentifier: HardwareIdentifier
    private let jwtCollection = JWTKeyCollection()
    private let licenseClient: LicenseClient
    private let publicKey: EdDSA.PublicKey
    private let tokenStore: TokenStore
    private var keysReady = false
    private var validationTask: Task<Void, Never>?
    
    public init(
        publicKey: String,
        bundleIdentifier: String? = nil,
        autoValidate: Bool = false,
        configuration: LicensingConfiguration = .default,
        server: LicenseServer? = nil,
    ) throws {
        let bid = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? publicKey
        self.autoValidate = autoValidate
        self.configuration = configuration
        self.publicKey = try EdDSA.PublicKey(x: publicKey, curve: .ed25519)
        self.bundleIdentifier = bid
        self.tokenStore = KeychainTokenStore(bundleIdentifier: bid)
        self.hardwareIdentifier = MacHardwareIdentifier()
        self.licenseClient = HTTPLicenseClient(server: server ?? .amore(bundleIdentifier: bid))
        if autoValidate {
            Task { [self] in try? await validate() }
        }
    }
    
    internal init(
        publicKey: EdDSA.PublicKey,
        bundleIdentifier: String,
        autoValidate: Bool = false,
        configuration: LicensingConfiguration = .default,
        tokenStore: TokenStore,
        hardwareIdentifier: HardwareIdentifier,
        licenseClient: LicenseClient
    ) {
        self.autoValidate = autoValidate
        self.configuration = configuration
        self.publicKey = publicKey
        self.bundleIdentifier = bundleIdentifier
        self.tokenStore = tokenStore
        self.hardwareIdentifier = hardwareIdentifier
        self.licenseClient = licenseClient
    }
    
    isolated deinit {
        validationTask?.cancel()
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
        if autoValidate { startAutoValidation() }
    }
    
    public func deactivate() async throws(AmoreError) {
        stopAutoValidation()
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
        
        await ensureKeysConfigured()
        
        let result: ValidationStatus
        do {
            let payload = try await jwtCollection.verify(token, as: LicensePayload.self)
            guard payload.hardwareId == hardwareIdentifier.identifier else {
                status = .invalid
                throw AmoreError.hardwareIdMismatch
            }
            if shouldRefreshProactively(issuedAt: payload.iat.value) {
                result = try await refreshOrKeepValid(token, payload: payload)
            } else {
                status = .valid(License(from: payload))
                result = status
            }
        } catch let error as AmoreError {
            throw error
        } catch {
            // Token expired or invalid signature — try refresh
            result = try await handleExpiredToken(token)
        }
        
        if autoValidate, case .valid = result { startAutoValidation() }
        return result
    }
    
    // MARK: - Private
    
    private func startAutoValidation() {
        guard validationTask == nil else { return }
        guard let interval = configuration.validationFrequency.timeInterval, interval > 0 else { return }
        validationTask = Task(name: "AmoreKit.ValidationTask", priority: .background) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                _ = try? await validate()
            }
        }
    }
    
    private func stopAutoValidation() {
        validationTask?.cancel()
        validationTask = nil
    }
    
    private func refreshOrKeepValid(
        _ token: String, payload: LicensePayload
    ) async throws(AmoreError) -> ValidationStatus {
        let nonce = UUID().uuidString
        do {
            let newToken = try await licenseClient.validate(token: token, nonce: nonce)
            let newPayload = try await verifyToken(newToken, expectedNonce: nonce)
            do { try tokenStore.store(newToken) } catch { throw AmoreError.keychain(error) }
            status = .valid(License(from: newPayload))
            return status
        } catch let error as ClientError {
            status = .invalid
            stopAutoValidation()
            throw .client(error)
        } catch let error as AmoreError {
            throw error
        } catch {
            // Network failure — JWT is still valid, keep using it
            status = .valid(License(from: payload))
            return status
        }
    }
    
    private func shouldRefreshProactively(issuedAt: Date) -> Bool {
        guard let interval = configuration.validationFrequency.timeInterval else { return false }
        return Date().timeIntervalSince(issuedAt) >= interval
    }
    
    private func applyGracePeriod(token: String) async -> ValidationStatus {
        guard let payload = try? await jwtCollection.verify(token, as: GracePeriodPayload.self) else {
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
    
    private func handleExpiredToken(_ token: String) async throws(AmoreError) -> ValidationStatus {
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
            status = .invalid
            stopAutoValidation()
            throw .client(error)
        } catch let error as AmoreError {
            throw error
        } catch {
            return await applyGracePeriod(token: token)
        }
    }
    
    @discardableResult
    private func verifyToken(_ token: String, expectedNonce: String) async throws(AmoreError) -> LicensePayload {
        await ensureKeysConfigured()
        let payload: LicensePayload
        do {
            payload = try await jwtCollection.verify(token, as: LicensePayload.self)
        } catch {
            throw .invalidSignature
        }
        guard payload.nonce == expectedNonce else { throw .nonceMismatch }
        guard payload.hardwareId == hardwareIdentifier.identifier else { throw .hardwareIdMismatch }
        return payload
    }
    
    private func ensureKeysConfigured() async {
        guard !keysReady else { return }
        await jwtCollection.add(eddsa: publicKey)
        keysReady = true
    }
}
