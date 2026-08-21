import Cocoa

@dynamicMemberLookup
class Window {
    private static var globalCreationCounter = Int.zero

    /// Backing record for the fields this window OWNS. Two of its fields are NOT owned here and must never
    /// be read off it directly: `isTabbed` is dead storage (the live value is derived from the `TabGroups`
    /// registry — see the computed property below), and `isPhantom` holds only the latched CGS verdict
    /// (written by `applyCgsPhantomVerdict`; the user-facing value is the derived `isPhantom` below).
    /// Kernels receive `state`, which patches both derived values in.
    private var storedState: WindowState
    /// Canonical data record this window exposes to the switcher's logic kernels (see `WindowState`), with
    /// the two derived facts (`isTabbed`, `isPhantom`) patched in. The subscript below forwards every other
    /// `WindowState` field by name — `window.title` / `window.isFullscreen` / `window.spaceIds` / etc. —
    /// so call sites stay unchanged without per-property boilerplate on this class.
    var state: WindowState {
        var s = storedState
        s.isTabbed = isTabbed
        s.isPhantom = isPhantom
        s.isHeldVisibleForTab = cgWindowId.map { Windows.windowsHeldVisibleForTab.contains($0) } ?? false
        return s
    }
    var cgWindowId: CGWindowID?
    var thumbnail: CALayerContents?
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
    /// True when `spaceIds` was COPIED from a tab sibling (the backfill onto background tabs; the borrow onto
    /// a representative that just backgrounded) rather than reported by CGS/WindowServer. A borrowed Space is
    /// OUR annotation, not evidence: rules that read "holds a Space" as "genuinely on-screen" must see this
    /// flag, or the annotation defeats them — three recordings each found one such rule (rec14: the hold;
    /// rec20: a brand-new active's claim rejecting its group's ex-representative, orphaning it as a permanent
    /// stray tile). Cleared whenever genuine Space evidence arrives (a CGS map hit, a 1325/1326 delta).
    ///
    /// Leaving the group does NOT clear it, and does not strip the Space either. It used to: the borrow was
    /// "dropped with the membership that justified it", which wrote a fact nobody had told us — "CGS places
    /// this window nowhere" — and that is precisely the strong phantom signal, so an ungrouped window was
    /// HIDDEN on our own guess. Live case (QA T-05): "Move Tab to New Window", the group re-forms around the
    /// other two members, and the window the user had just torn out vanished from the switcher for 515ms,
    /// until `spacesSynced` re-read the Space CGS had held for it the whole time. rec20's stray is answered
    /// by this flag alone — every claim rule reads it, with the Space still set
    /// (`testExRepresentativeWithABorrowedSpaceIsClaimable`) — and an ex-member that is genuinely gone is not
    /// left standing: `spacesSynced` applies `[]` to every wid it QUERIED and its map doesn't place, which
    /// turns it phantom and hands it to the dead-window sweep.
    var spaceIsBorrowed = false
    /// The Space this window most recently LEFT (a 1326 names it), nil once it joins one again — the history
    /// tab-grouping needs to tell a just-backgrounded tab from a brand-new one. Owned by the reducer.
    var lastLeftSpaceId: UInt64?
    /// The handover edge: the wid that took this window's place on the Space it just left, and the wid this
    /// one replaced when it joined. Owned by the reducer; see `TrackedWindow.replacedByWid` for why a Space
    /// cannot answer what a wid can.
    var replacedByWid: CGWindowID?
    var replacedWid: CGWindowID?
    /// Tab-button count from this window's last AXTabGroup read (0 = none / not tabbed). Owned by the
    /// reducer; see `TabWindow.tabCount` for why the COUNT is trusted where the tab TITLES are not.
    var tabCount = 0
    /// True when `isFullscreen` was MIRRORED from the active tab sibling (a background tab gets no WS
    /// geometry event, so its own flag would go stale — the mirror keeps the fullscreen/minimized FILTERS
    /// correct for the whole group). Like `spaceIsBorrowed`, it marks a synthetic write: tab-grouping rules
    /// must see only GENUINE (OS-reported) fullscreen — a frozen 920×436 background tab wearing the mirrored
    /// flag poisoned the whole windowed size-cluster (geometry stopped splitting it by frame and folded it;
    /// the title claim waived its exact-position test), merging 25 windows across three frames and hiding a
    /// real window (rec21). Cleared whenever the WindowServer reports the flag genuinely.
    var isFullscreenMirrored = false
    /// When the OS last told us this window came forward — the MRU truth, from which `lastFocusOrder` is
    /// derived. Written only by the reducer (`TrackedWindowState.noteFocus`, applied through the bridge); it
    /// lives here so it survives between dispatches, since the state is re-snapshotted from the live model
    /// each time. Orchestration bookkeeping, deliberately NOT in `WindowState`: kernels rank windows, they
    /// don't time them. See `TrackedWindow.focusedAt`.
    var focusedAt: TimeInterval = 0
    var isHidden: Bool { get { application.isHidden } }
    var dockLabel: String? { get { application.dockLabel } }
    var position: CGPoint?
    var size: CGSize?
    var screenId: ScreenUuid?
    var axUiElement: AXUIElement?
    var application: Application
    var rowIndex: Int?
    var debugId: String!
    var lastSearchQuery: String?
    var swAppResults: [SWResult] = []
    var swTitleResults: [SWResult] = []
    var swBestSimilarity = 0.0

