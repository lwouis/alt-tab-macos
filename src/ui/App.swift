import Cocoa
import Darwin
import LetsMove
import ShortcutRecorder
import AppCenterCrashes

let cgsMainConnectionId = CGSMainConnectionID()

var activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep,
    reason: "Prevent App Nap to preserve responsiveness")

class App: AppCenterApplication, NSApplicationDelegate {
    static let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as! String
    static let id = Bundle.main.object(forInfoDictionaryKey: "CFBundleIdentifier") as! String
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
    static let licence = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as! String
    static let repository = "https://github.com/lwouis/alt-tab-macos"
    static var app: App!
    var menubar: Menubar!
    var thumbnailsPanel: ThumbnailsPanel!
    var previewPanel: PreviewPanel!
    var preferencesWindow: PreferencesWindow!
    var feedbackWindow: FeedbackWindow!
    var isFirstSummon = true
    var appIsBeingUsed = false
    var globalShortcutsAreDisabled = false
    var shortcutIndex = 0
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
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        #endif
        #if !DEBUG
        PFMoveToApplicationsFolderIfNecessary()
        #endif
        AXUIElement.setGlobalTimeout()
        BackgroundWork.startSystemPermissionThread()
        SystemPermissions.ensurePermissionsAreGranted { [weak self] in
            guard let self = self else { return }
            BackgroundWork.start()
            Preferences.initialize()
            self.menubar = Menubar()
            self.loadMainMenuXib()
            self.thumbnailsPanel = ThumbnailsPanel()
            self.previewPanel = PreviewPanel()
            Spaces.initialDiscovery()
            Applications.initialDiscovery()
            self.preferencesWindow = PreferencesWindow()
            self.feedbackWindow = FeedbackWindow()
            KeyboardEvents.addEventHandlers()
            MouseEvents.observe()
            // TODO: undeterministic; events in the queue may still be processing; good enough for now
            DispatchQueue.main.async { () -> () in Windows.sortByLevel() }
            self.preloadWindows()
            #if DEBUG
            self.showPreferencesWindow()
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
        ThumbnailsView.recycledViews = ThumbnailsView.recycledViews.map { _ in ThumbnailView() }
        thumbnailsPanel.thumbnailsView.updateRoundedCorners(Preferences.windowCornerRadius)
    }

    func restart() {
        // we use -n to open a new instance, to avoid calling applicationShouldHandleReopen
        // we use Bundle.main.bundlePath in case of multiple AltTab versions on the machine
        Process.launchedProcess(launchPath: "/usr/bin/open", arguments: ["-n", Bundle.main.bundlePath])
        App.shared.terminate(self)
    }

    func hideUi(_ keepPreview: Bool = false) {
        debugPrint("hideUi")
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
        debugPrint("focusTarget")
        focusSelectedWindow(Windows.focusedWindow())
    }

    @objc func checkForUpdatesNow(_ sender: NSMenuItem) {
        PoliciesTab.checkForUpdatesNow(sender)
    }

    @objc func showFeedbackPanel() {
        showSecondaryWindow(feedbackWindow)
    }

    @objc func showPreferencesWindow() {
        showSecondaryWindow(preferencesWindow)
    }

    func showSecondaryWindow(_ window: NSWindow?) {
        if let window = window {
            NSScreen.preferred().repositionPanel(window, .appleCentered)
            App.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc func showUi() {
        appIsBeingUsed = true
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
        if let window = selectedWindow, !MissionControl.isActive() {
            window.focus()
            if Preferences.cursorFollowFocusEnabled {
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

    func reopenUi() {
        thumbnailsPanel.orderOut(nil)
        rebuildUi()
    }

    func refreshOpenUi(_ windowsToUpdate: [Window]? = nil) {
        guard appIsBeingUsed else { return }
        let currentScreen = NSScreen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refreshCurrentSpaceId()
        Spaces.refreshAllIdsAndIndexes()
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
        currentScreen.repositionPanel(thumbnailsPanel, .appleCentered)
        Windows.voiceOverWindow() // at this point ThumbnailViews are assigned to the window, and ready
    }

    private func refreshSpecificWindows(_ windowsToUpdate: [Window]?, _ currentScreen: NSScreen) -> ()? {
        windowsToUpdate?.forEach { (window: Window) in
            guard appIsBeingUsed else { return }
            if !Preferences.hideThumbnails { window.refreshThumbnail() }
            Windows.refreshIfWindowShouldBeShownToTheUser(window, currentScreen)
            window.updatesWindowSpace()
        }
    }

    func showUiOrCycleSelection(_ shortcutIndex: Int) {
        debugPrint("showUiOrCycleSelection")
        if isFirstSummon || shortcutIndex != self.shortcutIndex {
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            isFirstSummon = false
            if Windows.list.count == 0 || MissionControl.isActive() { hideUi(); return }
            // TODO: can the CGS call inside detectTabbedWindows introduce latency when WindowServer is busy?
            Windows.detectTabbedWindows()
            // TODO: find a way to update space info when spaces are changed, instead of on every trigger
            // replace with:
            // So far, the best signal I've found is to watch com.apple.dock for the uiElementDestroyed notification.
            // When Mission Control is triggered, an AXGroup element is created (with some nested groups for the window and desktop buttons).
            // There's no way to observe this with the AX API, other than polling. However, when Mission Control is deactivated,
            // that AXGroup gets destroyed, triggering the uiElementDestroyed notification.
            // (At that point we won't be able to see what the element was, of course.)
            Spaces.refreshAllIdsAndIndexes()
            Windows.updateSpaces()
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
        guard appIsBeingUsed else { return }
        Windows.refreshFirstFewThumbnailsSync()
        guard appIsBeingUsed else { return }
        thumbnailsPanel.makeKeyAndOrderFront(nil) // workaround: without this, switching between 2 monitors make thumbnailPanel invisible
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
