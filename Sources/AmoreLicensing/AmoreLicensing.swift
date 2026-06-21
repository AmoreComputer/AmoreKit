import AmoreJWT
import Crypto
import Foundation
import Observation

/// Manages license activation, deactivation, and validation against an Amore licensing server.
///
/// Observes ``status`` to reactively update UI based on the current validation state.
@Observable
public final class AmoreLicensing: Licensing {
    /// The current validation status of the license.
    public private(set) var status: ValidationStatus = .unknown

    private let bundleIdentifier: String
    private let configuration: LicensingConfiguration
    private let deviceIdentity: any DeviceIdentity
    private let licenseClient: LicenseClient
    private let tokenStore: TokenStore
    private let verifier: LicenseTokenVerifier
    private var isValidating = false

    /// Creates a new licensing instance.
    /// - Parameters:
    ///   - publicKey: The Ed25519 public key used to verify server responses.
    ///   - bundleIdentifier: The app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier`.
    ///   - configuration: The licensing configuration. Defaults to ``LicensingConfiguration/default``.
    ///   - server: The license server to use. Defaults to the Amore server.
    ///   - deviceIdentity: How this device is identified when binding a license. On macOS, use the initializer without this parameter to default to the built-in identifier.
    ///   - tokenStore: A custom store for persisting the license token. Defaults to a ``FileTokenStore`` in Application Support. Provide a custom ``TokenStore`` to store the token elsewhere.
    public init(
        publicKey: String,
        bundleIdentifier: String? = nil,
        configuration: LicensingConfiguration = .default,
        server: LicenseServer? = nil,
        deviceIdentity: (any DeviceIdentity),
        tokenStore: (any TokenStore)? = nil,
    ) throws {
        let bundleIdentifier = bundleIdentifier ?? Bundle.main.bundleIdentifier ?? publicKey
        guard
            let keyData = publicKey.base64URLDecodedData(),
            let signingKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else {
            throw AmoreError.invalidPublicKey
        }
        self.configuration = configuration
        self.bundleIdentifier = bundleIdentifier
        self.tokenStore = tokenStore ?? FileTokenStore(bundleIdentifier: bundleIdentifier)
        self.deviceIdentity = deviceIdentity
        self.licenseClient = HTTPLicenseClient(server: server ?? .amore(for: bundleIdentifier))
        self.verifier = LicenseTokenVerifier(publicKey: signingKey, deviceIdentity: deviceIdentity)
        if configuration.validationFrequency.shouldValidateAtLaunch {
            validateLocally()
            Task { [self] in try? await validate() }
        }
    }

#if os(macOS)
    /// Creates a new licensing instance using the built-in macOS device identity.
    ///
    /// This is the recommended initializer on macOS. To control how the device is
    /// identified, use the initializer that takes a `deviceIdentity` instead.
    /// - Parameters:
    ///   - publicKey: The Ed25519 public key used to verify server responses.
    ///   - bundleIdentifier: The app's bundle identifier. Defaults to `Bundle.main.bundleIdentifier`.
    ///   - configuration: The licensing configuration. Defaults to ``LicensingConfiguration/default``.
    ///   - server: The license server to use. Defaults to the Amore server.
    ///   - tokenStore: A custom store for persisting the license token. Defaults to a ``FileTokenStore`` in Application Support. Provide a custom ``TokenStore`` to store the token elsewhere.
    public convenience init(
        publicKey: String,
        bundleIdentifier: String? = nil,
        configuration: LicensingConfiguration = .default,
        server: LicenseServer? = nil,
        tokenStore: (any TokenStore)? = nil,
    ) throws {
        try self.init(
            publicKey: publicKey,
            bundleIdentifier: bundleIdentifier,
            configuration: configuration,
            server: server,
            deviceIdentity: MacDeviceIdentity(),
            tokenStore: tokenStore
        )
    }
#endif

    internal init(
        publicKey: Curve25519.Signing.PublicKey,
        bundleIdentifier: String,
        configuration: LicensingConfiguration = .default,
        tokenStore: TokenStore,
        deviceIdentity: any DeviceIdentity,
        licenseClient: LicenseClient
    ) {
        self.configuration = configuration
        self.bundleIdentifier = bundleIdentifier
        self.tokenStore = tokenStore
        self.deviceIdentity = deviceIdentity
        self.licenseClient = licenseClient
        self.verifier = LicenseTokenVerifier(publicKey: publicKey, deviceIdentity: deviceIdentity)
    }

