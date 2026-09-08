import Cocoa

@dynamicMemberLookup
/// Live switch destination. WindowServer surfaces which are not destinations remain in
/// `WindowSurfaceInventory`; native tabs are grouped into logical destinations by `TabGroups`.
class Window {
    private static var globalCreationCounter = Int.zero

    /// **The single backing record for every fact the reducer owns** (`TrackedWindow`), held as ONE value so
    /// the bridge moves it whole: `TrackedWindowStateBridge.modelWindow` reads it and `adopt(_:)` takes the
    /// reduced one back. A field added to `TrackedWindow` therefore crosses in both directions by
    /// construction — the field-by-field copy this replaces could not promise that, and eight fields once
    /// shipped inert because one of the two lists was missing them.
    ///
    /// Two of its fields must never be read off it directly: `cgsPhantomLatch` holds only the latched CGS
    /// verdict (the user-facing value is the derived `isPhantom` below), and `hasThumbnail` mirrors pixels
    /// this class owns. Kernels receive `state`, which patches the derived values in.
    var tracked: TrackedWindow
    /// Canonical data record this window exposes to the switcher's logic kernels (see `WindowState`), with
    /// the derived facts (`isTabbed`, `isPhantom`, the tab hold) patched in. The subscript below forwards
    /// every `TrackedWindow` field by name — `window.title` / `window.isFullscreen` / `window.spaceIds` /
    /// etc. — so call sites stay unchanged without per-property boilerplate on this class.
    var state: WindowState {
        var s = tracked.storedWindowState
        s.isTabbed = isTabbed
        s.isPhantom = isPhantom
        s.isHeldVisibleForTab = cgWindowId.map { Windows.windowsHeldVisibleForTab.contains($0) } ?? false
        s.axStatus = axStatus
        return s
    }
    /// `TrackedWindow.wid`, under the name the shell has always called it.
    var cgWindowId: CGWindowID? {
        get { tracked.wid }
        set { tracked.wid = newValue }
    }
    /// Shell-owned, so deliberately NOT in `tracked`: it records how this destination was acquired (AX vs
    /// attention), which no reducer rule or kernel decides on. Patched into `state` for the kernels.
    var axStatus = AxSemanticStatus.axVerified
    /// The pixels are shell-owned; `tracked.hasThumbnail` is the reducer's view of them, so it mirrors this.
    var thumbnail: CALayerContents? { didSet { tracked.hasThumbnail = thumbnail != nil } }
    var icon: CGImage? { get { application.icon } }
    var shouldShowTheUser = true
    /// DERIVED from the `TabGroups` registry (the single owner of group membership): the ordered members of
    /// this window's group, or nil when it's in none. The registry can't hold a group of one, so the
    /// `TabWindow` invariant (non-nil ⇒ ≥ 2 members) holds by construction.
    var tabbedSiblingWids: [CGWindowID]? { cgWindowId.flatMap { TabGroups.siblingWids(of: $0) } }
    /// DERIVED: a window is an inactive tab exactly when it belongs to a tab group AND is not the group's
    /// representative (the member the group shows). Storing this as a flag is what allowed the contradictions
    /// the registry exists to kill — a focused window flagged tabbed and hidden with nothing to correct it,
    /// members disagreeing on who is visible. Get-only, so no call site can write it back.
    var isTabbed: Bool { cgWindowId.map { TabGroups.isTabbed($0) } ?? false }
    var isHidden: Bool { get { application.isHidden } }
    var dockLabel: String? { get { application.dockLabel } }
    var screenId: ScreenUuid?
    var axUiElement: AXUIElement?
    /// Behavioral evidence is independent from AX availability. Once exact attention names this destination,
    /// later semantic refreshes may refine it but cannot pretend the interaction did not happen.
    var admissionEvidence: WindowAdmissionEvidence
    var semanticSurface: SemanticSurface?
    var application: Application
    var rowIndex: Int?
    var debugId: String!
    var lastSearchQuery: String?
    var swAppResults: [SWResult] = []
    var swTitleResults: [SWResult] = []
    var swBestSimilarity = 0.0

