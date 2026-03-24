class ApplicationDiscriminator {
    static func isActualApplication(_ processIdentifier: pid_t, _ bundleIdentifier: String?) -> Bool {
        // an app can start with .activationPolicy == .prohibited, then transition to != .prohibited later
        // an app can be both activationPolicy == .accessory and XPC (e.g. com.apple.dock.etci)
        guard isNotXpc(processIdentifier) || isPasswords(bundleIdentifier) || isAndroidEmulator(bundleIdentifier, processIdentifier) else {
            Logger.debug { logTemplate("XPC process", processIdentifier, bundleIdentifier) }
            return false
        }
        guard !processIdentifier.isZombie() else {
            Logger.debug { logTemplate("zombie process", processIdentifier, bundleIdentifier) }
            return false
        }
        Logger.debug { logTemplate(nil, processIdentifier, bundleIdentifier) }
        return true
    }

    private static func logTemplate(_ rejectionReason: String?, _ processIdentifier: pid_t, _ bundleIdentifier: String?) -> String {
        "Application \(rejectionReason == nil ? "accepted" : "rejected") (pid:\(processIdentifier) \(bundleIdentifier ?? "nil"))\(rejectionReason == nil ? "" : " because \(rejectionReason!)")"
    }

    private static func isNotXpc(_ processIdentifier: pid_t) -> Bool {
        // these private APIs are more reliable than Bundle.init? as it can return nil (e.g. for com.apple.dock.etci)
        var psn = ProcessSerialNumber()
        GetProcessForPID(processIdentifier, &psn)
        var info = ProcessInfoRec()
        GetProcessInformation(&psn, &info)
        return String(info.processType) != "XPC!"
    }

    private static func isPasswords(_ bundleIdentifier: String?) -> Bool {
        return bundleIdentifier == "com.apple.Passwords"
    }

    static func isAndroidEmulator(_ bundleIdentifier: String?, _ processIdentifier: pid_t) -> Bool {
        // NSRunningApplication provides no way to identify the emulator; we pattern match on its KERN_PROCARGS
        if bundleIdentifier == nil,
           let executablePath = Sysctl.run([CTL_KERN, KERN_PROCARGS, processIdentifier]) {
            // example path: ~/Library/Android/sdk/emulator/qemu/darwin-x86_64/qemu-system-x86_64
            return executablePath.range(of: "qemu-system[^/]*$", options: .regularExpression, range: nil, locale: nil) != nil
        }
        return false
    }
}
