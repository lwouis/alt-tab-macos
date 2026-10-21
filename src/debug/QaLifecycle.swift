#if DEBUG
import Cocoa
import Security

/// Lifecycle QA keeps the real app, storage and UI. Permission replies and request effects
/// stay in memory; trial time and the disposable license namespace are controlled.
enum QaLifecycle {
    static var session: String? { QaLifecycleEnvironment.session }
    static var enabled: Bool { QaLifecycleEnvironment.enabled }
    static var now: Date? {
        get { QaLifecycleEnvironment.now }
        set { QaLifecycleEnvironment.now = newValue }
    }
    static var finishedLaunching = false
    static var actions = [String]()
    static var launchCount = 0
    private static let permissionLock = NSLock()
    private static var permissionValues: [Bool] = {
        let mode = CommandLine.arguments.first { $0.hasPrefix("--qa-permissions=") }
            .map { String($0.dropFirst("--qa-permissions=".count)) } ?? "granted"
        switch mode {
        case "new": return [false, false, true, true]
        case "denied": return [false, false, false, false]
        case "screen": return [true, false, false, false]
        case "accessibility": return [false, true, false, false]
        default: return [true, true, false, false]
        }
    }()

    static func permission(_ index: Int) -> Bool {
        permissionLock.lock()
        defer { permissionLock.unlock() }
        return permissionValues[index]
    }

    static func recordPermissionRequest(_ service: String, prompt: Bool) {
        actions.append("\(prompt ? "permissionPrompt" : "permissionPane"):\(service)")
        permissionLock.lock()
        permissionValues[service == "kTCCServiceAccessibility" ? 2 : 3] = false
        permissionLock.unlock()
    }

    static var restartArguments: [String] {
        let mode = permission(0) ? (permission(1) ? "granted" : "screen") : (permission(1) ? "accessibility" : "denied")
        return CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--qa-permissions=") } + ["--qa-permissions=\(mode)"]
    }
    static var licenseService: String { "\(App.bundleIdentifier).qa.lifecycle.\(session!)" }
    static var licenseSuite: String { "\(App.bundleIdentifier).qa.lifecycle.\(session!)" }

    struct Request: Decodable {
        let action: String
        var day: Int?
        var fresh: Bool?
        var completed: Bool?
        var welcome: Bool?
        var text: String?
        var key: String?
        var value: String?
        var hour: Int?
        var seconds: Double?
        var seen: [String]?
        var accessibility: Bool?
        var screenRecording: Bool?
    }

    struct Surface: Codable {
        let name: String
        let number: Int
        let texts: [String]
        let buttons: [String]
        let purchaseHasReturn: Bool
        let width: Double
        let height: Double
        let layoutIssues: [String]
    }

    struct Snapshot: Codable {
        let session: String
        let pid: Int32
        let ready: Bool
        let launchCount: Int
        let accessibility: String
        let screenRecording: String
        let axEntryAbsent: Bool?
        let screenEntryAbsent: Bool?
        let permissionsMocked: Bool
        let license: String
        let lifetime: Bool?
        let trialStart: Double?
        let day: Int
        let welcomeSeen: Bool
        let completed: Bool
        let pending: Bool
        let freePass: Bool
        let badge: Bool
        let badgeDrawn: Bool
        let switcher: Bool
        let actions: [String]
        let surfaces: [Surface]
        let error: String?
    }

    static func command(_ raw: String) -> Codable? {
        guard enabled, raw.hasPrefix("--qa-lifecycle=") else { return nil }
        guard let data = Data(base64Encoded: String(raw.dropFirst("--qa-lifecycle=".count))),
              let request = try? JSONDecoder().decode(Request.self, from: data) else { return snapshot("Malformed lifecycle request") }
        do {
            try execute(request)
            return snapshot(nil)
        } catch { return snapshot(String(describing: error)) }
    }

