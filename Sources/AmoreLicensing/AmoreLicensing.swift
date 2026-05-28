import Foundation
import JWTKit

/// Manages license activation, deactivation, and validation against an Amore licensing server.
///
/// Observes ``status`` to reactively update UI based on the current validation state.
@Observable
public final class AmoreLicensing: Licensing {
    /// The current validation status of the license.
    public private(set) var status: ValidationStatus = .unknown
    
    private let bundleIdentifier: String
    private let configuration: LicensingConfiguration
    private let hardwareIdentifier: HardwareIdentifier
    private let jwtCollection = JWTKeyCollection()
    private let licenseClient: LicenseClient
    private let publicKey: EdDSA.PublicKey
    private let tokenStore: TokenStore
    private var shouldAutoValidate: Bool {
        configuration.validationFrequency != .manual
    }
    private var isValidating = false
    private var keysReady = false
    private var validationTask: Task<Void, Never>?
    
    /// Creates a new licensing instance.
    /// - Parameters:
    ///   - publicKey: The Ed25519 public key used to verify server responses.
    ///   - bundleIdentifier: The app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier`.
    ///   - configuration: The licensing configuration. Defaults to ``LicensingConfiguration/default``.
    ///   - server: The license server to use. Defaults to the Amore server.
    ///   - tokenStore: A custom store for persisting the license token. Defaults to a ``FileTokenStore`` in Application Support. Provide a custom ``TokenStore`` to store the token elsewhere.
    public init(
        publicKey: String,
        bundleIdentifier: String? = nil,
        configuration: LicensingConfiguration = .default,
        server: LicenseServer? = nil,
        tokenStore: (any TokenStore)? = nil
    ) throws {
        let bundleIdentifier = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? publicKey
        self.configuration = configuration
        self.publicKey = try EdDSA.PublicKey(x: publicKey, curve: .ed25519)
        self.bundleIdentifier = bundleIdentifier
        self.tokenStore = tokenStore ?? FileTokenStore(bundleIdentifier: bundleIdentifier)
        self.hardwareIdentifier = MacHardwareIdentifier()
        self.licenseClient = HTTPLicenseClient(server: server ?? .amore(for: bundleIdentifier))
        if shouldAutoValidate {
            Task { [self] in try? await validate() }
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
    
    isolated deinit {
        validationTask?.cancel()
    }
    
    /// Activates a license on this device using the given license key.
    /// - Parameter licenseKey: The license key to activate.
    /// - Throws: ``AmoreError`` if activation fails.
    public func activate(licenseKey: String) async throws(AmoreError) {
        let nonce = UUID().uuidString
        let token = try await mapClientErrors {
            try await self.licenseClient.activate(
                licenseKey: licenseKey, hardwareId: self.hardwareIdentifier.identifier, nonce: nonce,
                name: Host.current().localizedName
            )
        }
        let payload = try await verifyToken(token, expectedNonce: nonce)
        do { try tokenStore.store(token) } catch { throw .tokenStore(error) }
        status = .valid(License(from: payload))
        if shouldAutoValidate { startAutoValidation() }
    }
    
    /// Deactivates the current license on this device.
    /// - Throws: ``AmoreError`` if deactivation fails.
    public func deactivate() async throws(AmoreError) {
        stopAutoValidation()
        let stored: String?
        do { stored = try tokenStore.retrieve() } catch { throw .tokenStore(error) }
        guard let token = stored else { throw .noStoredToken }
        try await mapClientErrors {
            try await self.licenseClient.deactivate(token: token)
        }
        do { try tokenStore.delete() } catch { throw .tokenStore(error) }
        status = .unknown
    }
    
    /// Validates the stored license token and updates ``status``.
    /// - Returns: The resulting ``ValidationStatus``.
    /// - Throws: ``AmoreError`` if validation fails.
    @discardableResult
    public func validate() async throws(AmoreError) -> ValidationStatus {
        guard !isValidating else { return status }
        isValidating = true
        defer { isValidating = false }
        
        let stored: String?
        do { stored = try tokenStore.retrieve() } catch { throw .tokenStore(error) }
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
                result = try await refreshToken(token, currentPayload: payload)
            } else {
                status = .valid(License(from: payload))
                result = status
            }
        } catch let error as AmoreError {
            throw error
        } catch {
            // Token expired or invalid signature — try refresh
            result = try await refreshToken(token)
        }
        
        if shouldAutoValidate, case .valid = result { startAutoValidation() }
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
    
    private func refreshToken(
        _ token: String,
        currentPayload: LicensePayload? = nil
    ) async throws(AmoreError) -> ValidationStatus {
        let nonce = UUID().uuidString
        do {
            let newToken = try await licenseClient.validate(token: token, nonce: nonce)
            let payload = try await verifyToken(newToken, expectedNonce: nonce)
            do { try tokenStore.store(newToken) } catch { throw AmoreError.tokenStore(error) }
            status = .valid(License(from: payload))
            return status
        } catch let error as ClientError {
            status = .invalid
            stopAutoValidation()
            throw .client(error)
        } catch let error as AmoreError {
            if let currentPayload {
                status = .valid(License(from: currentPayload))
                return status
            }
            throw error
        } catch {
            if let currentPayload {
                // Token still valid locally, keep using it
                status = .valid(License(from: currentPayload))
                return status
            }
            return await applyGracePeriod(token: token)
        }
    }
    
    private func shouldRefreshProactively(issuedAt: Date) -> Bool {
        guard let interval = configuration.validationFrequency.timeInterval else { return false }
        return Date().timeIntervalSince(issuedAt) >= interval
    }
    
    private func applyGracePeriod(token: String) async -> ValidationStatus {
        await ensureKeysConfigured()
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
    
    private func mapClientErrors<T>(
        _ operation: @MainActor @Sendable () async throws -> T
    ) async throws(AmoreError) -> T {
        do {
            return try await operation()
        } catch let error as ClientError {
            throw .client(error)
        } catch let error as NetworkError {
            throw .network(error)
        } catch let error as AmoreError {
            throw error
        } catch {
            throw .network(.requestFailed(error.localizedDescription))
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