    /// Forwards every `TrackedWindow` field by name — `window.title` resolves to the backing record,
    /// `window.isFullscreen = true` writes through. Replaces a stack of one-per-field computed
    /// properties. The explicit `isTabbed` / `isPhantom` / `cgsPhantomLatch` / `tabbedSiblingWids` members
    /// above shadow this for the derived facts, so those can't be read stale or written at all.
    subscript<T>(dynamicMember keyPath: WritableKeyPath<TrackedWindow, T>) -> T {
        get { tracked[keyPath: keyPath] }
        set { tracked[keyPath: keyPath] = newValue }
    }

    /// Take the reduced record whole — the write half of the bridge (`TrackedWindowStateBridge.apply`).
    /// `hasThumbnail` is the one field re-derived instead of adopted: the pixels are shell-owned, and the
    /// reducer setting it true states an INTENT that the `copyThumbnail` effect fulfils after this runs, and
    /// may not (the source window can be gone by then).
    func adopt(_ record: TrackedWindow) {
        tracked = record
        tracked.hasThumbnail = thumbnail != nil
    }

    /// `axUiElement` is optional for an exact-attention destination whose app has not answered yet.
    init(_ axUiElement: AXUIElement?, _ application: Application, _ wid: CGWindowID, _ title: String?, _ isFullscreen: Bool?, _ isMinimized: Bool?, _ position: CGPoint?, _ size: CGSize?, _ axStatus: AxSemanticStatus = .axVerified, _ admissionEvidence: WindowAdmissionEvidence = .discovery) {
        tracked = TrackedWindow(id: "wid-\(wid)", wid: wid, pid: application.pid,
            spaceIds: [CGSSpaceID.max], spaceIndexes: [SpaceIndex.max])
        self.axUiElement = axUiElement
        self.admissionEvidence = admissionEvidence
        semanticSurface = nil
        self.application = application
        self.axStatus = axStatus
        self.lifecycle = axUiElement == nil ? .unverified : .alive
        // Default a new window to the current Space rather than fetching its Space here: that fetch is a
        // blocking CGS call and `Window.init` runs on the main thread (#5721). A brand-new window is on the
        // current Space ~always; the rare exception (an app restoring a window onto another Space) is
        // corrected off-main by Applications.syncSpacesState.
        self.updateSpacesAndScreen([wid: [Spaces.currentSpaceId]])
        updateFromAxAttributes(title, size, position, isFullscreen, isMinimized)
        mirrorAxElementForDestroyMatching()
        debugId = "\(self.application.debugId) (wid:\(cgWindowId) title:\(self.title))"
        Window.globalCreationCounter += 1
        self.creationOrder = Window.globalCreationCounter
        application.removeWindowlessAppWindow()
        // ensure the app's AXUIElement exists for on-demand reads + window actions (it's skipped at app init
        // for ineligible apps; having a window means the app is eligible now)
        application.ensureAxUiElement()
        // fetch app icon only if we display that app in the switcher
        application.fetchAppIcon()
        checkIfFocused()
        // debug, not info: the reducer's `.discoveryLanded` line is the one that names a new window with the
        // facts a report needs, and this fired for the same event
        Logger.debug { self.debugId }
    }

    init(_ application: Application) {
        tracked = TrackedWindow(id: "pid-\(application.pid)", wid: nil, pid: application.pid,
            spaceIds: [CGSSpaceID.max], spaceIndexes: [SpaceIndex.max], isWindowlessApp: true)
        admissionEvidence = .discovery
        semanticSurface = nil
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
        // debug, not info: `TrackedWindowState.removalLog` already names every removal WITH the reason that
        // condemned it, which is the whole point of logging one (#5785)
        Logger.debug { self.debugId }
    }

    func updateFromAxAttributes(_ title: String?, _ size: CGSize?, _ position: CGPoint?, _ isFullscreen: Bool?, _ isMinimized: Bool?) {
        self.title = bestEffortTitle(title)
        self.size = size
        self.position = position
        self.isFullscreen = isFullscreen ?? false
        self.isMinimized = isMinimized ?? false
        self.isFullscreenMirrored = false
        lastSearchQuery = nil
    }

