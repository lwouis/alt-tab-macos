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
    static var app: App!
    var thumbnailsPanel: ThumbnailsPanel!
    var previewPanel: PreviewPanel!
    var preferencesWindow: PreferencesWindow!
    var permissionsWindow: PermissionsWindow!
    var appIsBeingUsed = false
    var shortcutIndex = 0
    private var feedbackWindow: FeedbackWindow!
    private var isFirstSummon = true
    private var isVeryFirstSummon = true
    // periphery:ignore
    private var appCenterDelegate: AppCenterCrash?
    // don't queue multiple delayed rebuildUi() calls
    private var delayedDisplayScheduled = 0

    override init() {
        super.init()
        delegate = self
        App.app = self
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// pre-load some windows so they are faster on first display
    private func preloadWindows() {
        thumbnailsPanel.orderFront(nil)
        thumbnailsPanel.orderOut(nil)
    }

    /// keyboard shortcuts are broken without a menu. We generated the default menu from XCode and load it
    /// see https://stackoverflow.com/a/3746058/2249756
    private func loadMainMenuXib() {
        var menuObjects: NSArray?
        Bundle.main.loadNibNamed("MainMenu", owner: self, topLevelObjects: &menuObjects)
        menu = menuObjects?.first { $0 is NSMenu } as? NSMenu
    }

    /// we put application code here which should be executed on init() and Preferences change
    func resetPreferencesDependentComponents() {
        thumbnailsPanel.thumbnailsView.reset()
    }

    func restart() {
        // we use -n to open a new instance, to avoid calling applicationShouldHandleReopen
        // we use Bundle.main.bundlePath in case of multiple AltTab versions on the machine
        printStackTrace()
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
        App.shared.terminate(self)
    }

    func hideUi(_ keepPreview: Bool = false) {
        Logger.info(appIsBeingUsed)
        guard appIsBeingUsed else { return } // already hidden
        appIsBeingUsed = false
        isFirstSummon = true
        MouseEvents.toggle(false)
        hideThumbnailPanelWithoutChangingKeyWindow()
        if !keepPreview {
            previewPanel.orderOut(nil)
        }
        hideAllTooltips()
    }

    /// some tooltips may not be hidden when the main window is hidden; we force it through a private API
    private func hideAllTooltips() {
        let selector = NSSelectorFromString("abortAllToolTips")
        if NSApp.responds(to: selector) {
            NSApp.perform(selector)
        }
    }

    /// we don't want another window to become key when the thumbnailPanel is hidden
    func hideThumbnailPanelWithoutChangingKeyWindow() {
        preferencesWindow.canBecomeKey_ = false
        feedbackWindow.canBecomeKey_ = false
        thumbnailsPanel.orderOut(nil)
        preferencesWindow.canBecomeKey_ = true
        feedbackWindow.canBecomeKey_ = true
    }

    func closeSelectedWindow() {
        Windows.focusedWindow()?.close()
    }

    func minDeminSelectedWindow() {
        Windows.focusedWindow()?.minDemin()
    }

    func toggleFullscreenSelectedWindow() {
        Windows.focusedWindow()?.toggleFullscreen()
    }

    func quitSelectedApp() {
        Windows.focusedWindow()?.application.quit()
    }

    func hideShowSelectedApp() {
        Windows.focusedWindow()?.application.hideOrShow()
    }

    func focusTarget() {
        guard appIsBeingUsed else { return } // already hidden
        let focusedWindow = Windows.focusedWindow()
        let previousFocusedWindow = Windows.previousFocusedWindow()
        Logger.info(focusedWindow?.cgWindowId.map { String(describing: $0) } ?? "nil", focusedWindow?.title ?? "nil", focusedWindow?.application.pid ?? "nil", focusedWindow?.application.bundleIdentifier ?? "nil", previousFocusedWindow?.application.bundleIdentifier ?? "nil")
        focusSelectedWindow(focusedWindow, previousFocusedWindow)
    }

    @objc func checkForUpdatesNow(_ sender: NSMenuItem) {
        PoliciesTab.checkForUpdatesNow(sender)
    }

    @objc func checkPermissions(_ sender: NSMenuItem) {
        permissionsWindow.show({})
    }

    @objc func supportProject() {
        NSWorkspace.shared.open(URL(string: App.website + "/support")!)
    }

    @objc func showFeedbackPanel() {
        showSecondaryWindow(feedbackWindow)
    }

    @objc func showPreferencesWindow() {
        showSecondaryWindow(preferencesWindow)
    }

    func showSecondaryWindow(_ window: NSWindow?) {
        if let window {
            NSScreen.updatePreferred()
            NSScreen.preferred.repositionPanel(window)
            App.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            // Use the center function to continue to center, the `repositionPanel` function cannot center, it may be a system bug
            window.center()
        }
    }

    @objc func showUi() {
        showUiOrCycleSelection(0)
    }

    @objc func showAboutTab() {
        preferencesWindow.selectTab("about")
        showPreferencesWindow()
    }

    func cycleSelection(_ direction: Direction, allowWrap: Bool = true) {
        if direction == .up || direction == .down {
            thumbnailsPanel.thumbnailsView.navigateUpOrDown(direction, allowWrap: allowWrap)
        } else {
            Windows.cycleFocusedWindowIndex(direction.step(), allowWrap: allowWrap)
        }
    }

    func previousWindowShortcutWithRepeatingKey() {
        cycleSelection(.trailing)
        KeyRepeatTimer.toggleRepeatingKeyPreviousWindow()
    }

    func focusSelectedWindow(_ selectedWindow: Window?, _ previousSelectedWindow: Window?) {
        guard appIsBeingUsed else { return } // already hidden
        previousSelectedWindow?.unfocus()
        usleep(10000)
        if let window = selectedWindow, MissionControl.state() == .inactive || MissionControl.state() == .showDesktop {
            window.focus()
            if Preferences.cursorFollowFocusEnabled {
                moveCursorToSelectedWindow(window)
            }
        } else {
            previewPanel.orderOut(nil)
        }
        hideUi(true)
    }

    func moveCursorToSelectedWindow(_ window: Window) {
        let referenceWindow = window.referenceWindowForTabbedWindow()
        guard let position = referenceWindow?.position, let size = referenceWindow?.size else { return }
        let point = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)
        CGWarpMouseCursorPosition(point)
    }

    func refreshOpenUi(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy) {
        if !windowsToScreenshot.isEmpty && SystemPermissions.screenRecordingPermission == .granted
               && !Preferences.onlyShowApplications()
               && (!Appearance.hideThumbnails || Preferences.previewFocusedWindow) {
            Windows.refreshThumbnails(windowsToScreenshot, source)
            if source == .refreshOnlyThumbnailsAfterShowUi { return }
        }
        guard appIsBeingUsed else { return }
        if source == .refreshUiAfterExternalEvent {
            if !Windows.updatesBeforeShowing() { hideUi(); return }
        }
        guard appIsBeingUsed else { return }
        Windows.updateFocusedWindowIndex()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.thumbnailsView.updateItemsAndLayout()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.setContentSize(thumbnailsPanel.thumbnailsView.frame.size)
        thumbnailsPanel.display()
        guard appIsBeingUsed else { return }
        NSScreen.preferred.repositionPanel(thumbnailsPanel)
        guard appIsBeingUsed else { return }
        Windows.voiceOverWindow() // at this point ThumbnailViews are assigned to the window, and ready
        guard appIsBeingUsed else { return }
        Windows.previewFocusedWindowIfNeeded()
        guard appIsBeingUsed else { return }
        Applications.refreshBadgesAsync()
    }

    func showUiOrCycleSelection(_ shortcutIndex: Int) {
        Logger.debug(shortcutIndex, self.shortcutIndex, isFirstSummon)
        App.app.appIsBeingUsed = true
        if isFirstSummon || shortcutIndex != self.shortcutIndex {
            if isVeryFirstSummon {
                Windows.sortByLevel()
                isVeryFirstSummon = false
            }
            isFirstSummon = false
            self.shortcutIndex = shortcutIndex
            NSScreen.updatePreferred()
            if !Windows.updatesBeforeShowing() { hideUi(); return }
            Windows.setInitialFocusedAndHoveredWindowIndex()
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
            KeyRepeatTimer.toggleRepeatingKeyNextWindow()
        }
    }

    func buildUiAndShowPanel() {
        guard appIsBeingUsed else { return }
        Appearance.update()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.makeKeyAndOrderFront(nil) // workaround: without this, switching between 2 screens make thumbnailPanel invisible
        KeyRepeatTimer.toggleRepeatingKeyNextWindow()
        guard appIsBeingUsed else { return }
        refreshOpenUi([], .showUi)
        guard appIsBeingUsed else { return }
        thumbnailsPanel.show()
        refreshOpenUi(Windows.list, .refreshOnlyThumbnailsAfterShowUi)
    }

    func checkIfShortcutsShouldBeDisabled(_ activeWindow: Window?, _ activeApp: NSRunningApplication?) {
        let app = activeWindow?.application.runningApplication ?? activeApp
        let shortcutsShouldBeDisabled = Preferences.blacklist.contains { blacklistedId in
            if let id = app?.bundleIdentifier {
                return id.hasPrefix(blacklistedId.bundleIdentifier) &&
                    (blacklistedId.ignore == .always || (blacklistedId.ignore == .whenFullscreen && (activeWindow?.isFullscreen ?? false)))
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
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        #endif
        #if !DEBUG
        PFMoveToApplicationsFolderIfNecessary()
        #endif
        AXUIElement.setGlobalTimeout()
        Preferences.initialize()
        BackgroundWork.startSystemPermissionThread()
        permissionsWindow = PermissionsWindow()
        SystemPermissions.ensurePermissionsAreGranted { [weak self] in
            guard let self else { return }
            BackgroundWork.start()
            NSScreen.updatePreferred()
            Appearance.update()
            Menubar.initialize()
            self.loadMainMenuXib()
            self.thumbnailsPanel = ThumbnailsPanel()
            self.previewPanel = PreviewPanel()
            Spaces.refresh()
            SpacesEvents.observe()
            ScreensEvents.observe()
            SystemAppearanceEvents.observe()
            SystemScrollerStyleEvents.observe()
            Applications.initialDiscovery()
            self.preferencesWindow = PreferencesWindow()
            self.feedbackWindow = FeedbackWindow()
            KeyboardEvents.addEventHandlers()
            MouseEvents.observe()
            TrackpadEvents.observe()
            CliEvents.observe()
            self.preloadWindows()
            Logger.info("AltTab ready")
            #if DEBUG
//            self.showPreferencesWindow()
            #endif
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferencesWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // symbolic hotkeys state persist after the app is quit; we restore this shortcut before quitting
        setNativeCommandTabEnabled(true)
    }
}

enum RefreshCausedBy {
    case showUi
    case refreshOnlyThumbnailsAfterShowUi
    case refreshUiAfterThumbnailsHaveBeenRefreshed
    case refreshUiAfterExternalEvent
}
