class ApplicationDiscriminator {
    static func isActualApplication(_ processIdentifier: pid_t, _ bundleIdentifier: String?,
                                    evidence: ApplicationAdmissionEvidence = .discovery) -> Bool {
        // an app can start with .activationPolicy == .prohibited, then transition to != .prohibited later
        // an app can be both activationPolicy == .accessory and XPC (e.g. com.apple.dock.etci)
        let isZombie = processIdentifier.isZombie()
        guard !isZombie else {
            Logger.debug { logTemplate("zombie process", processIdentifier, bundleIdentifier) }
            return false
        }
        let isWindowManager = bundleIdentifier == ApplicationAdmissionResolver.windowManagerBundleId
        // the bundle id alone refuses the window manager, so it never pays the process-type IPC below
        let isXpc = !isWindowManager && !isNotXpc(processIdentifier, bundleIdentifier)
        let isKnownUserFacingException = isXpc && (isPasswords(bundleIdentifier)
            || isAndroidEmulator(bundleIdentifier, processIdentifier))
        guard ApplicationAdmissionResolver.accepts(isXpc: isXpc, isZombie: false,
                  isKnownUserFacingException: isKnownUserFacingException, isWindowManager: isWindowManager,
                  evidence: evidence) else {
            let reason = isWindowManager ? "window manager" : "XPC process without attention"
            Logger.debug { logTemplate(reason, processIdentifier, bundleIdentifier) }
            return false
        }
        Logger.debug { logTemplate(nil, processIdentifier, bundleIdentifier) }
        return true
    }

    private static func logTemplate(_ rejectionReason: String?, _ processIdentifier: pid_t, _ bundleIdentifier: String?) -> String {
        "Application \(rejectionReason == nil ? "accepted" : "rejected") (pid:\(processIdentifier) \(bundleIdentifier ?? "nil"))\(rejectionReason == nil ? "" : " because \(rejectionReason!)")"
    }

    /// A process's type is fixed for its whole life, but this verdict was re-bought every time: the refusal
    /// memo in `Applications` only short-circuits `.discovery`, so every `.attention` lookup for a pid already
    /// classified paid two Carbon IPCs again. Memoised per pid, guarded by the bundle id for the same reason
    /// `RefusedApplication` is: macOS reuses pids, and an answer that outlived its process would classify the
    /// process that inherited the number. Entries are dropped in `Applications.removeRunningApplications`.
    ///
    /// Locked, not main-thread-confined: `isActualApplication` is called off-main from `ProcessCallScheduler`
    /// (the discovery sweep) AND on main from `Applications.findOrCreate` (the AX/WindowServer new-pid path).
    private static var xpcByPid = [pid_t: (bundleId: String?, isXpc: Bool)]()
    private static let xpcLock: UnsafeMutablePointer<os_unfair_lock> = {
        let p = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        p.initialize(to: os_unfair_lock())
        return p
    }()

    static func forgetProcess(_ processIdentifier: pid_t) {
        os_unfair_lock_lock(xpcLock)
        xpcByPid[processIdentifier] = nil
        os_unfair_lock_unlock(xpcLock)
    }

    private static func isNotXpc(_ processIdentifier: pid_t, _ bundleIdentifier: String?) -> Bool {
        os_unfair_lock_lock(xpcLock)
        let memo = xpcByPid[processIdentifier]
        os_unfair_lock_unlock(xpcLock)
        if let memo, memo.bundleId == bundleIdentifier { return !memo.isXpc }
        // these private APIs are more reliable than Bundle.init? as it can return nil (e.g. for com.apple.dock.etci)
        var psn = ProcessSerialNumber()
        GetProcessForPID(processIdentifier, &psn)
        var info = ProcessInfoRec()
        GetProcessInformation(&psn, &info)
        let notXpc = String(info.processType) != "XPC!"
        os_unfair_lock_lock(xpcLock)
        xpcByPid[processIdentifier] = (bundleIdentifier, !notXpc)
        os_unfair_lock_unlock(xpcLock)
        return notXpc
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
