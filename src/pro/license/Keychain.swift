import Foundation
import Security

protocol Keychain {
    func value(account: String) -> String?
    @discardableResult func setValue(_ value: String, account: String) -> OSStatus
    @discardableResult func remove(account: String) -> OSStatus
}

struct SystemKeychain: Keychain {
    let service: String

    func value(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
            case errSecSuccess:
                guard let data = result as? Data,
                      let string = String(data: data, encoding: .utf8) else {
                    Logger.error { "keychain read account=\(account): success but data not utf-8" }
                    return nil
                }
                return string
            case errSecItemNotFound:
                return nil
            default:
                Logger.error { "keychain read account=\(account) failed: \(Self.describe(status))" }
                return nil
        }
    }

    @discardableResult
    func setValue(_ value: String, account: String) -> OSStatus {
        remove(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: value.data(using: .utf8)!,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            Logger.error { "keychain write account=\(account) failed: \(Self.describe(status))" }
        }
        return status
    }

    @discardableResult
    func remove(account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error { "keychain delete account=\(account) failed: \(Self.describe(status))" }
        }
        return status
    }

    static func describe(_ status: OSStatus) -> String {
        let msg = SecCopyErrorMessageString(status, nil) as String? ?? "unknown"
        return "OSStatus=\(status) (\(msg))"
    }

    #if DEBUG
    /// Wipe every keychain entry under `service`. Used by the QA "Mock fresh install" action.
    @discardableResult
    func removeAll() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error { "keychain wipe service=\(service) failed: \(Self.describe(status))" }
        }
        return status
    }
    #endif
}
