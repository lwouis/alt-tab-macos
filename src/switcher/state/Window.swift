import Cocoa

@dynamicMemberLookup
class Window {
    private static let notifications = [
        kAXUIElementDestroyedNotification,
        kAXTitleChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXWindowResizedNotification,
        kAXWindowMovedNotification,
    ]
    private static var globalCreationCounter = Int.zero

    /// Canonical data record this window exposes to the switcher's logic kernels (see
    /// `WindowState`). The subscript below forwards every `WindowState` field by name —
    /// `window.title` / `window.isFullscreen` / `window.spaceIds` / etc. resolve to `state`'s
    /// fields — so call sites stay unchanged without per-property boilerplate on this class.
    var state: WindowState
    var cgWindowId: CGWindowID?
    var thumbnail: CALayerContents?
    var icon: CGImage? { get { application.icon } }
    var shouldShowTheUser = true
    var tabbedSiblingWids: [CGWindowID]?
    var isHidden: Bool { get { application.isHidden } }
    var dockLabel: String? { get { application.dockLabel } }
    var position: CGPoint?
    var size: CGSize?
    var screenId: ScreenUuid?
    var axUiElement: AXUIElement?
    var application: Application
    var axObserver: AXObserver?
    var rowIndex: Int?
    var debugId: String!
    var lastSearchQuery: String?
    var swAppResults: [SWResult] = []
    var swTitleResults: [SWResult] = []
    var swBestSimilarity = 0.0

    /// Forwards every `WindowState` field by name — `window.title` resolves to `state.title`,
    /// `window.isFullscreen = true` writes through. Replaces a stack of one-per-field computed
    /// properties.
    subscript<T>(dynamicMember keyPath: WritableKeyPath<WindowState, T>) -> T {
        get { state[keyPath: keyPath] }
        set { state[keyPath: keyPath] = newValue }
    }

    init(_ axUiElement: AXUIElement, _ application: Application, _ wid: CGWindowID, _ title: String?, _ isFullscreen: Bool?, _ isMinimized: Bool?, _ position: CGPoint?, _ size: CGSize?) {
        state = WindowState(
            id: "wid-\(wid)", isPhantom: false, isWindowlessApp: false,
            isFullscreen: false, isMinimized: false, isTabbed: false,
            isOnAllSpaces: false, spaceIds: [CGSSpaceID.max], spaceIndexes: [SpaceIndex.max],
            lastFocusOrder: .zero, creationOrder: .zero, title: "")
        self.axUiElement = axUiElement
        self.application = application
        cgWindowId = wid
        // Default a new window to the current Space rather than fetching its Space here: that fetch is a
        // blocking CGS call and `Window.init` runs on the main thread (#5721). A brand-new window is on the
        // current Space ~always; the rare exception (an app restoring a window onto another Space) is
        // corrected off-main by Applications.syncSpacesState.
        self.updateSpacesAndScreen([wid: [Spaces.currentSpaceId]])
        updateFromAxAttributes(title, size, position, isFullscreen, isMinimized)
        debugId = "\(self.application.debugId) (wid:\(cgWindowId) title:\(self.title))"
        Window.globalCreationCounter += 1
        self.creationOrder = Window.globalCreationCounter
        application.removeWindowlessAppWindow()
        // the app may have timed out trying to subscribe to app notifications
        // It may be responsive now since it has a window; we attempt again
        application.observeEventsIfEligible()
        // fetch app icon only if we display that app in the switcher
        application.fetchAppIcon()
        checkIfFocused()
        Logger.info { self.debugId }
        observeEvents()
    }

    init(_ application: Application) {
        state = WindowState(
            id: "pid-\(application.pid)", isPhantom: false, isWindowlessApp: true,
            isFullscreen: false, isMinimized: false, isTabbed: false,
            isOnAllSpaces: false, spaceIds: [CGSSpaceID.max], spaceIndexes: [SpaceIndex.max],
            lastFocusOrder: .zero, creationOrder: .zero, title: "")
        self.application = application
        self.title = bestEffortTitle(nil)
        Window.globalCreationCounter += 1
        self.creationOrder = Window.globalCreationCounter
        debugId = "\(application.debugId) (title:\(self.title))"
        // fetch app icon only if we display that app in the switcher
        application.fetchAppIcon()
        Logger.debug { self.debugId }
    }

