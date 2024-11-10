import Cocoa
import Darwin
import LetsMove
import ShortcutRecorder
import AppCenterCrashes

let cgsMainConnectionId = CGSMainConnectionID()

// periphery:ignore
var activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
    reason: "Prevent App Nap to preserve responsiveness")

class App: AppCenterApplication, NSApplicationDelegate {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let id = Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static let website = "https://alt-tab-macos.netlify.app"
    static var app: App!
    var thumbnailsPanel: ThumbnailsPanel!
    var previewPanel: PreviewPanel!
    var preferencesWindow: PreferencesWindow!
    var feedbackWindow: FeedbackWindow!
    var permissionsWindow: PermissionsWindow!
    var isFirstSummon = true
    var appIsBeingUsed = false
    var globalShortcutsAreDisabled = false
    var shortcutIndex = 0
    // periphery:ignore
    var appCenterDelegate: AppCenterCrash?
    // multiple delayed display triggers should only show the ui when the last one triggers
    var delayedDisplayScheduled = 0

    override init() {
        super.init()
        delegate = self
        App.app = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

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
            guard let self = self else { return }
            BackgroundWork.start()
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
            // TODO: undeterministic; events in the queue may still be processing; good enough for now
            DispatchQueue.main.async { () -> () in Windows.sortByLevel() }
            self.preloadWindows()
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
        logger.i()
        if appIsBeingUsed == false { return } // already hidden
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
        let focusedWindow = Windows.focusedWindow()
        logger.i(focusedWindow?.cgWindowId.map { String(describing: $0) } ?? "nil", focusedWindow?.title ?? "nil", focusedWindow?.application.pid ?? "nil", focusedWindow?.application.runningApplication.bundleIdentifier ?? "nil")
        focusSelectedWindow(focusedWindow)
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
        if let window = window {
            NSScreen.preferred().repositionPanel(window)
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

    func cycleSelection(_ direction: Direction) {
        if direction == .up || direction == .down {
            thumbnailsPanel.thumbnailsView.navigateUpOrDown(direction)
        } else {
            Windows.cycleFocusedWindowIndex(direction.step())
        }
    }

    func previousWindowShortcutWithRepeatingKey() {
        cycleSelection(.trailing)
        KeyRepeatTimer.toggleRepeatingKeyPreviousWindow()
    }

    func focusSelectedWindow(_ selectedWindow: Window?) {
        hideUi(true)
        if let window = selectedWindow, MissionControl.state() == .inactive {
            window.focus()
        } else {
            previewPanel.orderOut(nil)
        }
    }

    func refreshOpenUi(_ windowsToUpdate: [Window]? = nil) {
        guard appIsBeingUsed else { return }
        let currentScreen = NSScreen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refresh()
        guard appIsBeingUsed else { return }
        refreshSpecificWindows(windowsToUpdate, currentScreen)
        if (!Windows.list.contains { $0.shouldShowTheUser }) { hideUi(); return }
        guard appIsBeingUsed else { return }
        Windows.reorderList()
        Windows.updateFocusedWindowIndex()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.thumbnailsView.updateItemsAndLayout(currentScreen)
        guard appIsBeingUsed else { return }
        thumbnailsPanel.setContentSize(thumbnailsPanel.thumbnailsView.frame.size)
        thumbnailsPanel.display()
        guard appIsBeingUsed else { return }
        currentScreen.repositionPanel(thumbnailsPanel)
        Windows.voiceOverWindow() // at this point ThumbnailViews are assigned to the window, and ready
    }

    private func refreshSpecificWindows(_ windowsToUpdate: [Window]?, _ currentScreen: NSScreen) -> ()? {
        windowsToUpdate?.forEach { (window: Window) in
            guard appIsBeingUsed else { return }
            if !Appearance.hideThumbnails { window.refreshThumbnail() }
            Windows.refreshIfWindowShouldBeShownToTheUser(window, currentScreen)
            window.updatesWindowSpace()
        }
    }

    func showUiOrCycleSelection(_ shortcutIndex: Int) {
        logger.d(shortcutIndex, self.shortcutIndex, isFirstSummon)
        App.app.appIsBeingUsed = true
        if isFirstSummon || shortcutIndex != self.shortcutIndex {
            isFirstSummon = false
            if Windows.list.count == 0 || MissionControl.state() != .inactive { hideUi(); return }
            // TODO: can the CGS call inside detectTabbedWindows introduce latency when WindowServer is busy?
            Windows.detectTabbedWindows()
            // TODO: find a way to update space info when spaces are changed, instead of on every trigger
            // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
            // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
            Spaces.refresh()
            Windows.list.forEachAsync { $0.updatesWindowSpace() }
            let screen = NSScreen.preferred()
            self.shortcutIndex = shortcutIndex
            Windows.refreshWhichWindowsToShowTheUser(screen)
            Windows.reorderList()
            if (!Windows.list.contains { $0.shouldShowTheUser }) { hideUi(); return }
            Windows.setInitialFocusedAndHoveredWindowIndex()
            delayedDisplayScheduled += 1
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) { () -> () in
                if self.delayedDisplayScheduled == 1 {
                    self.rebuildUi(screen)
                }
                self.delayedDisplayScheduled -= 1
            }
        } else {
            cycleSelection(.leading)
            KeyRepeatTimer.toggleRepeatingKeyNextWindow()
        }
    }

    func rebuildUi(_ screen: NSScreen = NSScreen.preferred()) {
        Appearance.update()
        guard appIsBeingUsed else { return }
        Windows.refreshFirstFewThumbnailsSync()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.makeKeyAndOrderFront(nil) // workaround: without this, switching between 2 screens make thumbnailPanel invisible
        guard appIsBeingUsed else { return }
        refreshOpenUi()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.show()
        Windows.previewFocusedWindowIfNeeded()
        guard appIsBeingUsed else { return }
        Windows.refreshThumbnailsAsync(screen)
        guard appIsBeingUsed else { return }
        Applications.refreshBadges()
        KeyRepeatTimer.toggleRepeatingKeyNextWindow()
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
