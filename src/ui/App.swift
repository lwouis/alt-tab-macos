import Cocoa
import Darwin
import LetsMove
import ShortcutRecorder
import AppCenterCrashes

class App: AppCenterApplication {
    /// periphery:ignore
    static let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Prevent App Nap to preserve responsiveness")
    /// the main AltTab process's bundle identifier. Hardcoded instead of
    /// read from `Bundle.main.bundleIdentifier!` because the Settings helper
    /// runs from a nested `.app` bundle with its own distinct identifier
    /// (`.settings`) so it shows up separately in Activity Monitor. All call
    /// sites using `App.bundleIdentifier` expect to address the *main*
    /// preferences domain / launch agent / CLI port regardless of which
    /// process is running.
    static let bundleIdentifier = "com.lwouis.alt-tab-macos"
    static let bundleURL = Bundle.main.bundleURL
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static let website = "https://alt-tab.app"
    static let appIcon = CGImage.named("app.icns")
    override class var shared: App { super.shared as! App }
    static var supportProjectAction: Selector { #selector(App.supportProject) }
    static var isTerminating = false
    static var appIsBeingUsed = false
    static var shortcutIndex = 0
    static var forceDoNothingOnRelease = false
    /// when launched with `--settings-only`, this process is a short-lived helper whose sole
    /// job is to display the Settings UI and then quit. The main AltTab process launches
    /// one of these on demand so the heavy Settings view tree never gets allocated in the
    /// long-running switcher process.
    static let isSettingsHelper = CommandLine.arguments.contains("--settings-only")
    private static var isFirstSummon = true
    private static var isVeryFirstSummon = true
    private static var pendingShowSettingsWindow = false
    // periphery:ignore
    private static var appCenterDelegate: AppCenterCrash?
    // don't queue multiple delayed rebuildUi() calls
    private static var delayedDisplayScheduled = 0
    private static let refreshOpenUiThrottler = Throttler(delayInMs: 200)

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// we put application code here which should be executed on init() and Preferences change
    static func resetPreferencesDependentComponents() {
        TilesView.reset()
    }

    static func restart() {
        // we use -n to open a new instance, to avoid calling applicationShouldHandleReopen
        // we use Bundle.main.bundlePath in case of multiple AltTab versions on the machine
        printStackTrace()
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
        App.shared.terminate(nil)
    }

    /// minimal launch path taken when this process is a Settings helper
    /// (`--settings-only` CLI flag). We skip switcher initialization: no
    /// ScreenCaptureKit, no AX observers, no menubar, no permissions gate.
    /// The helper only needs preferences + the Settings view tree, and exits
    /// when the user closes the Settings window.
    static func startAsSettingsHelper() {
        Logger.initialize()
        Logger.info { "Launching AltTab Settings helper \(App.version)" }
        AXUIElement.setGlobalTimeout()
        Preferences.initialize()
        // must run before the Settings view tree is built: several views
        // (TileFontIconView, ShowHideIllustratedView, …) read `Appearance.fontHeight`
        // / `Appearance.fontColor` in their init, which are dummy values
        // (`3`, `.red`) until `Appearance.update()` fills them in. Creating
        // an `NSFont` with size ≈ 3 feeds CoreText a degenerate font and
        // crashes inside `TAttributes::ApplyFont` with a nil-dictionary-insert.
        NSScreen.updatePreferred()
        Appearance.update()
        App.shared.setActivationPolicy(.accessory)
        // Defer Settings window creation to the next runloop tick so the
        // NSApplicationDidFinishLaunching notification has already been posted
        // and framework observers are in a consistent state.
        DispatchQueue.main.async {
            initializeSettingsWindowIfNeeded()
            App.shared.activate(ignoringOtherApps: true)
            showSecondaryWindow(SettingsWindow.shared!)
        }
    }

    /// nested sub-bundle name (Activity Monitor / ps display text).
    static let settingsHelperExecName = "AltTabSettings"
    static let settingsHelperDisplayName = "AltTab Settings"
    /// distinct bundle id so LaunchServices treats the helper as its own app
    /// instead of a duplicate instance of the main AltTab (which would cause
    /// LaunchServices to terminate one of the two). Preferences still live in
    /// `App.bundleIdentifier`'s domain -- both processes share that domain via
    /// `Preferences.defaults` regardless of their own bundle id.
    static let settingsHelperBundleId = "\(bundleIdentifier).settings"

    /// lazily materialises `Contents/Helpers/AltTabSettings.app` as a sibling
    /// sub-bundle. Uses a hardlink to the main executable (no extra disk cost,
    /// code signature preserved via copy-on-write semantics of `link(2)`) plus
    /// relative symlinks for Frameworks/Resources so dyld resolves frameworks
    /// from the parent bundle. Returns the helper binary URL, or nil if the
    /// bundle can't be materialised (e.g. app ships on a read-only volume);
    /// callers then fall back to launching the main executable.
    private static func ensureSettingsHelperBundle(primary: URL) -> URL? {
        let fm = FileManager.default
        let helperApp = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("\(settingsHelperExecName).app", isDirectory: true)
        let helperContents = helperApp.appendingPathComponent("Contents", isDirectory: true)
        let helperMacOS = helperContents.appendingPathComponent("MacOS", isDirectory: true)
        let helperBinary = helperMacOS.appendingPathComponent(settingsHelperExecName)
        let helperPlist = helperContents.appendingPathComponent("Info.plist")
        // from `AltTabSettings.app/Contents/Frameworks`, `../../../Frameworks`
        // resolves to `<AltTab.app>/Contents/Frameworks`. kept relative so the
        // sub-bundle keeps working if the main app is moved.
        let sharedLinks: [(name: String, target: String)] = [
            ("Frameworks", "../../../Frameworks"),
            ("Resources", "../../../Resources"),
        ]

        do {
            try fm.createDirectory(at: helperMacOS, withIntermediateDirectories: true)

            // refresh hardlink if stale (different inode after an app upgrade).
            if fm.fileExists(atPath: helperBinary.path) {
                let pi = (try? fm.attributesOfItem(atPath: primary.path)[.systemFileNumber] as? NSNumber)?.uint64Value
                let hi = (try? fm.attributesOfItem(atPath: helperBinary.path)[.systemFileNumber] as? NSNumber)?.uint64Value
                if pi == nil || pi != hi {
                    try? fm.removeItem(atPath: helperBinary.path)
                }
            }
            if !fm.fileExists(atPath: helperBinary.path) {
                try fm.linkItem(atPath: primary.path, toPath: helperBinary.path)
            }

            // start from the main bundle's Info.plist so the helper
            // inherits keys that AppKit / CoreText depend on (e.g.
            // NSPrincipalClass, CFBundleDevelopmentRegion,
            // ATSApplicationFontsPath, LSMinimumSystemVersion,
            // CFBundleSupportedPlatforms). A minimal Info.plist missing
            // these makes CoreText receive nil font attributes inside
            // `TAttributes::ApplyFont` and crash when drawing attributed
            // strings (observed with NSAttributedString.size()).
            var desiredPlist = (Bundle.main.infoDictionary ?? [:])
            // strip keys that Foundation injects at runtime but would look
            // stale if re-serialised to disk (BuildMachineOSBuild, DT*, etc.
            // are fine to keep; these can cause issues when written back).
            for k in ["CFBundleInfoPlistURL", "CFBundleNumericVersion"] {
                desiredPlist.removeValue(forKey: k)
            }
            desiredPlist["CFBundleExecutable"] = settingsHelperExecName
            desiredPlist["CFBundleIdentifier"] = settingsHelperBundleId
            desiredPlist["CFBundleName"] = settingsHelperDisplayName
            desiredPlist["CFBundleDisplayName"] = settingsHelperDisplayName
            desiredPlist["LSUIElement"] = true
            // note: keep `NSPrincipalClass` (`AppCenterApplication`) so NSApp
            // is instantiated as our `App` subclass -- the helper relies on
            // `applicationDidFinishLaunching` to branch on `isSettingsHelper`.
            // Sparkle / AppCenter actual *initialisation* is already guarded
            // behind `isSettingsHelper`, so leaving their Info.plist keys in
            // place is harmless (the frameworks just don't get wired up).
            let desiredData = try PropertyListSerialization.data(fromPropertyList: desiredPlist, format: .xml, options: 0)
            let currentData = try? Data(contentsOf: helperPlist)
            if currentData != desiredData {
                try desiredData.write(to: helperPlist, options: [.atomic])
            }

            for link in sharedLinks {
                let linkPath = helperContents.appendingPathComponent(link.name).path
                let existingTarget = try? fm.destinationOfSymbolicLink(atPath: linkPath)
                if existingTarget == link.target { continue }
                if fm.fileExists(atPath: linkPath) || existingTarget != nil {
                    try? fm.removeItem(atPath: linkPath)
                }
                try fm.createSymbolicLink(atPath: linkPath, withDestinationPath: link.target)
            }

            return helperBinary
        } catch {
            Logger.warning { "Could not materialise \(settingsHelperExecName) sub-bundle: \(error)" }
            return nil
        }
    }

    /// launches a fresh Settings helper subprocess. Prefers the nested
    /// `AltTabSettings.app` sub-bundle so the helper appears distinctly in
    /// Activity Monitor (own `CFBundleName`, own `CFBundleIdentifier`). Falls
    /// back to the main executable if the sub-bundle can't be materialised --
    /// in that degraded mode the two processes share a name but still function.
    private static func launchSettingsHelper() {
        let execName = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "AltTab"
        let primary = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("MacOS")
            .appendingPathComponent(execName)
        let launchURL = ensureSettingsHelperBundle(primary: primary) ?? primary
        let task = Process()
        task.executableURL = launchURL
        task.arguments = ["--settings-only"]
        try? task.run()
    }

    static func hideUi(_ keepPreview: Bool = false) {
        Logger.info { "appIsBeingUsed:\(appIsBeingUsed)" }
        guard appIsBeingUsed else { return } // already hidden
        appIsBeingUsed = false
        isFirstSummon = true
        forceDoNothingOnRelease = false
        UsageStats.resetSession()
        TilesView.endSearchSession()
        ContextMenuEvents.toggle(false)
        CursorEvents.toggle(false)
        TrackpadEvents.reset()
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            PreviewPanel.shared.orderOut(nil)
        }
        hideAllTooltips()
        MainMenu.toggle(true)
    }

