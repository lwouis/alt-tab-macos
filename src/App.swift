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
    /// How long the panel waits for the launch inventory when the very first summon arrives before it
    /// (`showUiOrCycleSelection`). One inventory lands ~280ms after it is asked for, measured.
    private static let launchInventoryGraceInMs = 400
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
        guard beginHideUi(keepPreview) else { return }
        endHideUi()
    }

    /// The part of the dismissal the user can see. `focusSelectedWindow` runs it before asking for the
    /// focus, so the two things the user is waiting for are both out before any bookkeeping.
    /// Returns false when the switcher was already hidden.
    private static func beginHideUi(_ keepPreview: Bool) -> Bool {
        MainThreadStall.step()
        Logger.debug { "active:\(SwitcherSession.isActive)" }
        guard SwitcherSession.current != nil else { return false } // already hidden
        SwitcherSession.current = nil
        hideTilesPanelWithoutChangingKeyWindow()
        if !keepPreview {
            PreviewPanel.hide()
        }
        return true
    }

    /// The rest of the dismissal, none of it visible. Kept behind the focus request because
    /// `TilesView.endSearchSession` can stall on the OS text-input services (#5981).
    private static func endHideUi() {
        MainThreadStall.step()
        // Two event-server round trips (`tapIsEnabled`, then `tapEnable`), measured at up to 8ms on
        // macOS 26.6.2. Behind the focus request rather than in front of it: the tap's callback already
        // passes Esc through once `SwitcherSession.isActive` is false, so nothing absorbs a key in the gap.
        KeyboardEvents.updateEscapeAbsorptionTap() // session closed: stop tapping keyDown (#5766)
        UsageStats.resetSession()
        TilesView.endSearchSession()
        ContextMenuEvents.toggle(false)
        CursorEvents.toggle(false)
        TrackpadEvents.reset()
        Tooltips.hideAll()
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
        MainThreadStall.step()
        guard beginHideUi(true) else { return } // already hidden
        if let window = selectedWindow, MissionControl.state() == .inactive || MissionControl.state() == .showDesktop {
            window.focus()
            if Preferences.cursorFollowFocus == .always || (
                Preferences.cursorFollowFocus == .differentScreen && (Spaces.screenSpacesMap.first { $0.value.contains { space in window.spaceIds.contains(space) } })?.key != NSScreen.active()?.cachedUuid()) {
                moveCursorToSelectedWindow(window)
            }
        } else {
            PreviewPanel.hide()
        }
        endHideUi()
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

    static func refreshOpenUiImmediatelyAfterExternalEvent(_ windowsToScreenshot: [Window]) {
        WindowThumbnails.refreshAsync(windowsToScreenshot, .refreshUiAfterExternalEvent)
        guard SwitcherSession.isActive else { return }
        if !Windows.updatesBeforeShowing() { hideUi(); return }
        refreshUi(true)
    }

    static func refreshUi(_ preserveScrollPosition: Bool = false) {
        MainThreadStall.step()
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
        MainThreadStall.step()
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
            let isLaunchSummon = isVeryFirstSummon
            if isVeryFirstSummon {
                Windows.endStartupOrderSeeding()
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
            // The very first summon of a launch can beat the launch inventory: AltTab has been alive for a
            // few hundred milliseconds, nothing has been discovered yet, and the panel opens EMPTY and fills
            // itself under the user's eyes a beat later. Nobody is served by that frame. Ask for the scan
            // now and let the panel wait for it — capped, because a desktop that genuinely has no window
            // still has to be told so, and measured against the ~280ms an inventory takes to land.
            let awaitingLaunchInventory = isLaunchSummon && Windows.list.isEmpty
            if awaitingLaunchInventory { Applications.manuallyRefreshAllWindows() }
            let displayDelay = awaitingLaunchInventory
                ? DispatchTimeInterval.milliseconds(max(Preferences.windowDisplayDelayInMs, launchInventoryGraceInMs))
                : Preferences.windowDisplayDelay
            if displayDelay == DispatchTimeInterval.milliseconds(0) {
                buildUiAndShowPanel()
            } else {
                delayedDisplayScheduled += 1
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + displayDelay) { () -> () in
                    if delayedDisplayScheduled == 1 {
                        buildUiAndShowPanel(true)
                    }
                    delayedDisplayScheduled -= 1
                }
            }
        } else {
            cycleSelection(.leading)
            KeyRepeatTimer.startRepeatingKeyNextWindow()
        }
    }

    static func buildUiAndShowPanel(_ listChangedSincePress: Bool = false) {
        MainThreadStall.step()
        guard SwitcherSession.isActive else { return }
        // A delayed show renders a list that was filtered at the PRESS. Windows discovered during the delay
        // are appended with `shouldShowTheUser` still at its default `true`, and the repaint that would
        // filter them is throttled at 200ms — so the first frame can draw a window the filters exclude.
        // Measured on a cold start: three tabs of a 4-tab Finder group were adopted 28ms before the grace
        // expired, and the group opened unfolded as 3 tiles, then folded a beat later (QA C-01).
        if listChangedSincePress, !Windows.updatesBeforeShowing() { hideUi(); return }
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
        let isFullscreen = attendedWindowIsFullscreen(app, activeWindow)
        let shortcutsShouldBeDisabled = ExceptionMatcher.disablesShortcuts(
            app.state,
            isFullscreen: isFullscreen,
            exceptions: Preferences.exceptions)
        KeyboardEvents.toggleGlobalShortcuts(shortcutsShouldBeDisabled)
        if shortcutsShouldBeDisabled && SwitcherSession.isActive {
            hideUi()
        }
    }

    private static func attendedWindowIsFullscreen(_ app: Application, _ activeWindow: Window?) -> Bool {
        ShortcutExceptionContextResolver.isFullscreen(AttentionEngine.currentUserContext, appPid: app.pid,
            activeWindowIsFullscreen: activeWindow?.isFullscreen == true,
            windows: Windows.list.compactMap {
                guard let wid = $0.cgWindowId else { return nil }
                return FullscreenWindowEvidence(pid: $0.application.pid, wid: wid,
                    isFullscreen: $0.isFullscreen, isOnCurrentSpace: $0.spaceIds.contains(Spaces.currentSpaceId))
            })
    }

    private static var didContinueAppLaunch = false

    /// Exactly once, whatever asks. `SystemPermissions` polls every 500ms while the permissions window is
    /// up and hops its "granted" verdict to main, where `preStartupPermissionsPassed` is set, so a
    /// main-thread stall longer than one tick queues this function twice. A second run starts a second
    /// input-events thread while the first keeps running (the old RunLoop still retains the old taps'
    /// sources, so both threads get every event), and the gesture state in `TrackpadEvents` is unlocked on
    /// the grounds that one thread reaches it. Two of them segfault in `GestureTracker.prune`.
    static func continueAppLaunchAfterPermissionsAreGranted() {
        guard !didContinueAppLaunch else {
            Logger.warning { "launch continuation asked for twice; ignoring" }
            return
        }
        didContinueAppLaunch = true
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
            // The seed is NOT fired on the next line any more. This refresh is asynchronous: measured
            // 2026-08-25, its windows land ~280ms later, so a seed here ranked an empty model and the
            // first-summon call was left doing the whole job, after that summon had already drawn.
            // `Windows.reseedZOrderDuringStartup` re-makes the guess as the windows actually arrive.
            Applications.manuallyRefreshAllWindows()
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
        // With the other taps, not with `WindowServerEvents`: it needs Accessibility (`tapCreate` returns nil
        // without it) and the input-devices runloop, neither of which exists before this point.
        WindowAttentionEvents.observe()
        // Needs the AX runloop `BackgroundWork.start()` created, so it cannot go with the launch-time setup.
        AxObserverRegistry.shared.startRecoveryTicks()
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
        MainThreadStall.observe()
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
        // symbolic hotkeys state persist after the app is quit; we restore this shortcut before quitting
        setNativeCommandTabEnabled(true)
        // usage counters are appended in memory and written back on a debounce; land the pending ones
        UsageStats.flushNow()
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
