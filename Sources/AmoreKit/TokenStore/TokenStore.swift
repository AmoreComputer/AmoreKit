protocol TokenStore: Sendable {
    func store(_ token: String) throws
    func retrieve() throws -> String?
    func delete() throws
}