    /// some tooltips may not be hidden when the main window is hidden; we force it through a private API
    private static func hideAllTooltips() {
        let selector = NSSelectorFromString("abortAllToolTips")
        if NSApp.responds(to: selector) {
            NSApp.perform(selector)
        }
    }

    /// we don't want another window to become key when the TilesPanel is hidden
    static func hideTilesPanelWithoutChangingKeyWindow() {
        allSecondaryWindowsCanBecomeKey(false)
        TilesPanel.shared.orderOut(nil)
        allSecondaryWindowsCanBecomeKey(true)
    }

    private static func allSecondaryWindowsCanBecomeKey(_ canBecomeKey_: Bool) {
        SettingsWindow.canBecomeKey_ = canBecomeKey_
        AboutWindow.canBecomeKey_ = canBecomeKey_
        PermissionsWindow.canBecomeKey_ = canBecomeKey_
        FeedbackWindow.canBecomeKey_ = canBecomeKey_
        DebugWindow.canBecomeKey_ = canBecomeKey_
    }

    static func closeSelectedWindow() {
        Windows.selectedWindow()?.close()
    }

    static func minDeminSelectedWindow() {
        Windows.selectedWindow()?.minDemin()
    }

    static func toggleFullscreenSelectedWindow() {
        Windows.selectedWindow()?.toggleFullscreen()
    }