    /// Update the WindowServer-owned facts (geometry, fullscreen) from a WS snapshot — the live path for
    /// move/resize events. Title/subrole/tabs/minimized stay on the AX read: WS can't give them cleanly, and
    /// minimized in particular can't be inferred from the WS ordered-out bit (which also fires for closing /
    /// other-Space / app-hidden windows). Returns whether a filter-relevant field changed.
    @discardableResult
    func updateFromWindowServer(position: CGPoint, size: CGSize, isFullscreen: Bool) -> Bool {
        let changed = self.position != position || self.size != size || self.isFullscreen != isFullscreen
        self.position = position
        self.size = size
        self.isFullscreen = isFullscreen
        self.isFullscreenMirrored = false
        return changed
    }

    /// DERIVED "phantom" verdict, computed at read time and never latched — so a window whose Space
    /// membership recovers shows again immediately. (It was a stored flag written monotonically on every
    /// show, which needed force-clears in three places and flapped with CGS enumeration timing, #5791.)
    /// Composition, most specific first:
    /// - a HELD tab (`windowsHeldVisibleForTab`) is never phantom: it just backgrounded as a new tab takes
    ///   over, and must keep its tile through the ~640ms discovery gap (the "window vanishes, then app icon,
    ///   then window" gap) until the incoming tab's claim or the hold release settles it;
    /// - ANY tab-group member is never phantom: a background tab is legitimately Space-less (CGS lists no
    ///   background tab on any Space), and the representative is the group's chosen tile — visibility inside
    ///   a group is the `TabGroups` registry's decision, not phantom detection's;
    /// - otherwise `PhantomWindowDetector.syncVerdict` over the stored record: the strong signal (no Space
    ///   at all — Joplin / Sprig / `show:false` Electron) evaluated live, OR'd with the latched CGS verdict
    ///   (`tracked.cgsPhantomLatch`, the only place the weak/alpha=0 case can come from — owned by
    ///   `applyCgsPhantomVerdict`) — see #5714.
    var isPhantom: Bool {
        if let wid = cgWindowId {
            if Windows.windowsHeldVisibleForTab.contains(wid) { return false }
            // Group members are exempt only while their group has a CLAIM TO THE SCREEN (a member on some
            // Space, or held mid-swap). Background tabs are legitimately Space-less and the representative
            // rides its group's claim — but a group whose EVERY member is Space-less is dead remains (Finder
            // destroys tab windows on switches; a whole generation of corpses stayed grouped, and a blanket
            // exemption kept their representative visible forever AND shielded them from the dead-window
            // sweep, rec22). Without the exemption they fall to their own facts: phantom, hidden, sweepable.
            if let gid = TabGroups.groupId(of: wid), TabGroups.hasScreenClaim(gid) { return false }
        }
        return PhantomWindowDetector.syncVerdict(tracked.storedWindowState, application.state,
            isOrderedIn: self.isOrderedIn, alpha: self.alpha)
    }

    /// The raw latched CGS verdict. Get-only on purpose: writing it must go through the two methods below,
    /// which is what keeps the latch's clearing rules in one place. Never read this as the user-facing
    /// phantom; that's the derived `isPhantom` above.
    var cgsPhantomLatch: Bool { tracked.cgsPhantomLatch }

    /// Store the authoritative CGS verdict (~250ms post-show, both signals — the only path that can SET the
    /// weak/alpha=0 case). Returns whether the derived `isPhantom` changed, so callers skip a re-render when
    /// it didn't (e.g. the verdict flipped on a group member, whose exemption absorbs it).
    @discardableResult
    func applyCgsPhantomVerdict(_ verdict: Bool) -> Bool {
        let before = isPhantom
        tracked.cgsPhantomLatch = verdict
        return isPhantom != before
    }

    /// Drop a latched CGS verdict. Used when Space membership recovers (a verdict taken mid-transition is
    /// stale — a weak-signal phantom never loses its Space, so it can't be wrongly cleared here) and when a
    /// window becomes its group's representative (the group's chosen visible tab is authoritatively not a
    /// phantom, and a latch taken while it was mid-transition must not outlive the group).
    func clearCgsPhantomLatch() {
        tracked.cgsPhantomLatch = false
    }

