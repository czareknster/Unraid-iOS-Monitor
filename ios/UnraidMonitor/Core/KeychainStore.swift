import Foundation
import Security

enum KeychainKey: String {
    case apiToken = "com.cezarmac.unraidmonitor.apiToken"
    case cfAccessClientId = "com.cezarmac.unraidmonitor.cfAccessClientId"
    case cfAccessClientSecret = "com.cezarmac.unraidmonitor.cfAccessClientSecret"
}

enum KeychainStore {
    static func set(_ value: String, for key: KeychainKey) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
        ]
        SecItemDelete(query as CFDictionary)
        if value.isEmpty { return }
        let addQuery = query.merging([kSecValueData as String: data]) { _, new in new }
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func get(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