    /// Activates a license on this device using the given license key.
    /// - Parameter licenseKey: The license key to activate.
    /// - Throws: ``AmoreError`` if activation fails.
    public func activate(licenseKey: String) async throws(AmoreError) {
        let nonce = UUID().uuidString
        let token = try await mapClientErrors {
            try await self.licenseClient.activate(
                licenseKey: licenseKey, hardwareId: self.deviceIdentity.identifier, nonce: nonce,
                name: self.deviceIdentity.deviceName
            )
        }
        let payload = try verifier.decode(token, expectedNonce: nonce)
        do { try tokenStore.store(token) } catch { throw .tokenStore(error) }
        status = .valid(License(from: payload))
    }

    /// Deactivates the current license on this device.
    /// - Throws: ``AmoreError`` if deactivation fails.
    public func deactivate() async throws(AmoreError) {
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
    ///
    /// The token is verified locally (signature, expiry, hardware ID). If it is
    /// stale for the configured ``ValidationFrequency`` (or has expired) it is
    /// refreshed from the server; if that refresh fails the license enters its
    /// ``LicensingConfiguration/gracePeriod``.
    ///
    /// AmoreLicensing calls this automatically once at launch (for every
    /// ``ValidationFrequency`` except ``ValidationFrequency/manual``). It does
    /// **not** run a background timer, so call this yourself at the lifecycle
    /// moments that matter, for example when your main window returns to the
    /// foreground, to keep a long-running app's ``status`` fresh.
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

        switch verifier.decodeLocally(token) {
        case .hardwareMismatch:
            status = .invalid
            throw AmoreError.hardwareIdMismatch
        case .unverifiable:
            try await refreshToken(token)
        case .decoded(let payload):
            if payload.exp < Date() || configuration.validationFrequency.isRefreshDue(issuedAt: payload.iat) {
                try await refreshToken(token, localPayload: payload)
            } else {
                status = .valid(License(from: payload))
            }
        }
        return status
    }

    // MARK: - Private

    private func validateLocally() {
        guard let token = try? tokenStore.retrieve() else { return }
        switch verifier.decodeLocally(token) {
        case .hardwareMismatch:
            status = .invalid
        case .unverifiable:
            break
        case .decoded(let payload) where payload.exp > Date():
            status = .valid(License(from: payload))
        case .decoded(let payload):
            // Expired, but maybe still within grace. Surface grace synchronously so
            // an offline launch is authoritative; stay .unknown once grace has
            // elapsed and let validate() ask the server, which may still renew it.
            if let license = graceLicense(for: payload) { status = .gracePeriod(license) }
        }
    }

    /// Refreshes the token from the server and updates ``status``. On a transient
    /// failure it keeps `localPayload` while still valid, falls back to the grace
    /// period once it has expired, and invalidates when there is nothing to fall
    /// back on; a ``ClientError`` always invalidates the license.
    private func refreshToken(
        _ token: String,
        localPayload: LicensePayload? = nil
    ) async throws(AmoreError) {
        let nonce = UUID().uuidString
        do {
            let newToken = try await licenseClient.validate(token: token, nonce: nonce)
            let payload = try verifier.decode(newToken, expectedNonce: nonce)
            do { try tokenStore.store(newToken) } catch { throw AmoreError.tokenStore(error) }
            status = .valid(License(from: payload))
        } catch let error as ClientError {
            status = .invalid
            throw .client(error)
        } catch let error as AmoreError {
            guard let localPayload, localPayload.exp > Date() else { throw error }
            status = .valid(License(from: localPayload))
        } catch {
            guard let localPayload else { status = .invalid; return }
            guard localPayload.exp > Date() else { applyGracePeriod(payload: localPayload); return }
            // Token still valid locally, keep using it.
            status = .valid(License(from: localPayload))
        }
    }

    /// Enters the grace period derived from an already-verified, expired payload,
    /// or invalidates once that grace period has elapsed.
    private func applyGracePeriod(payload: LicensePayload) {
        if let license = graceLicense(for: payload) {
            status = .gracePeriod(license)
        } else {
            status = .invalid
        }
    }
    
    /// The license a still-within-grace expired payload represents, or `nil` once
    /// the grace period has elapsed.
    private func graceLicense(for payload: LicensePayload) -> License? {
        let graceEnd = payload.exp.addingTimeInterval(configuration.gracePeriod.timeInterval)
        guard graceEnd >= .now else { return nil }
        return License(from: payload)
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

}