    /// A real window that just un-phantomed (its Space membership recovered) may belong to an app still
    /// showing a windowless icon placeholder — added on a show while the window briefly looked windowless
    /// (the empty-spaceIds blip during a fullscreen transition). Drop it. Async because the callers run
    /// inside a Windows.list iteration and removeWindowlessAppWindow mutates that list.
    private func dropStaleWindowlessPlaceholderIfUnphantomed(_ wasPhantom: Bool) {
        guard wasPhantom, !self.isPhantom, !self.isWindowlessApp else { return }
        let app = application
        DispatchQueue.main.async { app.removeWindowlessAppWindow() }
    }

    func isEqualRobust(_ otherWindowAxUiElement: AXUIElement, _ otherWindowWid: CGWindowID?) -> Bool {
        // the window can be deallocated by the OS, in which case its `CGWindowID` will be `-1`
        // we check for equality both on the AXUIElement, and the CGWindowID, in order to catch all scenarios
        return otherWindowAxUiElement == axUiElement || (cgWindowId != nil && cgWindowId != CGWindowID(bitPattern: -1) && otherWindowWid == cgWindowId)
    }


    /// Swap this window's cached AXUIElement for a fresher one (same wid). Some apps silently rebuild a
    /// window's accessibility node, invalidating our ref (#5586), so on-demand reads + the window actions
    /// would hit a dead node; swap in the freshly-resolved element.
    func rebindAxElement(_ fresh: AXUIElement) {
        axUiElement = fresh
        self.lifecycle = .alive
        mirrorAxElementForDestroyMatching()
    }

    /// Keep `AxObserverRegistry`'s element mirror in step with this window's cached element. That mirror is
    /// the only way an `AXUIElementDestroyed` can be attributed to a window: its element is dead by callback
    /// time, so `CFEqual` against what we cached is the identity, and a window missing from the mirror simply
    /// falls back to the WindowServer's order-out.
    private func mirrorAxElementForDestroyMatching() {
        guard let wid = cgWindowId else { return }
        AxObserverRegistry.noteTrackedElement(pid: application.pid, wid: wid, element: axUiElement)
    }

    /// Re-resolve this window's current AXUIElement by matching its wid against the app's live windows, to
    /// recover when the cached ref went stale. Makes AX IPC calls — invoke off the main thread.
    func refreshedAxElement() -> AXUIElement? {
        guard let wid = cgWindowId else { return nil }
        return WindowElementAcquisition.element(for: wid, pid: application.pid, route: .otherSpaceViaBruteForce)
    }

    func refreshThumbnail(_ screenshot: CALayerContents) {
        // a frame the OS drew mid-animation is much smaller than this window: keep the previous thumbnail,
        // stale but correct, while another capture is asked for (`WindowThumbnails.acceptCapture`)
        guard WindowThumbnails.acceptCapture(self, screenshot) else { return }
        thumbnail = screenshot
        if !SwitcherSession.isActive || !shouldShowTheUser { return }
        if let position = self.position, let size = self.size,
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
            // a thumbnail-scale refresh must not downgrade the sharp full-res frame the Preview may be
            // showing; the thumbnail only serves as the instant placeholder before the full-res fetch lands
            if cgWindowId.flatMap({ SwitcherSession.current?.hasPreviewFrame($0) }) != true {
                PreviewPanel.updateIfShowing(cgWindowId, screenshot, position, size)
            }
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
        guard let element = axUiElement else { return }
        let wasFullscreen = self.isFullscreen
        BackgroundWork.accessibilityCommandsQueue.addOperation {
            if wasFullscreen {
                try? element.setAttribute(kAXFullscreenAttribute, false)
                // minimizing is ignored if sent immediatly; we wait for the de-fullscreen animation to be over
                BackgroundWork.accessibilityCommandsQueue.addOperationAfter(deadline: .now() + .seconds(1)) {
                    if let closeButton_ = try? element.attributes([kAXCloseButtonAttribute]).closeButton {
                        try? closeButton_.performAction(kAXPressAction)
                    }
                }
            } else {
                if let closeButton_ = try? element.attributes([kAXCloseButtonAttribute]).closeButton {
                    try? closeButton_.performAction(kAXPressAction)
                }
            }
        }
        // No optimistic removal: the window leaves Windows.list only when the OS confirms it's gone, and
        // three signals can say so. The app's own AXUIElementDestroyed is normally first and is the only one
        // that reaches a close while the window is minimized, hidden, on another Space or a background tab.
        // The order-out (816) covers the on-screen close for an app that has never been seen to deliver a
        // destroy, via an AX-liveness probe. The WindowServer's destroy (804) is the last backstop, and it can
        // lag by seconds — measured 7.4s behind the destroy — or never fire for an app that retains its
        // CGWindow. The switcher reflects OS state, never a predicted one.
    }

