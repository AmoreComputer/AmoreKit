import Foundation
import Security

struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String
    private let accessGroup: String

    init(bundleIdentifier: String, accessGroup: String) {
        self.service = "\(bundleIdentifier).license"
        self.account = bundleIdentifier
        self.accessGroup = accessGroup
    }

    func store(_ token: String) throws(TokenStoreError) {
        guard let data = token.data(using: .utf8) else {
            throw .storeFailed("Unable to encode token as UTF-8")
        }

        // Delete any existing item first so SecItemAdd always succeeds.
        try? delete()

        // Should allow for reading the token even when launched in the background.
        // Restricts the item to this device so it won't migrate to another Mac via iCloud Keychain backup.
        // kSecUseDataProtectionKeychain is used to place the item into the Local Items keychain where extensions can access them.
        let query: [CFString: Any] = [
            kSecClass:                   kSecClassGenericPassword,
            kSecAttrService:             service,
            kSecAttrAccount:             account,
            kSecAttrAccessGroup:         accessGroup,
            kSecValueData:               data,
            kSecAttrAccessible:          kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecUseDataProtectionKeychain: true,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw .storeFailed(statusMessage(status))
        }
    }

    func retrieve() throws(TokenStoreError) -> String? {
        let query: [CFString: Any] = [
            kSecClass:                    kSecClassGenericPassword,
            kSecAttrService:              service,
            kSecAttrAccount:              account,
            kSecAttrAccessGroup:          accessGroup,
            kSecReturnData:               true,
            kSecMatchLimit:               kSecMatchLimitOne,
            kSecUseDataProtectionKeychain: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw .retrieveFailed("Keychain item data is not valid UTF-8")
            }
            return token

        case errSecItemNotFound:
            return nil

        default:
            throw .retrieveFailed(statusMessage(status))
        }
    }

    func delete() throws(TokenStoreError) {
        let query: [CFString: Any] = [
            kSecClass:                    kSecClassGenericPassword,
            kSecAttrService:              service,
            kSecAttrAccount:              account,
            kSecAttrAccessGroup:          accessGroup,
            kSecUseDataProtectionKeychain: true,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .deleteFailed(statusMessage(status))
        }
    }

    // MARK: - Private

    private func statusMessage(_ status: OSStatus) -> String {
        SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
    }
}