    static func quitSelectedApp() {
        Windows.selectedWindow()?.application.quit()
    }

    static func hideShowSelectedApp() {
        Windows.selectedWindow()?.application.hideOrShow()
    }

    static func toggleSearchMode() {
        guard appIsBeingUsed else { return }
        TilesView.toggleSearchModeFromShortcut()
    }

    static func lockSearchMode() {
        guard appIsBeingUsed, TilesView.isSearchModeOn else { return }
        TilesView.lockSearchMode()
    }

    static func cancelSearchModeOrHideUi() {
        guard appIsBeingUsed else { return }
        if TilesView.isSearchModeOn {
            TilesView.disableSearchMode()
        } else {
            hideUi()
        }
    }

    static func focusTarget() {
        guard appIsBeingUsed else { return } // already hidden
        let selectedWindow = Windows.selectedWindow()
        Logger.info { selectedWindow?.debugId }
        focusSelectedWindow(selectedWindow)
    }

    @objc static func checkForUpdatesNow(_ sender: NSMenuItem) {
        GeneralTab.checkForUpdatesNow(sender)
    }

    @objc static func checkPermissions(_ sender: NSMenuItem) {
        showPermissionsWindow()
    }

    @objc static func supportProject() {
        NSWorkspace.shared.open(URL(string: App.website + "/support")!)
    }