    /// Every one of these commands is an AX write. A window kept on WindowServer evidence alone has no
    /// element to write to, so it fails safely with the same beep an ineligible window gets rather than
    /// force-unwrapping nil.
    func canBeMinDeminOrFullscreened() -> Bool {
        return !self.isWindowlessApp && !self.isTabbed && (axUiElement != nil || altTabWindow() != nil)
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
            guard let self, let element = self.axUiElement else { return }
            if self.isFullscreen {
                try? element.setAttribute(kAXFullscreenAttribute, false)
                // minimizing is ignored if sent immediatly; we wait for the de-fullscreen animation to be over
                BackgroundWork.accessibilityCommandsQueue.addOperationAfter(deadline: .now() + .seconds(1)) { [weak self] in
                    guard let self, let element = self.axUiElement else { return }
                    try? element.setAttribute(kAXMinimizedAttribute, true)
                }
            } else {
                try? element.setAttribute(kAXMinimizedAttribute, !self.isMinimized)
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
            guard let self, let element = self.axUiElement else { return }
            try? element.setAttribute(kAXFullscreenAttribute, !self.isFullscreen)
        }
    }

    func focus() {
        MainThreadStall.step()
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
            // Only repair the origin Space (step 4) when we KNOW the target is on another Space. Empty spaceIds
            // means "Space unknown": the window was missing from the last CGS map (Slack windows drop out of it,
            // and it goes stale after sleep/monitor changes until syncSpacesState re-queries). Treating unknown
            // as cross-Space ran SLSSpaceSetFrontPSN on the CURRENT Space, re-fronting the previous app and
            // undoing the raise while the window stayed key (#5586, the Slack-after-sleep variant).
            // AltTab knows exactly which window it is focusing — record it so the coming app activation
            // bumps this window directly instead of divining the focus from a racy 808 / AX read (#5596).
            WindowServerEvents.noteAltTabInitiatedFocus(cgWindowId!, application.pid)
            Windows.promoteAttentionEvidence(cgWindowId!)
            let targetMaybeCrossSpace = !self.spaceIds.isEmpty && !self.spaceIds.contains(originSpaceId)
            let originFrontPid = targetMaybeCrossSpace
                ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
            BackgroundWork.accessibilityCommandsQueue.addOperation { [weak self] in
                guard let self else { return }
                if self.isMinimized, let element = self.axUiElement {
                    try? element.setAttribute(kAXMinimizedAttribute, false)
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
                //   3. raiseWindow (kAXRaiseAction): raise it within the app's own window stack. If our cached
                //      element went stale (the app silently rebuilt the window's a11y node, #5586), this returns
                //      .invalidUIElement and no-ops, so re-resolve the live element by wid, retry, and heal the
                //      cache; _SLPS/makeKeyWindow above use the wid/psn directly so they're unaffected.
                //   4. cross-Space only: restore the origin Space's front process (see snapshot above).
                var psn = ProcessSerialNumber()
                GetProcessForPID(self.application.pid, &psn)
                _SLPSSetFrontProcessWithOptions(&psn, self.cgWindowId!, SLPSMode.userGenerated.rawValue)
                makeKeyWindow(&psn, self.cgWindowId!)
                // Step 3 is the only AX-dependent step: 1 and 2 use the wid and psn directly, so a window
                // with no element still gets fronted and made key — which is the whole point of keeping a
                // hung app's window trackable.
                if self.axUiElement?.raiseWindow() != .success, let fresh = self.refreshedAxElement() {
                    fresh.raiseWindow()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.axUiElement != fresh else { return }
                        self.rebindAxElement(fresh)
                        Windows.promoteVerified(self.cgWindowId ?? 0)
                    }
                }
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

    /// For some windows (e.g. Slack) the AX API returns no title, so we fall back to the WindowServer's, and
    /// finally to the app name.
    ///
    /// The WindowServer title is taken from the inventory snapshot rather than asked for: this runs on the
    /// MAIN thread (`Window.init`, and the apply half of every title read), where `CGSCopyWindowProperty` is a
    /// synchronous WindowServer round trip on the show path — and the batched query that fills the inventory
    /// already fetched exactly this string (`SLSWindowIteratorCopyTitle`), refreshed on every geometry event.
    /// The live call remains for a wid the inventory has no row for, so nothing that used to resolve stops.
    /// Flattened on the way in, so no consumer ever sees a line break: `WindowTitle` says what that costs
    /// when one gets through.
    func bestEffortTitle(_ axTitle: String?) -> String {
        WindowTitle.singleLine(rawBestEffortTitle(axTitle))
    }

    private func rawBestEffortTitle(_ axTitle: String?) -> String {
        if let axTitle, !axTitle.isEmpty {
            return axTitle
        }
        if let cgWindowId {
            if let row = WindowSurfaceInventory.raw(cgWindowId) {
                if !row.title.isEmpty { return row.title }
            } else if let cgTitle = cgWindowId.title(), !cgTitle.isEmpty {
                return cgTitle
            }
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

    private func updateSpaces(_ windowToSpacesMap: [CGWindowID: [CGSSpaceID]]? = nil) {
        guard let cgWindowId else { return }
        let wasEmpty = self.spaceIds.isEmpty
        let wasPhantom = self.isPhantom
        // No blocking CGS fallback here: callers always supply the map (resolved off-main, or the current
        // Space at creation). A window absent from the map is treated as on no queried Space (#5721).
        var spaceIds = windowToSpacesMap?[cgWindowId] ?? []
        var borrowed = false
        // inactive tabs return no space from CGSCopySpacesForWindows; use the active tab sibling's space
        if spaceIds.isEmpty, let activeTab = TabGroup.activeTabSibling(of: self) {
            spaceIds = activeTab.spaceIds
            borrowed = !spaceIds.isEmpty
        }
        self.spaceIsBorrowed = borrowed
        self.spaceIds = spaceIds
        self.spaceIndexes = spaceIds.compactMap { spaceId in Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1 }
        self.isOnAllSpaces = spaceIds.count > 1
        // A CGS verdict latched while this window's Spaces were briefly empty (mid Space-transition, e.g.
        // going fullscreen) is stale now that CGS placed it again; the live strong signal un-latches by
        // itself (isPhantom is derived), the stored verdict needs the explicit clear. Safe: a weak-signal
        // phantom always keeps a non-empty Space, so it never recovers here.
        if wasEmpty, !spaceIds.isEmpty { clearCgsPhantomLatch() }
        dropStaleWindowlessPlaceholderIfUnphantomed(wasPhantom)
    }

    /// Internal (not private): also invoked by `TrackedWindowStateBridge` for the reducer's `updateScreenId` effect
    /// — an `NSScreen`-coupled derivation the pure layer can't do.
    func updateScreenId() {
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

    /// Seed the per-app focused-window fact after discovery. An app already frontmost when AltTab starts has
    /// produced no activation or AX focus change, so `kAXFocusedWindow` is the only initial answer (#5665).
    ///
    /// The answer is always recorded as a fact about that process; `AttentionModel` alone decides whether the
    /// process is frontmost when it lands. The scheduler key is per pid rather than per wid so a startup batch
    /// does not ask the same app once for every window.
    private func checkIfFocused() {
        let app = application
        guard let appAxUiElement = app.axUiElement else { return }
        AXCallScheduler.shared.schedule(key: "pid-\(app.pid)-discovery-focus", context: debugId, pid: app.pid) { [weak app] in
            guard let app, let focusedWindow = try appAxUiElement.attributes([kAXFocusedWindowAttribute], pid: app.pid).focusedWindow else { return }
            let focusedWid = try focusedWindow.cgWindowId(pid: app.pid)
            DispatchQueue.main.async {
                guard let window = (Windows.list.first { $0.isEqualRobust(focusedWindow, focusedWid) }) else { return }
                // This shell cache feeds actions and shortcut checks; the attention model independently owns
                // whether the per-app fact moves the visible front.
                app.focusedWindow = window
                guard let wid = window.cgWindowId else { return }
                TrackedWindowStateBridge.dispatch(.axFocusedWindowRead(pid: app.pid, wid: wid,
                    viaActivationRead: false))
            }
        }
    }
}