    deinit {
        Logger.info { self.debugId }
    }

    /// Symmetric counterpart to the `CFRunLoopAddSource` in `observeEvents()`.
    /// CFRunLoop strongly retains every source ever added; without an explicit remove,
    /// every Window we ever observed leaves an orphaned AXObserver source pinned in
    /// `BackgroundWork.accessibilityEventsThread.runLoop` for the rest of the app's lifetime.
    /// This is the dominant contributor to the 399 GB virtual-memory growth users see in
    /// long-running sessions (issue #5612 etc.).
    /// Called from `Windows.removeWindows`. CFRunLoopRemoveSource is thread-safe so
    /// invoking from the main thread on another runloop's source is fine.
    func releaseAxObserver() {
        if let axObserver, let runLoop = BackgroundWork.accessibilityEventsThread?.runLoop {
            CFRunLoopRemoveSource(runLoop, AXObserverGetRunLoopSource(axObserver), .commonModes)
        }
        // Nil-out so ARC releases the AXObserver — its dealloc tears down all
        // notification subscriptions in the AX framework automatically.
        axObserver = nil
    }

    func updateFromAxAttributes(_ title: String?, _ size: CGSize?, _ position: CGPoint?, _ isFullscreen: Bool?, _ isMinimized: Bool?) {
        self.title = bestEffortTitle(title)
        self.size = size
        self.position = position
        self.isFullscreen = isFullscreen ?? false
        self.isMinimized = isMinimized ?? false
        lastSearchQuery = nil
        recomputeIsPhantom()
    }

    /// Synchronous "phantom" detection — assert-only (may set `isPhantom`, never clears it). Catches the
    /// strong signal (no Space at all: Joplin / Sprig / "show:false" Electron) at creation/show time,
    /// reusing the spaceIds already populated by updateSpaces (cgWindowId.spaces()) — no new CGS call.
    /// Clearing is owned by Applications.refreshIsPhantom (the authoritative CGS-based catch-all that
    /// also handles alpha=0 / orderOut: phantoms that keep a Space); clearing here would clobber it on
    /// every show. See PhantomWindowDetector.syncVerdict and PhantomWindowDetection.swift (#5714).
    func recomputeIsPhantom() {
        self.isPhantom = PhantomWindowDetector.syncVerdict(state, application.state)
    }

    func isEqualRobust(_ otherWindowAxUiElement: AXUIElement, _ otherWindowWid: CGWindowID?) -> Bool {
        // the window can be deallocated by the OS, in which case its `CGWindowID` will be `-1`
        // we check for equality both on the AXUIElement, and the CGWindowID, in order to catch all scenarios
        return otherWindowAxUiElement == axUiElement || (cgWindowId != nil && cgWindowId != CGWindowID(bitPattern: -1) && otherWindowWid == cgWindowId)
    }

    private func observeEvents() {
        AXObserverCreate(application.pid, AccessibilityEvents.axObserverCallback, &axObserver)
        guard let axObserver else { return }
        AXCallScheduler.shared.schedule(key: "sub-win-\(cgWindowId)", context: debugId, pid: application.pid) { [weak self] in
            guard let self else { return }
            if try self.axUiElement!.subscribeToNotification(axObserver, Window.notifications.first!, AccessibilityEvents.subscriptionRefcon(self.application.pid, self.cgWindowId ?? 0)) {
                Logger.debug { "Subscribed to window: \(self.debugId)" }
                for notification in Window.notifications.dropFirst() {
                    AXCallScheduler.shared.schedule(key: "sub-win-\(cgWindowId)-\(notification)", context: self.debugId, pid: self.application.pid) { [weak self] in
                        guard let self else { return }
                        try self.axUiElement!.subscribeToNotification(axObserver, notification, AccessibilityEvents.subscriptionRefcon(self.application.pid, self.cgWindowId ?? 0))
                    }
                }
            }
        }
        CFRunLoopAddSource(BackgroundWork.accessibilityEventsThread.runLoop, AXObserverGetRunLoopSource(axObserver), .commonModes)
    }

