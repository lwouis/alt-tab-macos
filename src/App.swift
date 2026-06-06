import Cocoa
import Darwin
import ShortcutRecorder
import AppCenterCrashes
import Sparkle

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
    static let appIconReps = CGImage.allNamed("app.icns")

    static func appIcon(for size: NSSize) -> CGImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let scaled = NSSize(width: size.width * scale, height: size.height * scale)
        return CGImage.bestMatch(appIconReps, for: scaled)
    }
    override class var shared: App { super.shared as! App }
    static var supportProjectAction: Selector { #selector(App.supportProject) }
    static var upgradeToProAction: Selector { #selector(App.upgradeToPro) }
    static var openAccountAction: Selector { #selector(App.openAccount) }
    static var isTerminating = false
    private static var isVeryFirstSummon = true
    private static var pendingShowSettingsWindow = false
    private static var firstLaunchSettingsObserver: NSObjectProtocol?
    // periphery:ignore
    private static var appCenterDelegate: AppCenterCrash?
    // periphery:ignore
    static var sparkleDelegate: SparkleDelegate?
    static var updaterController: SPUStandardUpdaterController?
    // don't queue multiple delayed rebuildUi() calls
    private static var delayedDisplayScheduled = 0
    private static let switcherUiRefreshThrottler = Throttler(delayInMs: 200)

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
        Logger.info { "active:\(SwitcherSession.isActive)" }
        guard SwitcherSession.current != nil else { return } // already hidden
        SwitcherSession.current = nil
        UsageStats.resetSession()
        TilesView.endSearchSession()
        ContextMenuEvents.toggle(false)
        CursorEvents.toggle(false)
        TrackpadEvents.reset()
        Tooltips.hideAll()
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            PreviewPanel.shared.orderOut(nil)
        }
        MainMenu.toggle(true)
        ProTransitionManager.shared.onSwitcherDismissed()
    }

    /// we don't want another window to become key when the TilesPanel is hidden
    static func hideTilesPanelWithoutChangingKeyWindow() {
        allSecondaryWindowsCanBecomeKey(false)
        TilesPanel.shared.orderOut(nil)
        allSecondaryWindowsCanBecomeKey(true)
    }

    private static func allSecondaryWindowsCanBecomeKey(_ canBecomeKey_: Bool) {
        SettingsWindow.canBecomeKey_ = canBecomeKey_
        if #available(macOS 13.0, *) {
            SwiftUISettingsWindow.canBecomeKey_ = canBecomeKey_
        }
        AboutWindow.canBecomeKey_ = canBecomeKey_
        PermissionsWindow.canBecomeKey_ = canBecomeKey_
        FeedbackWindow.canBecomeKey_ = canBecomeKey_
        DebugWindow.canBecomeKey_ = canBecomeKey_
    }

    static func focusTarget() {
        guard SwitcherSession.isActive else { return } // already hidden
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
        NSWorkspace.shared.open(URL(string: Endpoints.supportUrl)!)
    }

    @objc static func upgradeToPro() {
        ProTransitionManager.openCheckout()
    }

    @objc static func openAccount() {
        UpgradeTab.openAccountPage()
    }

    @objc static func showFeedbackPanel() {
        let wasFresh = FeedbackWindow.shared == nil
        initializeFeedbackWindowIfNeeded()
        // Fresh init already runs reset(); skip the redundant second call so we don't
        // double-fire the Sparkle preflight on the first ever open.
        if !wasFresh { FeedbackWindow.shared?.reset() }
        showSecondaryWindow(FeedbackWindow.shared!)
    }

    @objc static func showDebugWindow() {
        initializeDebugWindowIfNeeded()
        showSecondaryWindow(DebugWindow.shared!)
    }

    @objc static func showSettingsWindow() {
        guard Menubar.statusItem != nil else {
            pendingShowSettingsWindow = true
            return
        }
        if #available(macOS 13.0, *) {
            if SwiftUISettingsWindow.shared == nil {
                _ = SwiftUISettingsWindow()
            }
            showSecondaryWindow(SwiftUISettingsWindow.shared!)
            if SwiftUISettingsWindow.shared!.isVisible != true {
                let window = SwiftUISettingsWindow()
                showSecondaryWindow(window)
                window.orderFrontRegardless()
            }
        } else {
            initializeSettingsWindowIfNeeded()
            showSecondaryWindow(SettingsWindow.shared!)
            if SettingsWindow.shared!.isVisible != true {
                let window = SettingsWindow()
                showSecondaryWindow(window)
                window.orderFrontRegardless()
            }
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
        if #available(macOS 13.0, *) {
            if SwiftUISettingsWindow.shared == nil {
                _ = SwiftUISettingsWindow()
            }
        } else {
            if SettingsWindow.shared == nil { _ = SettingsWindow() }
        }
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
        // If the Day1 Welcome window will be shown on this launch, wait for the user to close it
        // before showing Settings — otherwise both windows appear stacked.
        if willShowDay1WelcomeOnAppLaunch() {
            deferFirstLaunchSettingsUntilDay1WelcomeCloses()
        } else {
            showAndCenterSettingsWindowOnFirstLaunch()
        }
        return true
    }

    /// Mirrors the conditions under which `ProTransitionScheduler.computeNextFireDate()` returns
    /// "now" for the Welcome prompt. Kept narrow on purpose: the other Day-X prompts are gated by
    /// trial age and don't fire on the very first launch.
    private static func willShowDay1WelcomeOnAppLaunch() -> Bool {
        if case .pro = LicenseManager.shared.state { return false }
        return !ProTransitionManager.shared.hasSeenWelcome
    }

    private static func deferFirstLaunchSettingsUntilDay1WelcomeCloses() {
        firstLaunchSettingsObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: nil, queue: .main) { notification in
            guard notification.object is Day1WelcomeLetterWindow else { return }
            if let observer = firstLaunchSettingsObserver {
                NotificationCenter.default.removeObserver(observer)
                firstLaunchSettingsObserver = nil
            }
            DispatchQueue.main.async { showAndCenterSettingsWindowOnFirstLaunch() }
        }
    }

    /// `showSettingsWindow()` relies on a saved autosave frame to position the window. On first
    /// launch there's no saved frame, and `showSecondaryWindow`'s fallback centering doesn't always
    /// stick (the window has been observed at the lower-left corner). Force a center pass after
    /// showing so the user sees the window in the middle of the screen.
    private static func showAndCenterSettingsWindowOnFirstLaunch() {
        showSettingsWindow()
        if #available(macOS 13.0, *), let window = SwiftUISettingsWindow.shared {
            NSScreen.preferred.repositionPanel(window)
            window.center()
        } else if let window = SettingsWindow.shared {
            NSScreen.preferred.repositionPanel(window)
            window.center()
        }
        Preferences.markSettingsWindowShownOnFirstLaunch()
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
        guard SwitcherSession.isActive else { return } // already hidden
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
        WindowThumbnails.refreshAsync(windowsToScreenshot, .refreshUiAfterExternalEvent, windowRemoved: windowRemoved)
        switcherUiRefreshThrottler.throttleOrProceed {
            guard SwitcherSession.isActive else { return }
            if !Windows.updatesBeforeShowing() { hideUi(); return }
            refreshUi(true)
        }
    }

    static func refreshUi(_ preserveScrollPosition: Bool = false) {
        guard SwitcherSession.isActive else { return }
        let preservedScrollOrigin = preserveScrollPosition ? TilesView.currentScrollOrigin() : nil
        Windows.updateSelectedWindow()
        guard SwitcherSession.isActive else { return }
        TilesPanel.shared.updateContents(preservedScrollOrigin)
        guard SwitcherSession.isActive else { return }
        Windows.voiceOverWindow() // at this point TileViews are assigned to the window, and ready
        guard SwitcherSession.isActive else { return }
        WindowThumbnails.previewSelectedIfNeeded()
        guard SwitcherSession.isActive else { return }
        Applications.refreshBadgesAsync()
    }

    static func showUiOrCycleSelection(_ shortcutIndex: Int, _ forceDoNothingOnRelease_: Bool) {
        let session = SwitcherSession.current ?? {
            let new = SwitcherSession()
            SwitcherSession.current = new
            return new
        }()
        session.forceDoNothingOnRelease = forceDoNothingOnRelease_
        Logger.debug { "isFirstSummon:\(session.isFirstSummon) shortcutIndex:\(shortcutIndex)" }
        UsageStats.recordTrigger(shortcutIndex)
        if session.isFirstSummon || shortcutIndex != session.shortcutIndex {
            NSScreen.updatePreferred()
            if isVeryFirstSummon {
                Windows.sortByLevel()
                isVeryFirstSummon = false
            }
            session.isFirstSummon = false
            session.shortcutIndex = shortcutIndex
            session.holdMask =
                ControlsTab.shortcuts[
                    Preferences.indexToName("holdShortcut", shortcutIndex)
                ]?.shortcut.modifierFlags ?? []
            // Hide instantly so the rebuild for a different shortcut (Appearance change, layout
            // recalc) is invisible. `TilesPanel.show()` flips alpha back to 1 once everything is
            // in its final state. No-op on first summon (panel was orderOut'd with alpha=0).
            TilesPanel.shared.alphaValue = 0
            ProTransitionManager.shared.onSwitcherShown()
            let shouldStartInSearchMode = Preferences.effectiveShortcutStyle(shortcutIndex) == .searchOnRelease
            TilesView.startSearchSession(shouldStartInSearchMode)
            if shouldStartInSearchMode {
                session.forceDoNothingOnRelease = true
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
        guard SwitcherSession.isActive else { return }
        Appearance.update()
        guard SwitcherSession.isActive else { return }
        TilesView.swapBackgroundViewIfNeeded()
        guard SwitcherSession.isActive else { return }
        refreshUi()
        guard SwitcherSession.isActive else { return }
        TilesPanel.shared.show()
        WindowThumbnails.previewSelectedIfNeeded()
        if TilesView.isSearchEditing {
            TilesView.enableSearchEditing()
        }
        KeyRepeatTimer.startRepeatingKeyNextWindow()
        let prioritizedIds = TilesView.windowIdsInViewport()
        WindowThumbnails.refreshAsync(Windows.list, .refreshOnlyThumbnailsAfterShowUi, prioritizedIds: prioritizedIds)
    }

    static func checkIfShortcutsShouldBeDisabled(_ activeWindow: Window?, _ activeApp: Application?) {
        let app = activeWindow?.application ?? activeApp!
        let shortcutsShouldBeDisabled = ExceptionMatcher.disablesShortcuts(
            app.state,
            isFullscreen: activeWindow?.isFullscreen ?? false,
            exceptions: Preferences.exceptions)
        KeyboardEvents.toggleGlobalShortcuts(shortcutsShouldBeDisabled)
        if shortcutsShouldBeDisabled && SwitcherSession.isActive {
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
        App.sparkleDelegate = SparkleDelegate()
        App.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: App.sparkleDelegate!,
            userDriverDelegate: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            App.updaterController?.startUpdater()
        }
        PreferencesEvents.initialize()
        BenchmarkRunner.startIfNeeded()
        showSettingsWindowOnFirstLaunchIfNeeded()
        if pendingShowSettingsWindow {
            pendingShowSettingsWindow = false
            showSettingsWindow()
        }
        #if DEBUG
        QAMenu.shared = QAMenu()
        QAMenu.shared?.orderFront(nil)
        if QAMenu.openSettingsOnLaunch { App.showSettingsWindow() }
        if QAMenu.graphEnabled { DebugMenu.setEnabled(true) }
        #endif
        UsageStats.prune()
        ProTransitionManager.shared.onAction = { ProPromptHost.shared.dispatch($0) }
        ProTransitionManager.shared.onAppLaunchComplete()
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
        MoveToApplicationsFolder.promptIfNeeded()
        #endif
        AXUIElement.setGlobalTimeout()
        Preferences.initialize()

        // Skip LicenseManager / permission checks when running in Xcode SwiftUI Preview
        let isRunningInPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        if isRunningInPreview {
            // Preview uses ProStateTracker with default (locked) state — no keychain, no permissions
            return
        }

        LicenseManager.shared.onBeforeProUnlock = { ProTransitionManager.shared.onProUnlocked() }
        LicenseManager.shared.onStateChanged = { state in
            Menubar.refreshLicenseMenuItems()
            syncLicenseCookie(state: state)
            ProTransitionManager.shared.onLicenseStateChanged()
            UpgradeTab.refreshStatus()
            SettingsWindow.shared?.refreshUpgradeButton()
            if TilesPanel.shared != nil { App.resetPreferencesDependentComponents() }
            // `isProLocked` reads from state, so a state change implicitly changes the lock.
            // Notify UI observers so Settings rows repaint their ghost/pro-locked styling.
            NotificationCenter.default.post(name: ProTransitionManager.proLockStateDidChangeNotification, object: nil)
        }
        LicenseManager.shared.initialize()
        BackgroundWork.preStart()
        SystemPermissions.ensurePermissionsAreGranted()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if url.scheme == App.bundleIdentifier {
                handleCustomUrl(url)
            }
        }
    }

    private func handleCustomUrl(_ url: URL) {
        guard url.host == "activate",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let licenseKey = components.queryItems?.first(where: { $0.name == "license_key" })?.value,
              !licenseKey.isEmpty else {
            return
        }
        UpgradeTab.showAutoActivating(licenseKey)
        LicenseManager.shared.activate(licenseKey) { result in
            switch result {
            case .success:
                UpgradeTab.showAutoActivationSuccess()
                App.resetPreferencesDependentComponents()
            case .failure:
                UpgradeTab.showAutoActivationFailed(licenseKey)
            }
        }
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