    @objc static func showFeedbackPanel() {
        initializeFeedbackWindowIfNeeded()
        showSecondaryWindow(FeedbackWindow.shared!)
    }

    @objc static func showDebugWindow() {
        initializeDebugWindowIfNeeded()
        showSecondaryWindow(DebugWindow.shared!)
    }

    @objc static func showSettingsWindow() {
        // the main (switcher) process never opens Settings in-process: the heavy
        // UI tree would permanently inflate its memory footprint. instead we
        // spawn a short-lived helper subprocess that displays Settings and exits
        // on close. the helper process itself opens Settings inline via
        // `startAsSettingsHelper()` (see `applicationDidFinishLaunching`).
        if !isSettingsHelper {
            guard Menubar.statusItem != nil else {
                pendingShowSettingsWindow = true
                return
            }
            launchSettingsHelper()
            return
        }
        // shared is set to nil in SettingsWindow.close(); initialize here if needed so each open
        // gets a fresh instance (the previous tree is dropped by ARC after the previous close).
        initializeSettingsWindowIfNeeded()
        showSecondaryWindow(SettingsWindow.shared!)
    }

    @objc static func showAboutWindow() {
        initializeAboutWindowIfNeeded()
        showSecondaryWindow(AboutWindow.shared!)
    }

    static func showSecondaryWindow(_ window: NSWindow) {
        NSScreen.updatePreferred()
        App.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // if the window was resized/repositioned by the user, restore the window the way it was
        let restored = window.setFrameUsingName(window.frameAutosaveName)
        if !restored {
            NSScreen.preferred.repositionPanel(window)
            // Use the center function to continue to center, the `repositionPanel` function cannot center, it may be a system bug
            window.center()
        }
    }

    private static func initializeSettingsWindowIfNeeded() {
        if SettingsWindow.shared == nil { _ = SettingsWindow() }
    }

    private static func initializeAboutWindowIfNeeded() {
        if AboutWindow.shared == nil { _ = AboutWindow() }
    }

    private static func initializeFeedbackWindowIfNeeded() {
        if FeedbackWindow.shared == nil { _ = FeedbackWindow() }
    }

    private static func initializeDebugWindowIfNeeded() {
        if DebugWindow.shared == nil { _ = DebugWindow() }
    }

    private static func initializePermissionsWindowIfNeeded() {
        if PermissionsWindow.shared == nil { _ = PermissionsWindow() }
    }

    @discardableResult
    private static func showSettingsWindowOnFirstLaunchIfNeeded() -> Bool {
        guard !Preferences.settingsWindowShownOnFirstLaunch else { return false }
        showSettingsWindow()
        Preferences.markSettingsWindowShownOnFirstLaunch()
        return true
    }

    static func showPermissionsWindow() {
        initializePermissionsWindowIfNeeded()
        PermissionsWindow.show()
    }

    static func showUi(_ shortcutIndex: Int) {
        showUiOrCycleSelection(shortcutIndex, true)
    }

    @objc static func showUiFromShortcut0() {
        showUi(0)
    }

