import Foundation
import IOKit

enum MachineFingerprint {
    private static let keychainAccount = "machineFingerprint"

    /// IOKit-based UUID with a keychain fallback (so activation and subsequent revalidation
    /// see the same id even if IOKit starts returning a different value for any reason).
    static func get(keychain: Keychain) -> String {
        // kIOMainPortDefault (macOS 12+) / kIOMasterPortDefault (pre-12) both equal 0; passing 0 avoids the deprecation.
        let service = IOServiceGetMatchingService(0, IOServiceMatching("IOPlatformExpertDevice"))
        defer { IOObjectRelease(service) }
        if let uuid = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            return uuid
        }
        if let stored = keychain.value(account: keychainAccount) { return stored }
        let generated = UUID().uuidString
        keychain.setValue(generated, account: keychainAccount)
        return generated
    }
}
