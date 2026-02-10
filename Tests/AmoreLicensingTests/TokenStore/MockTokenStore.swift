@testable import AmoreLicensing

final class MockTokenStore: TokenStore, @unchecked Sendable {
    private var token: String?

    func store(_ token: String) throws {
        self.token = token
    }

    func retrieve() throws -> String? {
        token
    }

    func delete() throws {
        token = nil
    }
}