    func refreshThumbnail(_ screenshot: CALayerContents) {
        thumbnail = screenshot
        if !SwitcherSession.isActive || !shouldShowTheUser { return }
        if let position, let size,
           let view = (TilesView.recycledViews.first { $0.window_?.cgWindowId == cgWindowId }) {
            if !view.thumbnail.isHidden {
                let thumbnailSize = TileView.thumbnailSize(size, false)
                let newSize = thumbnailSize.width != view.thumbnail.frame.width || thumbnailSize.height != view.thumbnail.frame.height
                view.thumbnail.updateContents(screenshot, thumbnailSize)
                // if the thumbnail size has changed, we need to refresh the open UI
                if newSize {
                    App.refreshOpenUiAfterExternalEvent([])
                }
            }
            PreviewPanel.updateIfShowing(cgWindowId, screenshot, position, size)
        }
    }

    func canBeClosed() -> Bool {
        return !self.isWindowlessApp
    }

    func close() {
        if !canBeClosed() {
            NSSound.beep()
            return
        }
        if let altTabWindow = altTabWindow() {
            altTabWindow.close()
            return
        }
        BackgroundWork.accessibilityCommandsQueue.addOperation { [weak self] in
            guard let self else { return }
            if self.isFullscreen {
                try? self.axUiElement!.setAttribute(kAXFullscreenAttribute, false)
                // minimizing is ignored if sent immediatly; we wait for the de-fullscreen animation to be over
                BackgroundWork.accessibilityCommandsQueue.addOperationAfter(deadline: .now() + .seconds(1)) { [weak self] in
                    guard let self else { return }
                    if let closeButton_ = try? self.axUiElement!.attributes([kAXCloseButtonAttribute]).closeButton {
                        try? closeButton_.performAction(kAXPressAction)
                    }
                }
            } else {
                if let closeButton_ = try? self.axUiElement!.attributes([kAXCloseButtonAttribute]).closeButton  {
                    try? closeButton_.performAction(kAXPressAction)
                }
            }
        }
    }

    func canBeMinDeminOrFullscreened() -> Bool {
        return !self.isWindowlessApp && !self.isTabbed
    }

    func minDemin() {
        if !canBeMinDeminOrFullscreened() {
            NSSound.beep()
            return
        }
        if let altTabWindow = altTabWindow() {
            self.isMinimized ? altTabWindow.deminiaturize(nil) : altTabWindow.miniaturize(nil)
            return
        }
        BackgroundWork.accessibilityCommandsQueue.addOperation { [weak self] in
            guard let self else { return }
            if self.isFullscreen {
                try? self.axUiElement!.setAttribute(kAXFullscreenAttribute, false)
                // minimizing is ignored if sent immediatly; we wait for the de-fullscreen animation to be over
                BackgroundWork.accessibilityCommandsQueue.addOperationAfter(deadline: .now() + .seconds(1)) { [weak self] in
                    guard let self else { return }
                    try? self.axUiElement!.setAttribute(kAXMinimizedAttribute, true)
                }
            } else {
                try? self.axUiElement!.setAttribute(kAXMinimizedAttribute, !self.isMinimized)
            }
        }
    }

    func toggleFullscreen() {
        if !canBeMinDeminOrFullscreened() {
            NSSound.beep()
            return
        }
        if let altTabWindow = altTabWindow() {
            altTabWindow.toggleFullScreen(nil)
            return
        }
        BackgroundWork.accessibilityCommandsQueue.addOperation { [weak self] in
            guard let self else { return }
            try? self.axUiElement!.setAttribute(kAXFullscreenAttribute, !self.isFullscreen)
        }
    }

