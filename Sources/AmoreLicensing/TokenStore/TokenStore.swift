protocol TokenStore: Sendable {
    func store(_ token: String) throws(TokenStoreError)
    func retrieve() throws(TokenStoreError) -> String?
    func delete() throws(TokenStoreError)
}