    static func cycleSelection(_ direction: Direction, allowWrap: Bool = true) {
        (TilesView.scrollView?.documentView as? TilesDocumentView)?.cancelDraggingTimer()
        CursorEvents.resetDeadzone()
        if direction == .up || direction == .down {
            TilesView.navigateUpOrDown(direction, allowWrap: allowWrap)
        } else {
            Windows.cycleSelectedWindowIndex(direction.step(), allowWrap: allowWrap)
        }
    }

    static func previousWindowShortcutWithRepeatingKey() {
        cycleSelection(.trailing)
        KeyRepeatTimer.startRepeatingKeyPreviousWindow()
    }

    static func focusSelectedWindow(_ selectedWindow: Window?) {
        guard appIsBeingUsed else { return } // already hidden
        hideUi(true)
        if let window = selectedWindow, MissionControl.state() == .inactive || MissionControl.state() == .showDesktop {
            window.focus()
            if Preferences.cursorFollowFocus == .always || (
                Preferences.cursorFollowFocus == .differentScreen && (Spaces.screenSpacesMap.first { $0.value.contains { space in window.spaceIds.contains(space) } })?.key != NSScreen.active()?.cachedUuid()) {
                moveCursorToSelectedWindow(window)
            }
        } else {
            PreviewPanel.shared.orderOut(nil)
        }
    }

    static func moveCursorToSelectedWindow(_ window: Window) {
        let referenceWindow = window.referenceWindowForTabbedWindow()
        guard let position = referenceWindow?.position, let size = referenceWindow?.size else { return }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        CGWarpMouseCursorPosition(point)
    }

    static func refreshOpenUiAfterExternalEvent(_ windowsToScreenshot: [Window], windowRemoved: Bool = false) {
        Windows.refreshThumbnailsAsync(windowsToScreenshot, .refreshUiAfterExternalEvent, windowRemoved: windowRemoved)
        refreshOpenUiThrottler.throttleOrProceed {
            guard appIsBeingUsed else { return }
            if !Windows.updatesBeforeShowing() { hideUi(); return }
            refreshUi(true)
        }
    }

    static func refreshUi(_ preserveScrollPosition: Bool = false) {
        guard appIsBeingUsed else { return }
        let preservedScrollOrigin = preserveScrollPosition ? TilesView.currentScrollOrigin() : nil
        Windows.updateSelectedWindow()
        guard appIsBeingUsed else { return }
        TilesPanel.shared.updateContents(preservedScrollOrigin)
        guard appIsBeingUsed else { return }
        Windows.voiceOverWindow() // at this point TileViews are assigned to the window, and ready
        guard appIsBeingUsed else { return }
        Windows.previewSelectedWindowIfNeeded()
        guard appIsBeingUsed else { return }
        Applications.refreshBadgesAsync()
    }