    private static func execute(_ r: Request) throws {
        switch r.action {
        case "state": break
        case "seed": try seed(r)
        case "advance", "travel":
            guard let start = LicenseManager.shared.trialStartDate, let day = r.day, day > 0 else { throw QaError("A trial and positive day are required") }
            let date = start.addingTimeInterval(Double(day - 1) * 86400 + (r.seconds ?? 0))
            guard r.action == "travel" else { now = date; LicenseManager.shared.refreshState(); break }
            // `travel` moves only the clock, like a Mac left running overnight; the app must notice by itself. The
            // clock keeps ticking from there, so timers armed against it fire.
            now = nil
            QaLifecycleEnvironment.menuClockOffset = date.timeIntervalSinceNow
        case "startup": App.replayFirstLaunchForQa()
        case "schedule":
            // A launch draws the menu bar icon before it arms the scheduler.
            Menubar.menubarIconCallback(nil)
            ProTransitionManager.shared.onAppLaunchComplete()
        case "permissions":
            permissionLock.lock()
            if let value = r.accessibility { permissionValues[0] = value }
            if let value = r.screenRecording { permissionValues[1] = value }
            permissionLock.unlock()
            SystemPermissions.checkPermissionsSoon()
        case "open-permissions": App.showPermissionsWindow()
        case "open-settings": App.showSettingsWindow()
        case "request-accessibility": AccessibilityPermission.request()
        case "request-screen": ScreenRecordingPermission.request()
        case "skip-screen": ScreenRecordingPermission.waive()
        case "unskip-screen": ScreenRecordingPermission.unwaive()
        case "click": try click(r.text ?? "")
        case "purchase": try purchase(r.value ?? "pro")
        case "search": _ = ProFeature.searchInSwitcher.attemptUse()
        case "extra-shortcut": _ = ProFeature.extraShortcut(index: 1).attemptUse()
        case "preference":
            guard let key = r.key, let value = r.value, ["appearanceStyle", "appearanceSize", "shortcutStyle", "screenRecordingPermissionSkipped"].contains(key) else { throw QaError("Unsupported preference") }
            Preferences.set(key, value)
        case "keychain": try keychainRoundTrip()
        case "close": closeSurfaces()
        default: throw QaError("Unknown lifecycle action")
        }
    }

    private static func seed(_ r: Request) throws {
        App.hideUi()
        closeSurfaces()
        OnboardingPopover.closeForQa()
        let manager = ProTransitionManager.shared
        manager.clearSessionForQa()
        let store = LicenseManager.shared.defaults
        UserDefaults.standard.removePersistentDomain(forName: licenseSuite)
        guard store.synchronize() else { throw QaError("Could not clear QA license defaults") }
        let status = SystemKeychain(service: licenseService).removeAll()
        guard status == errSecSuccess || status == errSecItemNotFound else { throw QaError("Could not clear QA keychain: \(status)") }
        for key in ["appearanceStyle", "shortcutStyle"] { Preferences.set(key, "0", false) }
        let clock = Calendar.current.date(bySettingHour: r.hour ?? 10, minute: 0, second: 0, of: Date())!
        now = clock
        store.set(clock.addingTimeInterval(-Double((r.day ?? 1) - 1) * 86400).timeIntervalSince1970, forKey: "trialStartDate")
        ProTransitionState.markFreshInstallIfUnknown(r.fresh ?? true)
        manager.hasSeenWelcome = r.welcome ?? true
        for key in r.seen ?? [] {
            guard ["hasSeenDay4Tour", "freePassUsed", "hasTriggeredPostExpirationSwitcher", "hasSeenFullUpgrade",
                   "hasSeenProactiveDay15", "hasSeenDay35", "userOptedOut"].contains(key) else { throw QaError("Unsupported transition flag") }
            store.set(true, forKey: "proTransition.\(key)")
        }
        Preferences.set("settingsWindowShownOnFirstLaunch", r.completed == false ? "false" : "true", false)
        Preferences.remove("onboardingShortcutUsed", false)
        // Refreshing a paid fixture into a trial can arm Welcome before the test relaunches into setup.
        manager.state.onboardingInProgress = r.completed == false && r.fresh != false
        LicenseManager.shared.refreshState()
        actions.removeAll(keepingCapacity: true)
        guard store.synchronize() && UserDefaults.standard.synchronize() else { throw QaError("Could not persist QA fixture") }
    }

    private static func purchase(_ variant: String) throws {
        guard ["pro", "pro_lifetime"].contains(variant) else { throw QaError("Unsupported license variant") }
        let license = LicenseManager.shared
        for (account, value) in [(LicenseManager.keychainKeyAccount, "qa-\(session!)"), (LicenseManager.keychainInstanceAccount, "qa-instance"), (LicenseManager.keychainVariantAccount, variant)] {
            let status = license.keychain.setValue(value, account: account)
            guard status == errSecSuccess else { throw QaError("Real keychain write failed: \(status)") }
        }
        license.defaults.set(true, forKey: "lastValidationResult")
        license.defaults.set(license.clock.now.timeIntervalSince1970, forKey: "lastValidation")
        license.onBeforeProUnlock()
        license.refreshState()
    }

    private static func keychainRoundTrip() throws {
        let keychain = SystemKeychain(service: licenseService)
        let account = "roundTrip"
        let accounts = [account, "roundTripSecond", "roundTripThird"]
        defer { accounts.forEach { keychain.remove(account: $0) } }
        guard keychain.value(account: account) == nil else { throw QaError("QA keychain item unexpectedly exists") }
        guard keychain.setValue("first", account: account) == errSecSuccess, keychain.value(account: account) == "first",
              keychain.setValue("second", account: account) == errSecSuccess, keychain.value(account: account) == "second",
              keychain.remove(account: account) == errSecSuccess, keychain.value(account: account) == nil else {
            throw QaError("Real Security read/add/update/delete did not round-trip")
        }
        for account in accounts {
            guard keychain.setValue("fixture", account: account) == errSecSuccess else { throw QaError("Could not write cleanup fixture") }
        }
        guard keychain.removeAll() == errSecSuccess, accounts.allSatisfy({ keychain.value(account: $0) == nil }) else {
            throw QaError("QA keychain cleanup must remove every matching account")
        }
        actions.append("keychainRoundTrip")
    }