    func focus() {
        if let altTabWindow = altTabWindow() {
            App.shared.activate(ignoringOtherApps: true)
            altTabWindow.makeKeyAndOrderFront(nil)
            WindowThumbnails.previewSelectedIfNeeded()
        } else if self.isWindowlessApp || cgWindowId == nil {
            if let bundleUrl = application.bundleURL, self.isWindowlessApp {
                if (try? NSWorkspace.shared.launchApplication(at: bundleUrl, configuration: [:])) == nil {
                    application.runningApplication.activate(options: .activateAllWindows)
                }
            } else {
                application.runningApplication.activate(options: .activateAllWindows)
            }
            WindowThumbnails.previewSelectedIfNeeded()
        } else {
            // macOS bug: when switching to a System Preferences window in another space, it switches to that space,
            // but quickly switches back to another window in that space
            // You can reproduce this buggy behaviour by clicking on the dock icon, proving it's an OS bug
            let originSpaceId = Spaces.currentSpaceId
            let targetOnCurrentSpace = self.spaceIds.contains(originSpaceId)
            let originFrontPid = targetOnCurrentSpace ? nil : NSWorkspace.shared.frontmostApplication?.processIdentifier
            BackgroundWork.accessibilityCommandsQueue.addOperation { [weak self] in
                guard let self else { return }
                if self.isMinimized {
                    try? self.axUiElement!.setAttribute(kAXMinimizedAttribute, false)
                }
                // Focusing another app's window reliably takes the steps below. The public APIs alone don't
                // move key focus across apps (macOS 14 downgraded NSRunningApplication.activate to an advisory
                // "request").
                //   1. _SLPSSetFrontProcessWithOptions fronts the process + the target window (passing the wid
                //      raises only that window, not all the app's windows). For a cross-Space target it also
                //      makes macOS switch to a Space showing it. The global front clobbers the front process of
                //      other Spaces where the app has windows (they pop on Space entry, #4507); step 4 repairs
                //      the origin Space for a cross-Space focus.
                //   2. makeKeyWindow: make it key, via a synthetic mouse-down/up aimed just outside the window,
                //      so it becomes key without clicking its content (a top-left click would hit fullscreen UI, #5381).
                //   3. focusWindow (kAXRaiseAction): raise it within the app's own window stack.
                //   4. cross-Space only: restore the origin Space's front process (see snapshot above).
                var psn = ProcessSerialNumber()
                GetProcessForPID(self.application.pid, &psn)
                _SLPSSetFrontProcessWithOptions(&psn, self.cgWindowId!, SLPSMode.userGenerated.rawValue)
                makeKeyWindow(&psn, self.cgWindowId!)
                try? self.axUiElement!.focusWindow()
                // step 4 (#4507): undo step 1's clobber of the origin Space. The front-switch made that Space
                // remember our app as its front; restore the app that was there before (snapshotted above) so
                // returning shows it, not our window. Cross-Space only (originFrontPid is nil otherwise), and
                // skipped when the origin's front was already this app.
                if let originFrontPid, originFrontPid != self.application.pid {
                    var originPsn = ProcessSerialNumber()
                    GetProcessForPID(originFrontPid, &originPsn)
                    SLSSpaceSetFrontPSN(CGS_CONNECTION, originSpaceId, originPsn)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                    WindowThumbnails.previewSelectedIfNeeded()
                }
            }
        }
    }

    // for some windows (e.g. Slack), the AX API doesn't return a title; we try CG API; finally we resort to the app name
    func bestEffortTitle(_ axTitle: String?) -> String {
        if let axTitle, !axTitle.isEmpty {
            return axTitle
        }
        if let cgWindowId, let cgTitle = cgWindowId.title(), !cgTitle.isEmpty {
            return cgTitle
        }
        return application.localizedName ?? ""
    }

    func updateSpacesAndScreen(_ windowToSpacesMap: [CGWindowID: [CGSSpaceID]]? = nil) {
        // macOS bug: if you tab a window, then move the tab group to another space, other tabs from the tab group will stay on the current space
        // you can use the Dock to focus one of the other tabs and it will teleport that tab in the current space, proving that it's a macOS bug
        // note: for some reason, it behaves differently if you minimize the tab group after moving it to another space
        updateSpaces(windowToSpacesMap)
        updateScreenId()
    }

