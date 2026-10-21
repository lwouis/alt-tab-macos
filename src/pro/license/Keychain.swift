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

    /// Updates our own item in place, and only adds when there is nothing readable there. Never deletes
    /// first: where writes fail but reads work (a locked or password-drifted login keychain returns
    /// `errSecAuthFailed` on write), a delete-then-add destroys a working license and cannot put it back.
    ///
    /// The read gate keeps us off items belonging to another code signature. `SecItemUpdate` needs no ACL
    /// authorization, so a differently-signed build (a local dev build next to a released one: same bundle
    /// id, same service) would silently overwrite the real license and leave the item unreadable to both.
    /// Letting `SecItemAdd` fail with `errSecDuplicateItem` keeps that visible, as it was before.
    @discardableResult
    func setValue(_ value: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = value.data(using: .utf8)!
        if self.value(account: account) != nil {
            let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            // errSecItemNotFound: it vanished between the read and the update, so fall through to the add.
            if status != errSecItemNotFound {
                if status != errSecSuccess {
                    Logger.error { "keychain update account=\(account) failed: \(Self.describe(status))" }
                }
                return status
            }
        }
        var addQuery = query
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
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
    /// Wipe every keychain entry under `service`. macOS's file-based keychain deletes only the first
    /// match without an explicit limit; LIVE-STORE-01 verifies all three fixture accounts disappear.
    @discardableResult
    func removeAll() -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            Logger.error { "keychain wipe service=\(service) failed: \(Self.describe(status))" }
        }
        return status
    }
    #endif
}
