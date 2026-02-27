import Foundation

struct FileTokenStore: TokenStore {
    private let fileURL: URL
    
    static let fileName = "license.jwt"
    
    init(bundleIdentifier: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = appSupport.appendingPathComponent(bundleIdentifier).appendingPathComponent(Self.fileName)
    }
    
    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }
    
    func store(_ token: String) throws(TokenStoreError) {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(token.utf8).write(to: fileURL, options: .atomic)
        } catch {
            throw .storeFailed(error.localizedDescription)
        }
    }
    
    func retrieve() throws(TokenStoreError) -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return String(data: data, encoding: .utf8)
        } catch {
            throw .retrieveFailed(error.localizedDescription)
        }
    }
    
    func delete() throws(TokenStoreError) {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw .deleteFailed(error.localizedDescription)
        }
    }
}
