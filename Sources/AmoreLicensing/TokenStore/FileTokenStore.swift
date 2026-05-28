import Foundation

/// A ``TokenStore`` that persists the license token as a file on disk.
///
/// This is the default store used by ``AmoreLicensing`` when no custom store is provided. It writes
/// to the app's Application Support directory.
public struct FileTokenStore: TokenStore {
    private let fileURL: URL
    
    static let fileName = "license.jwt"
    
    init(bundleIdentifier: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = appSupport.appendingPathComponent(bundleIdentifier).appendingPathComponent(Self.fileName)
    }
    
    /// Creates a store that persists the token in the given directory.
    /// - Parameter directory: The directory in which to read and write the token file.
    public init(directory: URL) {
        self.fileURL = directory.appendingPathComponent(Self.fileName)
    }
    
    public func store(_ token: String) throws(TokenStoreError) {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(token.utf8).write(to: fileURL, options: .atomic)
        } catch {
            throw .storeFailed(error.localizedDescription)
        }
    }
    
    public func retrieve() throws(TokenStoreError) -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return String(data: data, encoding: .utf8)
        } catch {
            throw .retrieveFailed(error.localizedDescription)
        }
    }
    
    public func delete() throws(TokenStoreError) {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw .deleteFailed(error.localizedDescription)
        }
    }
}
