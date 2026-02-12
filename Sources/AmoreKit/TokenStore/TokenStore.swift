protocol TokenStore: Sendable {
    func store(_ token: String) throws(KeychainError)
    func retrieve() throws(KeychainError) -> String?
    func delete() throws(KeychainError)
}