    /// Apply a freshly-queried window→Spaces map (from `Applications.syncSpacesState`), returning whether
    /// `spaceIds` changed — the filter-relevant input — so the caller can skip a re-render when nothing
    /// moved. `spaceIndexes`/`isOnAllSpaces`/`screenId` all derive from `spaceIds`.
    @discardableResult
    func applySpacesAndScreen(_ windowToSpacesMap: [CGWindowID: [CGSSpaceID]]) -> Bool {
        let beforeSpaceIds = self.spaceIds
        updateSpacesAndScreen(windowToSpacesMap)
        return self.spaceIds != beforeSpaceIds
    }

    private func updateSpaces(_ windowToSpacesMap: [CGWindowID: [CGSSpaceID]]? = nil) {
        guard let cgWindowId else { return }
        // No blocking CGS fallback here: callers always supply the map (resolved off-main, or the current
        // Space at creation). A window absent from the map is treated as on no queried Space (#5721).
        var spaceIds = windowToSpacesMap?[cgWindowId] ?? []
        // inactive tabs return no space from CGSCopySpacesForWindows; use the active tab sibling's space
        if spaceIds.isEmpty, let activeTab = TabGroup.activeTabSibling(of: self) {
            spaceIds = activeTab.spaceIds
        }
        self.spaceIds = spaceIds
        self.spaceIndexes = spaceIds.compactMap { spaceId in Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1 }
        self.isOnAllSpaces = spaceIds.count > 1
        recomputeIsPhantom()
    }

    private func updateScreenId() {
        screenId = NSScreen.screens.first { isOnScreen($0) }?.cachedUuid()
    }

    /// window may not be visible on that screen (e.g. the window is not on the current Space)
    func isOnScreen(_ screen: NSScreen) -> Bool {
        if NSScreen.screensHaveSeparateSpaces {
            if let screenUuid = screen.cachedUuid(), let screenSpaces = Spaces.screenSpacesMap[screenUuid] {
                return screenSpaces.contains { screenSpace in self.spaceIds.contains { $0 == screenSpace } }
            }
        } else {
            let referenceWindow = referenceWindowForTabbedWindow()
            if let topLeftCorner = referenceWindow?.position, let size = referenceWindow?.size {
                var screenFrameInQuartzCoordinates = screen.frame
                screenFrameInQuartzCoordinates.origin.y = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(screen.frame)
                let windowRect = CGRect(origin: topLeftCorner, size: size)
                return windowRect.intersects(screenFrameInQuartzCoordinates)
            }
        }
        return true
    }

    func referenceWindowForTabbedWindow() -> Window? {
        // if the window is tabbed, we can't know its position/size before it's focused, so we use the currently
        // visible window-tab. Its data will match the tabbed window's
        // fallback to the focusedWindow
        self.isTabbed ? (TabGroup.activeTabSibling(of: self) ?? application.focusedWindow) : self
    }

    private func altTabWindow() -> NSWindow? {
        if application.bundleURL == App.bundleURL, let cgWindowId {
            return App.shared.window(withWindowNumber: Int(cgWindowId))
        }
        return nil
    }

    /// Scenarios addressed by this:
    /// * Some apps will not trigger AXApplicationActivated, where we usually update application.focusedWindow
    /// * Sometimes, we subscribe to an app after it has emitted the focusedWindow / applicationActivated events, so we never receive these
    private func checkIfFocused() {
        let app = application
        guard let appAxUiElement = app.axUiElement else { return }
        AXCallScheduler.shared.schedule(key: "wid-\(cgWindowId)-focus", context: debugId, pid: app.pid) { [weak app] in
            guard let app, let focusedWindow = try appAxUiElement.attributes([kAXFocusedWindowAttribute]).focusedWindow else { return }
            let focusedWid = try focusedWindow.cgWindowId()
            DispatchQueue.main.async {
                guard let window = (Windows.list.first { $0.isEqualRobust(focusedWindow, focusedWid) }) else { return }
                app.focusedWindow = window
                if let windows = Windows.updateLastFocusOrder(window) {
                    App.refreshOpenUiAfterExternalEvent(windows)
                }
            }
        }
    }
}
