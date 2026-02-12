@testable import AmoreLicensing

final class MockTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?

    func store(_ token: String) throws(KeychainError) {
        self.token = token
    }

    func retrieve() throws(KeychainError) -> String? {
        token
    }

    func delete() throws(KeychainError) {
        token = nil
    }
}