    /// Forwards every `WindowState` field by name — `window.title` resolves to the stored record,
    /// `window.isFullscreen = true` writes through. Replaces a stack of one-per-field computed
    /// properties. The explicit `isTabbed` / `isPhantom` / `tabbedSiblingWids` members above shadow this
    /// for the derived facts, so those can't be read stale or written at all.
    subscript<T>(dynamicMember keyPath: WritableKeyPath<WindowState, T>) -> T {
        get { storedState[keyPath: keyPath] }
        set { storedState[keyPath: keyPath] = newValue }
    }

    init(_ axUiElement: AXUIElement, _ application: Application, _ wid: CGWindowID, _ title: String?, _ isFullscreen: Bool?, _ isMinimized: Bool?, _ position: CGPoint?, _ size: CGSize?) {
        storedState = WindowState(
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
        storedState = WindowState(
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
        isFullscreenMirrored = false
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
        isFullscreenMirrored = false
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
    ///   (`storedState.isPhantom`, the only place the weak/alpha=0 case can come from — owned by
    ///   `applyCgsPhantomVerdict`). See PhantomWindowDetection.swift (#5714).
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
        return PhantomWindowDetector.syncVerdict(storedState, application.state)
    }

    /// The raw latched CGS verdict (`storedState.isPhantom`) — what `TrackedWindowStateBridge` snapshots into
    /// `TrackedWindow.cgsPhantomLatch`. Never read this as the user-facing phantom; that's the derived
    /// `isPhantom` above.
    var cgsPhantomLatch: Bool { storedState.isPhantom }

    /// Store the authoritative CGS verdict (~250ms post-show, both signals — the only path that can SET the
    /// weak/alpha=0 case). Returns whether the derived `isPhantom` changed, so callers skip a re-render when
    /// it didn't (e.g. the verdict flipped on a group member, whose exemption absorbs it).
    @discardableResult
    func applyCgsPhantomVerdict(_ verdict: Bool) -> Bool {
        let before = isPhantom
        storedState.isPhantom = verdict
        return isPhantom != before
    }

    /// Drop a latched CGS verdict. Used when Space membership recovers (a verdict taken mid-transition is
    /// stale — a weak-signal phantom never loses its Space, so it can't be wrongly cleared here) and when a
    /// window becomes its group's representative (the group's chosen visible tab is authoritatively not a
    /// phantom, and a latch taken while it was mid-transition must not outlive the group).
    func clearCgsPhantomLatch() {
        storedState.isPhantom = false
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
        // No optimistic removal: the window leaves Windows.list only when the OS confirms it's gone. Closing
        // orders the window out, and WindowServerEvents turns that into an AX-liveness probe: a dead element
        // means the window is gone, so Applications.removeIfClosedAfterOrderOut removes it. The WindowServer
        // destroy event (804) is the backstop for a close that fires no order-out we see (already off-screen).
        // The switcher reflects OS state, never a predicted one.
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
            // Only repair the origin Space (step 4) when we KNOW the target is on another Space. Empty spaceIds
            // means "Space unknown": the window was missing from the last CGS map (Slack windows drop out of it,
            // and it goes stale after sleep/monitor changes until syncSpacesState re-queries). Treating unknown
            // as cross-Space ran SLSSpaceSetFrontPSN on the CURRENT Space, re-fronting the previous app and
            // undoing the raise while the window stayed key (#5586, the Slack-after-sleep variant).
            // AltTab knows exactly which window it is focusing — record it so the coming app activation
            // bumps this window directly instead of divining the focus from a racy 808 / AX read (#5596).
            WindowServerEvents.noteAltTabInitiatedFocus(cgWindowId!, application.pid)
            let targetMaybeCrossSpace = !self.spaceIds.isEmpty && !self.spaceIds.contains(originSpaceId)
            let originFrontPid = targetMaybeCrossSpace ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil
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
                //   3. raiseWindow (kAXRaiseAction): raise it within the app's own window stack. If our cached
                //      element went stale (the app silently rebuilt the window's a11y node, #5586), this returns
                //      .invalidUIElement and no-ops, so re-resolve the live element by wid, retry, and heal the
                //      cache; _SLPS/makeKeyWindow above use the wid/psn directly so they're unaffected.
                //   4. cross-Space only: restore the origin Space's front process (see snapshot above).
                if self.activateExactDockItemForUnbundledApplication() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) {
                        WindowThumbnails.previewSelectedIfNeeded()
                    }
                    return
                }
                var psn = ProcessSerialNumber()
                GetProcessForPID(self.application.pid, &psn)
                _SLPSSetFrontProcessWithOptions(&psn, self.cgWindowId!, SLPSMode.userGenerated.rawValue)
                makeKeyWindow(&psn, self.cgWindowId!)
                if self.axUiElement!.raiseWindow() == .invalidUIElement, let fresh = self.refreshedAxElement() {
                    fresh.raiseWindow()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.axUiElement != fresh else { return }
                        self.rebindAxElement(fresh)
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

    /// An executable-hosted GUI has no app bundle for LaunchServices to activate. If Dock exposes an item
    /// whose URL is exactly that executable, pressing it reproduces the user's Dock action without guessing
    /// from a process or window title. Apps the filesystem classifies as applications retain the established
    /// targeted-window focus path; an unreadable classification also stays on that safer path.
    private func activateExactDockItemForUnbundledApplication() -> Bool {
        guard isUnbundledApplication else { return false }
        let identityUrls = Set([application.bundleURL, application.executableURL].compactMap { $0 }.compactMap {
            $0.isFileURL ? $0.standardizedFileURL.resolvingSymlinksInPath() : nil
        })
        guard !identityUrls.isEmpty,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return false }
        let dockElement = AXUIElementCreateApplication(dock.processIdentifier)

        func visit(_ element: AXUIElement, depth: Int) -> Bool {
            guard depth < 5 else { return false }
            guard let attributes = try? element.attributes([
                kAXRoleAttribute, kAXSubroleAttribute, kAXURLAttribute, kAXChildrenAttribute,
            ]) else { return false }
            if attributes.role == kAXDockItemRole {
                let itemUrl = attributes.url?.standardizedFileURL.resolvingSymlinksInPath()
                if attributes.subrole == kAXApplicationDockItemSubrole, let itemUrl, identityUrls.contains(itemUrl) {
                    return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
                }
            }
            return attributes.children?.contains { visit($0, depth: depth + 1) } == true
        }

        return visit(dockElement, depth: 0)
    }

    private var isUnbundledApplication: Bool {
        guard let bundleUrl = application.bundleURL else { return true }
        guard let values = try? bundleUrl.resourceValues(forKeys: [.isApplicationKey]) else { return false }
        return values.isApplication == false
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
        spaceIsBorrowed = borrowed
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

    /// Seed MRU focus order at window creation. WindowServer's focus event (808) keeps it live afterward, but
    /// a window discovered AFTER its app was already frontmost (e.g. cold launch) never saw an 808 for it, so
    /// read kAXFocusedWindow once and, if it points at this window, bump it to the front (#5665).
    ///
    /// The bump is gated on the app being FRONTMOST, the same rule every focus-bump site in the reducer
    /// applies (`windowFocused`, the order-in in-app raise). `kAXFocusedWindow` answers "which window WOULD
    /// take keys if this app were in front", which every app has at all times — so without the gate, any
    /// window discovered while its app sits in the BACKGROUND was fronted over the window the user is
    /// actually on. Not hypothetical: a QQ window was swept from the model during a show and re-discovered a
    /// beat later, and this seed put it at MRU 0 while Chrome was frontmost, so the switcher offered it as
    /// "the window you were on before" (#5785). Read at APPLY time, not at schedule time: the AX call is
    /// queued and was observed landing ~900ms later, by which point the frontmost app can differ.
    private func checkIfFocused() {
        let app = application
        guard let appAxUiElement = app.axUiElement else { return }
        AXCallScheduler.shared.schedule(key: "wid-\(cgWindowId)-focus", context: debugId, pid: app.pid) { [weak app] in
            guard let app, let focusedWindow = try appAxUiElement.attributes([kAXFocusedWindowAttribute], pid: app.pid).focusedWindow else { return }
            let focusedWid = try focusedWindow.cgWindowId()
            DispatchQueue.main.async {
                guard let window = (Windows.list.first { $0.isEqualRobust(focusedWindow, focusedWid) }) else { return }
                // still worth recording WHICH window is the app's focused one: that's a per-app fact, true
                // whether or not the app is in front, and `focusTarget` reads it when the user switches TO
                // this app. Only the MRU bump is gated, by the reducer's `.axFocusedWindowRead`.
                app.focusedWindow = window
                guard let wid = window.cgWindowId else { return }
                TrackedWindowStateBridge.dispatch(.axFocusedWindowRead(wid: wid, viaActivationBackstop: false))
            }
        }
    }
}
