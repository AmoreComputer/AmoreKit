/// A persistence mechanism for the signed license token.
///
/// `AmoreLicensing` uses a token store to persist the license JWT between launches so it can
/// validate offline. The default ``FileTokenStore`` writes to Application Support. Provide a custom
/// conformance to store the token elsewhere, and inject it via
/// ``AmoreLicensing/init(publicKey:bundleIdentifier:configuration:server:tokenStore:)``.
public protocol TokenStore: Sendable {
    /// Persists the license token, replacing any previously stored token.
    /// - Parameter token: The signed license JWT to store.
    /// - Throws: ``TokenStoreError`` if the token cannot be written.
    func store(_ token: String) throws(TokenStoreError)

    /// Returns the stored license token, or `nil` if none is stored.
    /// - Returns: The stored license JWT, or `nil` when no token has been saved.
    /// - Throws: ``TokenStoreError`` if a stored token exists but cannot be read.
    func retrieve() throws(TokenStoreError) -> String?

    /// Removes the stored license token, if present.
    /// - Throws: ``TokenStoreError`` if an existing token cannot be removed.
    func delete() throws(TokenStoreError)
}
