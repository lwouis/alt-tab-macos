import Cocoa
import Darwin
import LetsMove
import ShortcutRecorder
import AppCenterCrashes

class App: AppCenterApplication {
    /// periphery:ignore
    static let activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Prevent App Nap to preserve responsiveness")
    static let bundleIdentifier = Bundle.main.bundleIdentifier!
    static let bundleURL = Bundle.main.bundleURL
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static let website = "https://alt-tab-macos.netlify.app"
    static let appIcon = CGImage.named("app.icns")
    override class var shared: App { super.shared as! App }
    static var supportProjectAction: Selector { #selector(App.supportProject) }
    static var isTerminating = false
    static var appIsBeingUsed = false
    static var shortcutIndex = 0
    static var forceDoNothingOnRelease = false
    private static var isFirstSummon = true
    private static var isVeryFirstSummon = true
    // periphery:ignore
    private static var appCenterDelegate: AppCenterCrash?
    // don't queue multiple delayed rebuildUi() calls
    private static var delayedDisplayScheduled = 0
    private static var lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private static var nextRefreshScheduled = false

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

    static func hideUi(_ keepPreview: Bool = false) {
        Logger.info { "appIsBeingUsed:\(appIsBeingUsed)" }
        guard appIsBeingUsed else { return } // already hidden
        appIsBeingUsed = false
        isFirstSummon = true
        forceDoNothingOnRelease = false
        TilesView.endSearchSession()
        CursorEvents.toggle(false)
        TrackpadEvents.reset()
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            PreviewPanel.shared.orderOut(nil)
        }
        hideAllTooltips()
        MainMenu.toggle(enabled: true)
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
        initializeSettingsWindowIfNeeded()
        showSecondaryWindow(SettingsWindow.shared!)
        if SettingsWindow.shared!.isVisible != true {
            let window = SettingsWindow()
            showSecondaryWindow(window)
            window.orderFrontRegardless()
        }
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
        refreshOpenUiWithThrottling {
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

    static func refreshOpenUiWithThrottling(_ block: @escaping () -> Void) {
        let throttleDelayInMs = 200
        let now = DispatchTime.now().uptimeNanoseconds
        let (elapsedInNanoseconds, overflow) = now.subtractingReportingOverflow(lastRefreshTimeInNanoseconds)
        let timeSinceLastRefreshInMs = overflow ? 0 : Float(elapsedInNanoseconds) / 1_000_000
        if timeSinceLastRefreshInMs >= Float(throttleDelayInMs) {
            lastRefreshTimeInNanoseconds = now
            block()
            return
        }
        guard !nextRefreshScheduled else { return }
        nextRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(throttleDelayInMs + 10)) {
            nextRefreshScheduled = false
            refreshOpenUiWithThrottling(block)
        }
    }

    static func showUiOrCycleSelection(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool) {
        forceDoNothingOnRelease = forceDoNothingOnRelease_
        Logger.debug { "isFirstSummon:\(isFirstSummon) shortcutIndex:\(shortcutIndex)" }
        appIsBeingUsed = true
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
        MainMenu.loadFromXib()
        _ = TilesPanel()
        _ = PreviewPanel()
        Spaces.refresh()
        Screens.refresh()
        SpacesEvents.observe()
        ScreensEvents.observe()
        SystemAppearanceEvents.observe()
        SystemScrollerStyleEvents.observe()
        Applications.initialDiscovery()
        KeyboardEvents.addEventHandlers()
        CursorEvents.observe()
        TrackpadEvents.observe()
        CliEvents.observe()
        PreferencesEvents.initialize()
        BenchmarkRunner.startIfNeeded()
        showSettingsWindowOnFirstLaunchIfNeeded()
        #if DEBUG
//            App.showSettingsWindow()
        #endif
        Logger.info { "Finished launching AltTab" }
    }
}

extension App: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
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
        setNativeCommandTabEnabled(true)
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