    static func closeSurfaces() {
        ProPromptHost.windowPresentation.cancel()
        ProPromptPopover.closeAll()
        ProActivationPopover.close()
        for window in NSApp.windows where window is ProPromptWindow || window is SettingsWindow { window.close() }
    }

    private static func click(_ text: String) throws {
        let matches = NSApp.windows.filter(\.isVisible).compactMap(\.contentView).flatMap(controls).filter { $0.title == text && $0.isEnabled }
        guard matches.count == 1 else { throw QaError("Expected one visible button ‘\(text)’, got \(matches.count)") }
        matches[0].performClick(nil)
    }

    private static func controls(_ view: NSView) -> [NSButton] {
        guard !view.isHidden else { return [] }
        if let button = view as? NSButton { return [button] }
        return view.subviews.flatMap(controls)
    }

    private static func texts(_ view: NSView) -> [String] {
        guard !view.isHidden else { return [] }
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap(texts)
    }

    private static func layoutIssues(_ view: NSView, _ root: NSView) -> [String] {
        guard !view.isHidden else { return [] }
        var issues = [String]()
        if view is NSTextField || view is NSButton {
            let frame = view.convert(view.bounds, to: root)
            if frame.width <= 0 || frame.height <= 0 || !root.bounds.insetBy(dx: -1, dy: -1).contains(frame) {
                issues.append("\(type(of: view)): \(frame), root: \(root.bounds)")
            }
        }
        return issues + view.subviews.flatMap { layoutIssues($0, root) }
    }

    static func cleanup(_ session: String) -> Int32 {
        guard let id = UUID(uuidString: session)?.uuidString else { return 2 }
        let name = App.bundleIdentifier + ".qa.lifecycle." + id
        let status = SystemKeychain(service: name).removeAll()
        guard status == errSecSuccess || status == errSecItemNotFound else { return 1 }
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults.standard.synchronize() ? 0 : 1
    }

    static func snapshot(_ error: String?) -> Snapshot {
        let surfaces = NSApp.windows.filter { $0.isVisible && !($0 is QAMenu) }.map { window -> Surface in
            let buttons = window.contentView.map(controls) ?? []
            return Surface(name: OnboardingPopover.ownsForQa(window) ? "OnboardingPopover" : String(describing: type(of: window)), number: window.windowNumber,
                texts: window.contentView.map(texts) ?? [], buttons: buttons.map(\.title),
                purchaseHasReturn: buttons.contains { $0.title == NSLocalizedString("Get Pro", comment: "") && !$0.keyEquivalent.isEmpty },
                width: window.frame.width, height: window.frame.height,
                layoutIssues: window.contentView.map { layoutIssues($0, $0) } ?? [])
        }
        guard SystemPermissions.preStartupPermissionsPassed else {
            return Snapshot(session: session!, pid: getpid(), ready: false, launchCount: 0,
                accessibility: String(describing: AccessibilityPermission.status), screenRecording: String(describing: ScreenRecordingPermission.status),
                axEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceAccessibility"), screenEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceScreenCapture"),
                permissionsMocked: true,
                license: "notInitialized", lifetime: nil, trialStart: nil, day: 0, welcomeSeen: false, completed: false,
                pending: false, freePass: false, badge: false, badgeDrawn: false, switcher: false, actions: actions, surfaces: surfaces, error: error)
        }
        let manager = ProTransitionManager.shared
        let license = LicenseManager.shared
        return Snapshot(session: session!, pid: getpid(), ready: finishedLaunching, launchCount: launchCount,
            accessibility: String(describing: AccessibilityPermission.status), screenRecording: String(describing: ScreenRecordingPermission.status),
            axEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceAccessibility"), screenEntryAbsent: SystemPermissions.hasNoEntry("kTCCServiceScreenCapture"),
            permissionsMocked: true,
            license: String(describing: license.state), lifetime: license.isLifetimeVariant, trialStart: license.trialStartDate?.timeIntervalSince1970,
            day: license.daysSinceTrialStart + 1, welcomeSeen: manager.hasSeenWelcome,
            completed: Preferences.settingsWindowShownOnFirstLaunch, pending: manager.hasPendingPrompt,
            freePass: manager.isFreePassSessionActive, badge: manager.shouldShowBadgeDot, badgeDrawn: Menubar.badgeDotLayer != nil, switcher: TilesPanel.shared?.isVisible == true,
            actions: actions, surfaces: surfaces, error: error)
    }

    struct QaError: Error, CustomStringConvertible {
        let description: String
        init(_ text: String) { description = text }
    }
}
#endif
