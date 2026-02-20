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
    static var supportProjectAction: Selector { #selector(App.app.supportProject) }
    static var app: App!
    var isTerminating = false
    var tilesPanel: TilesPanel!
    var previewPanel: PreviewPanel!
    var appIsBeingUsed = false
    var shortcutIndex = 0
    var forceDoNothingOnRelease = false
    var settingsWindow: SettingsWindow!
    var aboutWindow: AboutWindow!
    var permissionsWindow: PermissionsWindow?
    private var feedbackWindow: FeedbackWindow!
    private var debugWindow: DebugWindow!
    private var isFirstSummon = true
    private var isVeryFirstSummon = true
    // periphery:ignore
    private var appCenterDelegate: AppCenterCrash?
    // don't queue multiple delayed rebuildUi() calls
    private var delayedDisplayScheduled = 0
    private var lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
    private var nextRefreshScheduled = false

    override init() {
        super.init()
        delegate = self
        App.app = self
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// we put application code here which should be executed on init() and Preferences change
    func resetPreferencesDependentComponents() {
        tilesPanel.tilesView.reset()
    }

    func restart() {
        // we use -n to open a new instance, to avoid calling applicationShouldHandleReopen
        // we use Bundle.main.bundlePath in case of multiple AltTab versions on the machine
        printStackTrace()
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
        App.shared.terminate(self)
    }

    func hideUi(_ keepPreview: Bool = false) {
        Logger.info { "appIsBeingUsed:\(self.appIsBeingUsed)" }
        guard appIsBeingUsed else { return } // already hidden
        appIsBeingUsed = false
        isFirstSummon = true
        forceDoNothingOnRelease = false
        tilesPanel.tilesView.endSearchSession()
        CursorEvents.toggle(false)
        TrackpadEvents.reset()
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            previewPanel.orderOut(nil)
        }
        hideAllTooltips()
        MainMenu.toggle(enabled: true)
    }

    /// some tooltips may not be hidden when the main window is hidden; we force it through a private API
    private func hideAllTooltips() {
        let selector = NSSelectorFromString("abortAllToolTips")
        if NSApp.responds(to: selector) {
            NSApp.perform(selector)
        }
    }

    /// we don't want another window to become key when the TilesPanel is hidden
    func hideTilesPanelWithoutChangingKeyWindow() {
        allSecondaryWindowsCanBecomeKey(false)
        tilesPanel.orderOut(nil)
        allSecondaryWindowsCanBecomeKey(true)
    }

    private func allSecondaryWindowsCanBecomeKey(_ canBecomeKey_: Bool) {
        settingsWindow?.canBecomeKey_ = canBecomeKey_
        aboutWindow?.canBecomeKey_ = canBecomeKey_
        permissionsWindow?.canBecomeKey_ = canBecomeKey_
        feedbackWindow?.canBecomeKey_ = canBecomeKey_
        debugWindow?.canBecomeKey_ = canBecomeKey_
    }

    func closeSelectedWindow() {
        Windows.selectedWindow()?.close()
    }

    func minDeminSelectedWindow() {
        Windows.selectedWindow()?.minDemin()
    }

    func toggleFullscreenSelectedWindow() {
        Windows.selectedWindow()?.toggleFullscreen()
    }

    func quitSelectedApp() {
        Windows.selectedWindow()?.application.quit()
    }

    func hideShowSelectedApp() {
        Windows.selectedWindow()?.application.hideOrShow()
    }

    func toggleSearchMode() {
        guard appIsBeingUsed else { return }
        tilesPanel.tilesView.toggleSearchModeFromShortcut()
    }

    func lockSearchMode() {
        guard appIsBeingUsed, tilesPanel.tilesView.isSearchModeOn else { return }
        tilesPanel.tilesView.lockSearchMode()
    }

    func cancelSearchModeOrHideUi() {
        guard appIsBeingUsed else { return }
        if tilesPanel.tilesView.isSearchModeOn {
            tilesPanel.tilesView.disableSearchMode()
        } else {
            hideUi()
        }
    }

    func focusTarget() {
        guard appIsBeingUsed else { return } // already hidden
        let selectedWindow = Windows.selectedWindow()
        Logger.info { selectedWindow?.debugId }
        focusSelectedWindow(selectedWindow)
    }

    @objc func checkForUpdatesNow(_ sender: NSMenuItem) {
        GeneralTab.checkForUpdatesNow(sender)
    }

    @objc func checkPermissions(_ sender: NSMenuItem) {
        showPermissionsWindow()
    }

    @objc func supportProject() {
        NSWorkspace.shared.open(URL(string: App.website + "/support")!)
    }

    @objc func showFeedbackPanel() {
        showSecondaryWindow(getOrCreateFeedbackWindow())
    }

    @objc func showDebugWindow() {
        showSecondaryWindow(getOrCreateDebugWindow())
    }

    @objc func showSettingsWindow() {
        showSecondaryWindow(getOrCreateSettingsWindow())
        if settingsWindow?.isVisible != true {
            settingsWindow = SettingsWindow()
            showSecondaryWindow(settingsWindow)
            settingsWindow?.orderFrontRegardless()
        }
    }

    @objc func showAboutWindow() {
        showSecondaryWindow(getOrCreateAboutWindow())
    }

    func showSecondaryWindow(_ window: NSWindow?) {
        if let window {
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
    }

    private func getOrCreateSettingsWindow() -> SettingsWindow {
        if settingsWindow == nil {
            settingsWindow = SettingsWindow()
        }
        return settingsWindow
    }

    private func getOrCreateAboutWindow() -> AboutWindow {
        if aboutWindow == nil {
            aboutWindow = AboutWindow()
        }
        return aboutWindow
    }

    private func getOrCreateFeedbackWindow() -> FeedbackWindow {
        if feedbackWindow == nil {
            feedbackWindow = FeedbackWindow()
        }
        return feedbackWindow
    }

    private func getOrCreateDebugWindow() -> DebugWindow {
        if debugWindow == nil {
            debugWindow = DebugWindow()
        }
        return debugWindow
    }

    private func getOrCreatePermissionsWindow() -> PermissionsWindow {
        if permissionsWindow == nil {
            permissionsWindow = PermissionsWindow()
        }
        return permissionsWindow!
    }

    @discardableResult
    private func showSettingsWindowOnFirstLaunchIfNeeded() -> Bool {
        guard !Preferences.settingsWindowShownOnFirstLaunch else { return false }
        showSettingsWindow()
        Preferences.markSettingsWindowShownOnFirstLaunch()
        return true
    }

    func showPermissionsWindow() {
        getOrCreatePermissionsWindow().show()
    }

    func showUi(_ shortcutIndex: Int) {
        showUiOrCycleSelection(shortcutIndex, true)
    }

    @objc func showUiFromShortcut0() {
        showUi(0)
    }

    func cycleSelection(_ direction: Direction, allowWrap: Bool = true) {
        if direction == .up || direction == .down {
            tilesPanel.tilesView.navigateUpOrDown(direction, allowWrap: allowWrap)
        } else {
            Windows.cycleSelectedWindowIndex(direction.step(), allowWrap: allowWrap)
        }
    }

    func previousWindowShortcutWithRepeatingKey() {
        cycleSelection(.trailing)
        KeyRepeatTimer.startRepeatingKeyPreviousWindow()
    }

    func focusSelectedWindow(_ selectedWindow: Window?) {
        guard appIsBeingUsed else { return } // already hidden
        hideUi(true)
        if let window = selectedWindow, MissionControl.state() == .inactive || MissionControl.state() == .showDesktop {
            window.focus()
            if Preferences.cursorFollowFocus == .always || (
                Preferences.cursorFollowFocus == .differentScreen && (Spaces.screenSpacesMap.first { $0.value.contains { space in window.spaceIds.contains(space) } })?.key != NSScreen.active()?.cachedUuid()) {
                moveCursorToSelectedWindow(window)
            }
        } else {
            previewPanel.orderOut(nil)
        }
    }

    func moveCursorToSelectedWindow(_ window: Window) {
        let referenceWindow = window.referenceWindowForTabbedWindow()
        guard let position = referenceWindow?.position, let size = referenceWindow?.size else { return }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        CGWarpMouseCursorPosition(point)
    }

    func refreshOpenUiAfterExternalEvent(_ windowsToScreenshot: [Window], windowRemoved: Bool = false) {
        Windows.refreshThumbnailsAsync(windowsToScreenshot, .refreshUiAfterExternalEvent, windowRemoved: windowRemoved)
        refreshOpenUiWithThrottling {
            guard self.appIsBeingUsed else { return }
            if !Windows.updatesBeforeShowing() { self.hideUi(); return }
            self.refreshUi(true)
        }
    }

    func refreshUi(_ preserveScrollPosition: Bool = false) {
        guard self.appIsBeingUsed else { return }
        let preservedScrollOrigin = preserveScrollPosition ? tilesPanel.tilesView.currentScrollOrigin() : nil
        Windows.updateSelectedWindow()
        guard self.appIsBeingUsed else { return }
        self.tilesPanel.updateContents(preservedScrollOrigin)
        guard self.appIsBeingUsed else { return }
        Windows.voiceOverWindow() // at this point TileViews are assigned to the window, and ready
        guard self.appIsBeingUsed else { return }
        Windows.previewSelectedWindowIfNeeded()
        guard self.appIsBeingUsed else { return }
        Applications.refreshBadgesAsync()
    }

    func refreshOpenUiWithThrottling( _ block: @escaping () -> Void) {
        let throttleDelayInMs = 200
        let timeSinceLastRefreshInSeconds = Float(DispatchTime.now().uptimeNanoseconds - lastRefreshTimeInNanoseconds) / 1_000_000
        if timeSinceLastRefreshInSeconds >= Float(throttleDelayInMs) {
            lastRefreshTimeInNanoseconds = DispatchTime.now().uptimeNanoseconds
            block()
            return
        }
        guard !nextRefreshScheduled else { return }
        nextRefreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(throttleDelayInMs + 10)) {
            self.nextRefreshScheduled = false
            self.refreshOpenUiWithThrottling(block)
        }
    }

    func showUiOrCycleSelection(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool) {
        forceDoNothingOnRelease = forceDoNothingOnRelease_
        Logger.debug { "isFirstSummon:\(self.isFirstSummon) shortcutIndex:\(shortcutIndex)" }
        App.app.appIsBeingUsed = true
        if isFirstSummon || shortcutIndex != self.shortcutIndex {
            NSScreen.updatePreferred()
            if isVeryFirstSummon {
                Windows.sortByLevel()
                isVeryFirstSummon = false
            }
            isFirstSummon = false
            self.shortcutIndex = shortcutIndex
            let shouldStartInSearchMode = Preferences.shortcutStyle == .searchOnRelease
            tilesPanel.tilesView.startSearchSession(shouldStartInSearchMode)
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
                    if self.delayedDisplayScheduled == 1 {
                        self.buildUiAndShowPanel()
                    }
                    self.delayedDisplayScheduled -= 1
                }
            }
        } else {
            cycleSelection(.leading)
            KeyRepeatTimer.startRepeatingKeyNextWindow()
        }
    }

    func buildUiAndShowPanel() {
        guard appIsBeingUsed else { return }
        Appearance.update()
        guard appIsBeingUsed else { return }
        refreshUi()
        guard appIsBeingUsed else { return }
        tilesPanel.show()
        if tilesPanel.tilesView.isSearchEditing {
            tilesPanel.tilesView.enableSearchEditing()
        }
        KeyRepeatTimer.startRepeatingKeyNextWindow()
        Windows.refreshThumbnailsAsync(Windows.list, .refreshOnlyThumbnailsAfterShowUi)
    }

    func checkIfShortcutsShouldBeDisabled(_ activeWindow: Window?, _ activeApp: Application?) {
        let app = activeWindow?.application ?? activeApp!
        let shortcutsShouldBeDisabled = Preferences.exceptions.contains { exception in
            if let id = app.bundleIdentifier {
                return id.hasPrefix(exception.bundleIdentifier) &&
                    (exception.ignore == .always || (exception.ignore == .whenFullscreen && (activeWindow?.isFullscreen ?? false)))
            }
            return false
        }
        KeyboardEvents.toggleGlobalShortcuts(shortcutsShouldBeDisabled)
        if shortcutsShouldBeDisabled && App.app.appIsBeingUsed {
            App.app.hideUi()
        }
    }
}

extension App: NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        appCenterDelegate = AppCenterCrash()
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

    func continueAppLaunchAfterPermissionsAreGranted() {
        Logger.info { "System permissions are granted; continuing launch" }
        BackgroundWork.start()
        NSScreen.updatePreferred()
        Appearance.update()
        TilesPanel.updateMaxPossibleThumbnailSize()
        TilesPanel.updateMaxPossibleAppIconSize()
        Menubar.initialize()
        MainMenu.loadFromXib()
        self.tilesPanel = TilesPanel()
        self.previewPanel = PreviewPanel()
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
//            self.showSettingsWindow()
        #endif
        Logger.info { "Finished launching AltTab" }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
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
