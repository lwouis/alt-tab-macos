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
    /// The switcher UI only exists once permissions are granted. Activating a license through the
    /// `alt-tab://activate` url launches the app and can land its callback before that, so we bail
    /// instead of resetting a UI that isn't built yet (`TilesView.reset` traps on `TilesPanel.shared`).
    static func resetPreferencesDependentComponents() {
        guard TilesPanel.shared != nil else { return }
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
        Logger.debug { "active:\(SwitcherSession.isActive)" }
        guard SwitcherSession.current != nil else { return } // already hidden
        SwitcherSession.current = nil
        KeyboardEvents.updateEscapeAbsorptionTap() // session closed: stop tapping keyDown (#5766)
        UsageStats.resetSession()
        TilesView.endSearchSession()
        ContextMenuEvents.toggle(false)
        CursorEvents.toggle(false)
        TrackpadEvents.reset()
        Tooltips.hideAll()
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            PreviewPanel.hide()
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
        // if the window was resized/repositioned by the user, restore the window the way it was.
        // ObjCExceptionCatcher guards a corrupt persisted frame (non-finite / out of Int32 bounds):
        // applying it throws NSInternalInconsistencyException and would abort the app (f481d5b0).
        var restored = false
        ObjCExceptionCatcher.catching { restored = window.setFrameUsingName(window.frameAutosaveName) }
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
        if let window = SettingsWindow.shared {
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
            PreviewPanel.hide()
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
        Windows.logTileDump("refreshUi")
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
            // The window set as it stood at the press. Only something ABSENT from it can be a newcomer that
            // the default pick steps over — see `SwitcherSession.windowIdsAtSummon`.
            new.windowIdsAtSummon = Set(Windows.list.map { $0.id })
            SwitcherSession.current = new
            KeyboardEvents.updateEscapeAbsorptionTap() // session opened: enable Esc keyDown tap if bound (#5585)
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
        // enqueue the full-res Preview fetches BEFORE the thumbnail pass below, so the Preview sharpens first
        WindowThumbnails.fetchPreviewFrames()
        if TilesView.isSearchEditing {
            TilesView.enableSearchEditing()
        }
        KeyRepeatTimer.startRepeatingKeyNextWindow()
        let prioritizedIds = TilesView.windowIdsInViewport()
        WindowThumbnails.refreshAsync(Windows.list, .refreshOnlyThumbnailsAfterShowUi, prioritizedIds: prioritizedIds)
    }

    static func checkIfShortcutsShouldBeDisabled(_ activeWindow: Window?, _ activeApp: Application?) {
        let app = activeWindow?.application ?? activeApp!
        // The `.whenFullscreen` rule must reflect whether the frontmost app is CURRENTLY showing a fullscreen
        // window. Don't trust only the window the triggering event carried: it is often nil or stale (RDP's
        // fullscreen session window can't be AX-acquired, so `focusedWindow` reads nil; an activation fires
        // before geometry lands). Deriving `isFullscreen` from that alone let the many call sites disagree, so
        // the toggle flapped and a re-check re-enabled the shortcut mid-fullscreen — AltTab then grabbed Cmd-Tab
        // inside a fullscreen remote session (#5842, same class as #5228). Read it from the model instead: the
        // app has a fullscreen window on the current Space. Any trigger now computes the same verdict.
        let isFullscreen = activeWindow?.isFullscreen == true
            || Windows.list.contains { $0.application.pid == app.pid && $0.isFullscreen && $0.spaceIds.contains(Spaces.currentSpaceId) }
        let shortcutsShouldBeDisabled = ExceptionMatcher.disablesShortcuts(
            app.state,
            isFullscreen: isFullscreen,
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
        ScreensEvents.observe()
        SystemAppearanceEvents.observe()
        SystemScrollerStyleEvents.observe()
        InputSourceEvents.observe()
        ScreenLockEvents.observe()
        SleepWakeEvents.observe()
        Applications.initialDiscovery()
        // The one initial window inventory; later ones ride events + switcher shows. It belongs here, not in
        // the WindowServer tap: the tap is installed before the permission gate, and this needs `Spaces.refresh`
        // to have run (the sweep bails on an empty Space list). Deferred a beat so it doesn't compete with the
        // rest of launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Applications.manuallyRefreshAllWindows()
            // Seed the MRU from screen stacking HERE, off the critical path, rather than only on the first
            // summon: the query blocks, so its answer lands after that summon's first render and the user
            // watches the list re-order. Seeded now, the first summon's own call finds nothing to change and
            // draws nothing twice. It still runs there, for the windows this pass could not see yet.
            Windows.sortByLevel()
        }
        KeyboardEvents.addEventHandlers()
        // Evaluate the "ignore shortcuts" exception for whatever app is already frontmost at launch (#5842):
        // no didActivateApplication fires for it, so without this an app blacklisted with ignore=.always keeps
        // AltTab's shortcut registered after an auto-update relaunch until the user switches away and back.
        if let frontmostPid = Applications.frontmostPid, let frontmostApp = Applications.findOrCreate(frontmostPid, false) {
            checkIfShortcutsShouldBeDisabled(frontmostApp.focusedWindow, frontmostApp)
        }
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
        // Create the background queues first, before anything that can pump the main run loop re-entrantly
        // (the "move to /Applications" modal below, the WindowServer tap's discovery). Window.init reads
        // BackgroundWork.screenshotsQueue (an implicitly-unwrapped optional) via Application.fetchAppIcon, so
        // if a queued discovery block drains re-entrantly before this runs, it traps on the nil queue (#5819).
        // preStart just allocates queues and depends on nothing, so it's safe at the very top.
        BackgroundWork.preStart()
        // Same reasoning as the queues above: a preference the user never changed lives only in the
        // registration domain, so reading one before `registerDefaults()` traps on the force-unwrap in
        // `CachedUserDefaults.getThenConvertOrReset`. The "move to /Applications" modal below drains the
        // main queue, and the crash-report attachment delegate hops to main there to build the debug
        // profile, which reads `showOnScreen` / `appearanceStyle`. Migrations must keep running before
        // `registerDefaults()` (they read raw plist values), which `initialize()` already guarantees.
        // This only touches UserDefaults + TIS (main-thread), so it depends on nothing below.
        Preferences.initialize()
        // Handle the "move to /Applications" prompt before anything else sets up the model. It runs a modal
        // alert (and may relaunch + exit), both of which pump the main run loop, so it must come before the
        // WindowServer tap below: otherwise the tap's queued window discovery drains re-entrantly during the
        // modal and builds a Window while the model is half-built. A translocated instance the user moves
        // relaunches from /Applications, so the setup we skip by returning here early is thrown away anyway.
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        #else
        MoveToApplicationsFolder.promptIfNeeded()
        #endif
        // The WindowServer event tap is CGS-only (needs no Accessibility, no Preferences, no model), so
        // install it before licensing / the permission gate. The skeleton is then available immediately and
        // independent of whether the user has granted AX.
        WindowServerEvents.observe()
        AXUIElement.setGlobalTimeout()
        PreferencesPersistenceCheck.runInBackground()
        LicenseManager.shared.onBeforeProUnlock = { ProTransitionManager.shared.onProUnlocked() }
        LicenseManager.shared.onStateChanged = { state in
            Menubar.refreshLicenseMenuItems()
            syncLicenseCookie(state: state)
            ProTransitionManager.shared.onLicenseStateChanged()
            UpgradeTab.refreshStatus()
            SettingsWindow.shared?.refreshUpgradeButton()
            App.resetPreferencesDependentComponents()
            // `isProLocked` reads from state, so a state change implicitly changes the lock.
            // Notify UI observers so Settings rows repaint their ghost/pro-locked styling.
            NotificationCenter.default.post(name: ProTransitionManager.proLockStateDidChangeNotification, object: nil)
        }
        #if DEBUG
        // test affordance: `--mock-pro` skips the license keychain round-trip (which prompts/hangs for an
        // ad-hoc build whose signature doesn't match the real app's keychain items). See QAMenu's Pro button.
        if CommandLine.arguments.contains("--mock-pro") { LicenseManager.shared.mockProUser() }
        #endif
        LicenseManager.shared.initialize()
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
        // symbolic hotkeys state persist after the app is quit; we restore the ones we disabled before quitting
        restoreNativeHotkeys()
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
