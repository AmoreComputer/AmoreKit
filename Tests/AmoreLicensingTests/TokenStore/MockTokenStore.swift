@testable import AmoreLicensing

final class MockTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?

    func store(_ token: String) throws(TokenStoreError) {
        self.token = token
    }

    func retrieve() throws(TokenStoreError) -> String? {
        token
    }

    func delete() throws(TokenStoreError) {
        token = nil
    }
}
