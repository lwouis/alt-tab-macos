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
    var forceDoNothingOnRelease = false
    private var feedbackWindow: FeedbackWindow!
    private var isFirstSummon = true
    private var isVeryFirstSummon = true
    // periphery:ignore
    private var appCenterDelegate: AppCenterCrash?
    // don't queue multiple delayed rebuildUi() calls
    private var delayedDisplayScheduled = 0
    // Atomic operation protection to prevent concurrent calls
    private var isExecutingCycling = false
    private let cyclingLock = NSLock()
    private var firstCallTimestamp: Date?
    private var isInitializing = false

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
        isInitializing = false // Clear initialization flag
        forceDoNothingOnRelease = false
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
        Logger.info(focusedWindow?.cgWindowId.map { String(describing: $0) } ?? "nil", focusedWindow?.title ?? "nil", focusedWindow?.application.pid ?? "nil", focusedWindow?.application.bundleIdentifier ?? "nil")
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
        if let window {
            NSScreen.updatePreferred()
            NSScreen.preferred.repositionPanel(window)
            App.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            // Use the center function to continue to center, the `repositionPanel` function cannot center, it may be a system bug
            window.center()
        }
    }

    func showUi(_ shortcutIndex: Int) {
        showUiOrCycleSelectionWithSource(shortcutIndex, true, .showUI)
    }

    @objc func showUiFromShortcut0() {
        showUi(0)
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

    func focusSelectedWindow(_ selectedWindow: Window?) {
        guard appIsBeingUsed else { return } // already hidden
        hideUi(true)
        if let window = selectedWindow, MissionControl.state() == .inactive || MissionControl.state() == .showDesktop {
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

    func refreshOpenUi(_ windowsToScreenshot: [Window], _ source: RefreshCausedBy) {
        if !windowsToScreenshot.isEmpty && SystemPermissions.screenRecordingPermission == .granted
               && !Preferences.onlyShowApplications()
               && (!Appearance.hideThumbnails || Preferences.previewFocusedWindow) {
            Windows.refreshThumbnails(windowsToScreenshot, source)
            if source == .refreshOnlyThumbnailsAfterShowUi { return }
        }
        guard appIsBeingUsed else { return }
        if source == .refreshUiAfterExternalEvent {
            // Block external events during initialization to prevent focus drift
            if isInitializing {
                Logger.debug("refreshOpenUi blocked - External event during initialization")
                return
            }
            if !Windows.updatesBeforeShowing() { hideUi(); return }
        }
        guard appIsBeingUsed else { return }
        // Only update focused window index if not initializing to prevent drift
        if !isInitializing || source != .refreshUiAfterExternalEvent {
            Windows.updateFocusedWindowIndex()
        }
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

    func showUiOrCycleSelection(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool) {
        showUiOrCycleSelectionWithSource(shortcutIndex, forceDoNothingOnRelease_, .unknown)
    }
    
    func showUiOrCycleSelectionWithSource(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool, _ eventSource: EventSource) {
        // Atomic operation protection - prevent concurrent calls
        cyclingLock.lock()
        defer { cyclingLock.unlock() }
        
        // Early exit if concurrent execution protection is active
        if isExecutingCycling {
            Logger.debug("showUiOrCycleSelection blocked by concurrent protection")
            return
        }
        
        // Initialize basic state
        forceDoNothingOnRelease = forceDoNothingOnRelease_
        Logger.debug(shortcutIndex, self.shortcutIndex, isFirstSummon)
        App.app.appIsBeingUsed = true
        
        // Determine if this is the first call and apply event source filtering
        let isFirstCall = isFirstSummon || shortcutIndex != self.shortcutIndex
        let now = Date()
        
        Logger.debug("showUiOrCycleSelection called from", eventSource.rawValue, "isFirstCall:", isFirstCall)
        
        // Apply event source based filtering for subsequent calls
        if !isFirstCall && appIsBeingUsed {
            if shouldBlockDuplicateEvent(eventSource: eventSource, currentTime: now) {
                return
            }
        }
        
        // Update timestamp for first calls
        if isFirstCall {
            firstCallTimestamp = now
        }
        
        // Set concurrent execution protection
        setConcurrentProtection()
        
        // Execute the appropriate action based on whether this is first call or cycling
        if isFirstCall {
            handleFirstCall(shortcutIndex: shortcutIndex)
        } else {
            handleCycling()
        }
    }
    
    /// Check if a duplicate event should be blocked based on event source and timing
    private func shouldBlockDuplicateEvent(eventSource: EventSource, currentTime: Date) -> Bool {
        guard let firstTime = firstCallTimestamp else { return false }
        
        let timeSinceFirst = currentTime.timeIntervalSince(firstTime)
        
        switch eventSource {
        case .cgEventTap:
            if timeSinceFirst < 0.3 {
                Logger.debug("showUiOrCycleSelection blocked - CGEventTap delayed duplicate call")
                return true
            }
            
        case .nsEvent:
            if timeSinceFirst < 0.1 {
                Logger.debug("showUiOrCycleSelection blocked - NSEvent rapid duplicate call")
                return true
            }
            
        case .globalHotKey:
            Logger.debug("showUiOrCycleSelection allowed - GlobalHotKey user action")
            return false
            
        case .unknown, .legacyAction:
            if timeSinceFirst < 0.3 {
                Logger.debug("showUiOrCycleSelection blocked - Unknown/LegacyAction delayed duplicate call")
                return true
            }
            
        case .keyRepeat:
            return shouldBlockKeyRepeatEvent(timeSinceFirst: timeSinceFirst)
            
        case .safetyMeasure:
            if timeSinceFirst < 0.3 {
                Logger.debug("showUiOrCycleSelection blocked - SafetyMeasure delayed duplicate call")
                return true
            }
            
        case .showUI, .trackpad:
            // These sources are generally allowed through
            return false
        }
        
        return false
    }
    
    /// Check if a KeyRepeat event should be blocked
    private func shouldBlockKeyRepeatEvent(timeSinceFirst: TimeInterval) -> Bool {
        // Check if KeyRepeat timer is inactive
        if !KeyRepeatTimer.isActive {
            Logger.debug("showUiOrCycleSelection blocked - KeyRepeat timer is inactive")
            return true
        }
        
        // Block KeyRepeat events during initialization period
        if timeSinceFirst < 0.5 {
            Logger.debug("showUiOrCycleSelection blocked - KeyRepeat during initialization")
            return true
        }
        
        return false
    }
    
    /// Set concurrent execution protection with automatic cleanup
    private func setConcurrentProtection() {
        isExecutingCycling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.isExecutingCycling = false
        }
    }
    
    /// Handle the first call - initialize and show UI
    private func handleFirstCall(shortcutIndex: Int) {
        // Set initialization protection flag to prevent focus drift
        isInitializing = true
        
        // Initialize on very first summon
        if isVeryFirstSummon {
            Windows.sortByLevel()
            isVeryFirstSummon = false
        }
        
        // Update state
        isFirstSummon = false
        self.shortcutIndex = shortcutIndex
        
        // Prepare UI
        NSScreen.updatePreferred()
        if !Windows.updatesBeforeShowing() { 
            isInitializing = false
            hideUi()
            return 
        }
        
        Windows.setInitialFocusedAndHoveredWindowIndex()
        
        // Show UI with appropriate delay
        if Preferences.windowDisplayDelay == DispatchTimeInterval.milliseconds(0) {
            buildUiAndShowPanel()
            // Clear initialization flag after UI is built
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isInitializing = false
            }
        } else {
            scheduleDelayedDisplay()
        }
    }
    
    /// Handle cycling through windows
    private func handleCycling() {
        cycleSelection(.leading)
        KeyRepeatTimer.toggleRepeatingKeyNextWindow()
    }
    
    /// Schedule delayed UI display
    private func scheduleDelayedDisplay() {
        delayedDisplayScheduled += 1
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay) { [weak self] in
            guard let self = self else { return }
            if self.delayedDisplayScheduled == 1 {
                self.buildUiAndShowPanel()
                // Clear initialization flag after UI is built
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.isInitializing = false
                }
            }
            self.delayedDisplayScheduled -= 1
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

/// Event source enumeration - used to identify the source of triggered actions
enum EventSource: String, CaseIterable {
    case globalHotKey = "GlobalHotKey"          // InstallEventHandler - real user key press
    case nsEvent = "NSEvent"                    // addLocalMonitorForEvents - key event monitoring
    case cgEventTap = "CGEventTap"              // cgEventFlagsChangedHandler - modifier key changes
    case keyRepeat = "KeyRepeat"                // KeyRepeatTimer - key repeat timer
    case legacyAction = "LegacyAction"          // legacy action calls
    case safetyMeasure = "SafetyMeasure"        // redundantSafetyMeasures - safety measure calls
    case showUI = "ShowUI"                      // showUi method calls
    case trackpad = "Trackpad"                  // trackpad gestures
    case unknown = "Unknown"                    // unknown source (should be avoided)
}