    static func showUiOrCycleSelection(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool) {
        forceDoNothingOnRelease = forceDoNothingOnRelease_
        Logger.debug { "isFirstSummon:\(isFirstSummon) shortcutIndex:\(shortcutIndex)" }
        appIsBeingUsed = true
        UsageStats.recordTrigger(shortcutIndex)
        if isFirstSummon || shortcutIndex != App.shortcutIndex {
            NSScreen.updatePreferred()
            if isVeryFirstSummon {
                Windows.sortByLevel()
                isVeryFirstSummon = false
            }
            isFirstSummon = false
            App.shortcutIndex = shortcutIndex
            let shouldStartInSearchMode = Preferences.shortcutStyle == .searchOnRelease
            TilesView.startSearchSession(shouldStartInSearchMode)
            if shouldStartInSearchMode {
                forceDoNothingOnRelease = true
            }
            if !Windows.updatesBeforeShowing() { hideUi(); return }
            Windows.setInitialSelectedAndHoveredWindowIndex()
            if Preferences.windowDisplayDelay == DispatchTimeInterval.milliseconds(0) {
                buildUiAndShowPanel()
            } else {
                delayedDisplayScheduled += 1
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) { () -> () in
                    if delayedDisplayScheduled == 1 {
                        buildUiAndShowPanel()
                    }
                    delayedDisplayScheduled -= 1
                }
            }
        } else {
            cycleSelection(.leading)
            KeyRepeatTimer.startRepeatingKeyNextWindow()
        }
    }

    static func buildUiAndShowPanel() {
        guard appIsBeingUsed else { return }
        Appearance.update()
        guard appIsBeingUsed else { return }
        refreshUi()
        guard appIsBeingUsed else { return }
        TilesPanel.shared.show()
        Windows.previewSelectedWindowIfNeeded()
        if TilesView.isSearchEditing {
            TilesView.enableSearchEditing()
        }
        KeyRepeatTimer.startRepeatingKeyNextWindow()
        Windows.refreshThumbnailsAsync(Windows.list, .refreshOnlyThumbnailsAfterShowUi)
    }

    static func checkIfShortcutsShouldBeDisabled(_ activeWindow: Window?, _ activeApp: Application?) {
        let app = activeWindow?.application ?? activeApp!
        let shortcutsShouldBeDisabled = Preferences.exceptions.contains { exception in
            if let id = app.bundleIdentifier {
                return id.hasPrefix(exception.bundleIdentifier) &&
                    (exception.ignore == .always || (exception.ignore == .whenFullscreen && (activeWindow?.isFullscreen ?? false)))
            }
            return false
        }
        KeyboardEvents.toggleGlobalShortcuts(shortcutsShouldBeDisabled)
        if shortcutsShouldBeDisabled && appIsBeingUsed {
            hideUi()
        }
    }

    static func continueAppLaunchAfterPermissionsAreGranted() {
        Logger.info { "System permissions are granted; continuing launch" }
        BackgroundWork.start()
        NSScreen.updatePreferred()
        Appearance.update()
        TilesPanel.updateMaxPossibleThumbnailSize()
        TilesPanel.updateMaxPossibleAppIconSize()
        Menubar.initialize()
        MainMenu.create()
        _ = TilesPanel()
        _ = PreviewPanel()
        Spaces.refresh()
        Screens.refresh()
        SpacesEvents.observe()
        ScreensEvents.observe()
        SystemAppearanceEvents.observe()
        SystemScrollerStyleEvents.observe()
        InputSourceEvents.observe()
        Applications.initialDiscovery()
        KeyboardEvents.addEventHandlers()
        CursorEvents.observe()
        TrackpadEvents.observe()
        CliEvents.observe()
        PreferencesEvents.initialize()
        // listen for preference edits made by the Settings helper subprocess so
        // the main process re-applies them immediately (hotkeys, menubar, ...).
        CrossProcessPreferencesEvents.observe()
        BenchmarkRunner.startIfNeeded()
        showSettingsWindowOnFirstLaunchIfNeeded()
        if pendingShowSettingsWindow {
            pendingShowSettingsWindow = false
            showSettingsWindow()
        }
        #if DEBUG
//            App.showSettingsWindow()
        #endif
        UsageStats.prune()
        Logger.info { "Finished launching AltTab" }
    }
}

extension App: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if App.isSettingsHelper {
            App.startAsSettingsHelper()
            return
        }
        App.appCenterDelegate = AppCenterCrash()
        App.shared.disableRelaunchOnLogin()
        Logger.initialize()
        Logger.info { "Launching AltTab \(App.version)" }
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        #endif
        #if !DEBUG
        PFMoveToApplicationsFolderIfNecessary()
        #endif
        AXUIElement.setGlobalTimeout()
        Preferences.initialize()
        BackgroundWork.preStart()
        SystemPermissions.ensurePermissionsAreGranted()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        App.showSettingsWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // symbolic hotkeys state persist after the app is quit; we restore this shortcut before quitting
        // the helper subprocess must not touch system-wide state -- the main AltTab
        // process is still running and owns the authoritative cmd-tab override.
        if !App.isSettingsHelper {
            setNativeCommandTabEnabled(true)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Logger.info { "" }
        makeSureAllCapturesAreFinished()
        return .terminateNow
    }
}

enum RefreshCausedBy {
    case refreshOnlyThumbnailsAfterShowUi
    case refreshUiAfterExternalEvent
}
