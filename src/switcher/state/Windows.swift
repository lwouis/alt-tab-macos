import Cocoa

class Windows {
    static var list = [Window]()
    private(set) static var byWindowId = [CGWindowID: Window]()
    /// wids that received physical promotion evidence (a visible-Space join or an order-in in the front app)
    /// while still untracked, with the time it happened. `.discoveryLanded` consumes it as structural repair,
    /// so a rediscovered tab or re-shown window is neither stranded at the back nor wrongly given a front the
    /// user has since left. Cleared on destroy/removal. See `TrackedWindowState.FocusPromotion`.
    static var windowsPendingFocusPromotion = [CGWindowID: TrackedWindowState.FocusPromotion]()
    /// **Wids the WindowServer said were newly created, rather than existing surfaces shown again.** A create
    /// event (811) is the only thing that tells the two apart, and the difference decides whether an arrival
    /// may take the front: a wid that joins the visible Space with no create is a tab switch minting nothing,
    /// so the user went there, while a wid that was born joins that same Space just by existing. Reading the
    /// join as attention fronted every
    /// new window whatever the user was doing (twenty background windows at once; a launch finishing
    /// after the user had moved on), so `discoveryLanded` keeps the promotion for a created wid only when it
    /// took another window's place. A window that really did take keys is fronted by its app's own answer, not
    /// from here. Also gates tab-grouping's `activeIsNewlyDiscovered`. Cleared on focus, destroy and removal.
    static var recentlyCreatedWindows = Set<CGWindowID>()
    /// wids that got a `windowRemovedFromSpace` (1326) while still UNtracked — the delta was dropped because
    /// there was no `Window` to apply it to. During a rapid tab burst a new tab backgrounds (loses its Space)
    /// before its async discovery lands, so discovery would otherwise keep the wrong current-Space default and
    /// the background tab would show as a separate window until the next show (#5830). `addDiscoveredWindow`
    /// consumes this to record the tab Space-less at discovery. Cleared if the wid is re-added to a Space, or
    /// on destroy/removal.
    static var windowsPendingSpaceRemoval = [CGWindowID: UInt64]()
    /// wids of tabs that just backgrounded (Space-less) as a new tab took over, kept visible through the
    /// ~250ms until the new tab is discovered and groups them — so the group never drops to zero tiles (the
    /// "window vanishes → app icon → window" gap). The derived `Window.isPhantom` reports a held wid
    /// non-phantom; `WindowServerEvents` inserts on the backgrounding 1326 (only right after a create) and
    /// clears on a timeout, on removal, or once the wid becomes a real background tab (`isTabbed`, hidden anyway).
    static var windowsHeldVisibleForTab = Set<CGWindowID>()
    private struct SurfaceRetirement {
        let oldWid: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        let expiresAt: TimeInterval
        let focusedAt: TimeInterval
        let creationOrder: Int
        let thumbnail: CALayerContents?
        let groupMembers: [CGWindowID]
        let groupRepresentative: CGWindowID?
        let wasFocusedWindow: Bool
    }
    private static var surfaceRetirements = [SurfaceRetirement]()
    private static var lastWindowActivityType = WindowActivityType.none
    private static var shouldSelectBestMatchOnSearchChange = false
    private static var shouldRestoreDefaultSelectionOnSearchClear = false

    static func shouldDisplay(_ window: Window) -> Bool {
        window.shouldShowTheUser && Search.matches(window, query: (SwitcherSession.current?.searchQuery ?? ""))
    }

    static func updateSearchQuery(_ query: String) {
        let previousTrimmedQuery = Search.normalizedQuery(SwitcherSession.current?.searchQuery ?? "")
        let newTrimmedQuery = Search.normalizedQuery(query)
        SwitcherSession.current?.searchQuery = query
        guard let session = SwitcherSession.current else {
            shouldSelectBestMatchOnSearchChange = false
            shouldRestoreDefaultSelectionOnSearchClear = false
            sort()
            return
        }
        if previousTrimmedQuery != newTrimmedQuery {
            if newTrimmedQuery.isEmpty {
                shouldRestoreDefaultSelectionOnSearchClear = !previousTrimmedQuery.isEmpty
                shouldSelectBestMatchOnSearchChange = false
            } else {
                shouldSelectBestMatchOnSearchChange = true
                shouldRestoreDefaultSelectionOnSearchClear = false
                session.hoveredIndex = nil
            }
        }
        sort()
    }

    static func voiceOverWindow(_ windowIndex: Int = (SwitcherSession.current?.selectedIndex ?? 0)) {
        guard SwitcherSession.isActive && TilesPanel.shared.isKeyWindow else { return }
        if TilesView.isSearchEditing { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            if TilesView.isSearchEditing { return }
            let window = TilesView.recycledViews[windowIndex]
            if window.window_ != nil && window.window != nil {
                TilesPanel.shared.makeFirstResponder(window)
            }
        }
    }

    static func updatesBeforeShowing() -> Bool {
        if MissionControl.state() == .showAllWindows || MissionControl.state() == .showFrontWindows { return false }
        if list.isEmpty { return true }
        // Space/screen membership is refreshed OFF the hot path now (#5721): reactively on Space change
        // (WindowServerEvents) and screen change (ScreensEvents), and after show in
        // `Applications.syncSpacesState`. Here we
        // only read the cached values, so there is no blocking SkyLight IPC on the way to rendering. A
        // one-frame staleness (e.g. a window just dragged to another Space) self-corrects via the deferred
        // reconcile. `isPhantom` is DERIVED at read (pure, no IPC — cached `spaceIds` + the CGS latch), so
        // there is nothing to recompute here.
        // ...with ONE exception: a summon can land inside a Space transition, before the leading-edge
        // re-read (`WindowEventReducer.spaceTransitionStarted`) ran, or in the gap where it ran but CGS was
        // still answering with the Space we are leaving. Filtering and sorting against that Space is the
        // whole of #5864, and the topology is one CGS round-trip — 0.1ms p50, measured, against a ~110ms
        // show — so re-read it rather than render a frame we know may be wrong. Only the topology: the
        // per-window membership fan-out is the expensive part #5721 moved off this path and it stays off.
        if WindowServerEvents.inSpaceTransition {
            Spaces.refresh()
        }
        // Per-shortcut prefs and `exceptions` don't change for the duration of one show, but each
        // computed-property access rebuilds the underlying array via N×`CachedUserDefaults.macroPref`
        // calls. Snapshot them once and pass into the per-window helper.
        let filters = WindowFilters.snapshot()
        // Read the cursor once per show: the switcher lists what was under it when summoned, not where it moves to.
        let cursor = filters.appsToShow == .underCursor ? NSScreen.mouseLocationInQuartzCoordinates() : nil
        // Tab grouping (incl. fullscreen siblings) and active→inactive state mirroring are reconciled
        // reactively on WindowServer events (TabGroup.reconcile), so the model is already grouped here —
        // doing it in this synchronous show path would reorder tiles mid-render (UI jump).
        for window in list {
            refreshIfWindowShouldBeShownToTheUser(window, filters, cursor)
        }
        refreshWhichWindowsToShowTheUser()
        sort()
        return true
    }

    static func refreshWhichWindowsToShowTheUser() {
        guard Preferences.showsOneWindowPerApp() else { return }
        let current = AttentionEngine.currentUserContext
        for (pid, windows) in Dictionary(grouping: list, by: { $0.application.pid }) {
            let eligible = windows.filter { $0.shouldShowTheUser }
            let currentWid = current.pid == pid ? current.wid : nil
            let lastAttendedWid = AttentionEngine.lastAttendedWindow(pid)
            let candidates = eligible.map {
                ApplicationRepresentativeCandidate(id: $0.id,
                    isCurrentAttention: $0.cgWindowId == currentWid,
                    isLastAttention: $0.cgWindowId == lastAttendedWid,
                    isMainWindow: $0.isMainWindow, lastFocusOrder: $0.lastFocusOrder,
                    creationOrder: $0.creationOrder)
            }
            let stableId = SwitcherSession.current?.representativeByPid[pid]
            guard let representativeId = ApplicationRepresentativeResolver.pick(candidates, stableId: stableId) else { continue }
            if stableId == nil || !candidates.contains(where: { $0.id == stableId })
                || candidates.first(where: { $0.id == representativeId })?.isCurrentAttention == true {
                SwitcherSession.current?.representativeByPid[pid] = representativeId
            }
            windows.filter { $0.id != representativeId }.forEach { $0.shouldShowTheUser = false }
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ f: WindowFilters, _ cursor: CGPoint?) {
        // `isOnPreferredScreen` is the one irreducibly OS-coupled fact (touches `Spaces.screenSpacesMap` +
        // multi-screen quartz math); passed as `@autoclosure` so it's only evaluated if the cheaper
        // filters above don't already exclude the window.
        window.shouldShowTheUser = WindowFilterResolver.shouldShow(
            window.state, window.application.state,
            onlyFrontmostApp: f.appsToShow == .active,
            excludeFrontmostApp: f.appsToShow == .nonActive,
            onlyUnderCursor: f.appsToShow == .underCursor,
            hideHidden: f.showHiddenWindows == .hide,
            hideWindowless: f.showWindowlessApps == .hide,
            hideFullscreen: f.showFullscreenWindows == .hide,
            hideMinimized: f.showMinimizedWindows == .hide,
            onlyVisibleSpaces: f.spacesToShow == .visible,
            onlyNonVisibleSpaces: f.spacesToShow == .nonVisible,
            onlyPreferredScreen: f.screensToShow == .showingAltTab,
            separateTabs: f.groupTabs == .separateWindows,
            frontmostPid: Applications.frontmostPid,
            visibleSpaceIds: Spaces.visibleSpaces,
            exceptions: f.exceptions,
            isOnPreferredScreen: window.isOnScreen(NSScreen.preferred),
            isUnderCursor: cursor.map { window.contains($0) } ?? false)
    }

    /// selection + hover methods (all operate on `SwitcherSession.current`)
    //////////////////////////////

    /// One-line dump of the switcher's tiles in list order + the selected index — the single most
    /// useful signal for the tab-detection race (a stray 2nd tile, a tile that appears/vanishes across two
    /// dumps, a selected index on the wrong tile). Debug level. `*` marks the selected tile;
    /// `+` shown / `-` hidden; per tile: app, wid, `t`abbed / `p`hantom / `h`eld / `w`indowless-placeholder /
    /// `F`ocused flags, size, and spaceIds.
    /// Size is logged because tab grouping keys on it — without it a capture can't be replayed into the
    /// `RealWorldScenariosTests` corpus without inventing frames.
    ///
    /// `w` and `F` earn their place from #5849, where both had to be DEDUCED from a capture. A windowless
    /// placeholder was only recognizable by its missing wid, so an app showing a real tile AND a placeholder
    /// (the "Slack appears twice" bug) read as two ordinary windows. And the bug itself was a window flagged
    /// phantom while the user was looking at it — a contradiction invisible here until `F` and `p` could be
    /// read on the same line.
    static func logTileDump(_ context: String) {
        guard Logger.debugEnabled else { return }
        let selected = SwitcherSession.current?.selectedIndex ?? -1
        let frontmostPid = Applications.frontmostPid
        let tiles = list.enumerated().map { (i, w) -> String in
            let held = w.cgWindowId.map { windowsHeldVisibleForTab.contains($0) } ?? false
            let focused = w.application.pid == frontmostPid && w.application.focusedWindow === w
            let flags = "\(w.isTabbed ? "t" : "")\(w.isPhantom ? "p" : "")\(w.isFullscreen ? "f" : "")\(held ? "h" : "")\(w.isWindowlessApp ? "w" : "")\(focused ? "F" : "")"
            let app = w.application.runningApplication.localizedName ?? "?"
            let frame = w.size.map { "\(Int($0.width))x\(Int($0.height))@\(Int(w.position?.x ?? 0)),\(Int(w.position?.y ?? 0))" } ?? "-"
            // ax=<hash of the AXUIElement>: is the accessibility element STABLE when Finder mints a new wid
            // for a tab switch? In AX terms a tabbed window is ONE AXWindow containing an AXTabGroup, while
            // AltTab's "one tab, one window" model comes from CGS wids — so the element may well outlive the
            // wid. If it does, it is a real identity to re-link a minted tab to its group, which geometry
            // cannot do once every window in the cluster is screen-sized. Diagnostic only.
            let ax = w.axUiElement.map { String(CFHash($0) % 100000) } ?? "-"
            return "\(i == selected ? "*" : "")\(shouldDisplay(w) ? "+" : "-")\(i):\(app)#\(w.cgWindowId ?? 0)ax\(ax)\(flags.isEmpty ? "" : "(\(flags))")\(frame)sp\(w.spaceIds)"
        }
        // `space=` is the Space the tiles below were filtered and sorted AGAINST, at the instant of this
        // render. Without it a capture cannot tell a wrong list from a right list judged against the Space
        // the user had just left, which is the whole of #5864 and what the QA Space tests assert on.
        Logger.debug { "show[\(context)] sel=\(selected) space=\(Spaces.currentSpaceId) "
            + "tiles=\(tiles.joined(separator: " "))" }
    }

    static func selectedWindow() -> Window? {
        guard let session = SwitcherSession.current, list.count > session.selectedIndex else { return nil }
        let window = list[session.selectedIndex]
        return shouldDisplay(window) ? window : nil
    }

    static func setInitialSelectedAndHoveredWindowIndex() {
        guard let session = SwitcherSession.current else { return }
        let inputs = selectionInputs(session)
        let pickIndex = SelectionResolver.initialPickIndex(inputs)
        Logger.debug { "select initialPick=\(pickIndex.map(String.init) ?? "nil") useLastFocusedRule=\(inputs.useLastFocusedRule) visible=\(inputs.list.indices.filter { inputs.list[$0].visible }) newcomers=\(inputs.list.indices.filter { inputs.list[$0].appearedAfterSummon }) visibleAtSummon=\(inputs.visibleCountAtSummon)" }
        resetForInitialPick(session)
        if let idx = pickIndex {
            updateSelectedAndHoveredWindowIndex(idx)
        }
    }

    static func updateSelectedWindow() {
        guard let session = SwitcherSession.current else { return }
        let inputs = selectionInputs(session)
        let decision = SelectionResolver.decide(inputs)
        Logger.debug { "select decide=\(decision) fromTarget=\(session.selectedTarget ?? "nil") sel=\(session.selectedIndex)" }
        shouldRestoreDefaultSelectionOnSearchClear = false
        shouldSelectBestMatchOnSearchChange = false
        applySelectionDecision(decision, session: session)
        reanchorHover(session)
    }

    /// The kernel's view of this refresh, plus the one measurement that has to be taken on the FIRST one:
    /// how long the visible list was at the summon. It is read here rather than at the press because it needs
    /// `updatesBeforeShowing()`'s filtering to have run — and both happen in the same main-thread turn as the
    /// press, so no event can land in between and shift the count.
    private static func selectionInputs(_ session: SwitcherSession) -> SelectionInputs {
        let snapshot = selectionSnapshot()
        let visibleCountAtSummon = session.visibleWindowCountAtSummon ?? snapshot.filter { $0.visible }.count
        session.visibleWindowCountAtSummon = visibleCountAtSummon
        return SelectionInputs(
            list: snapshot,
            selectedIndex: session.selectedIndex,
            selectedTarget: session.selectedTarget,
            useLastFocusedRule: Applications.frontmostPid != nil
                && Preferences.windowOrder[session.shortcutIndex] != .recentlyFocused,
            visibleCountAtSummon: visibleCountAtSummon,
            userPickedSelection: session.userPickedSelection,
            restoreDefaultOnSearchClear: shouldRestoreDefaultSelectionOnSearchClear,
            bestMatchOnSearchChange: shouldSelectBestMatchOnSearchChange,
            currentWindowIsDrawn: currentWindowIsDrawn())
    }

    private static func currentWindowIsDrawn() -> Bool {
        let evidence: CurrentWindowDrawEvidence
        switch AttentionEngine.currentUserContext {
        case .window(let identity):
            if let window = byWindowId[identity.wid], !window.isMinimized && !window.isPhantom
                && !window.isWindowlessApp && !window.isTabbed {
                evidence = .exactWindow(isDrawn: shouldDisplay(window))
            } else {
                evidence = currentWindowDrawEvidence(identity.process.pid)
            }
        case .application(let process):
            evidence = currentWindowDrawEvidence(process.pid)
        case .unknown:
            evidence = .unknown
        }
        return SelectionResolver.currentWindowIsDrawn(evidence)
    }

    private static func currentWindowDrawEvidence(_ pid: pid_t) -> CurrentWindowDrawEvidence {
        .application(list.compactMap {
            $0.application.pid == pid
                ? FrontmostAppWindow(visible: shouldDisplay($0), isWindowlessApp: $0.isWindowlessApp,
                    isPhantom: $0.isPhantom, isMinimized: $0.isMinimized)
                : nil
        })
    }

    /// Project `list` into the kernel's window view (just the fields selection needs).
    private static func selectionSnapshot() -> [SelectionWindow] {
        // No session (a CLI read) means nothing is a newcomer, hence the `?? true` fallback below.
        let presentAtSummon = SwitcherSession.current?.windowIdsAtSummon
        return list.map {
            SelectionWindow(id: $0.id,
                            visible: shouldDisplay($0),
                            lastFocusOrder: $0.lastFocusOrder,
                            isMinimized: $0.isMinimized,
                            isWindowlessApp: $0.isWindowlessApp,
                            appearedAfterSummon: !(presentAtSummon?.contains($0.id) ?? true))
        }
    }

    /// Re-derive the hover highlight from the window it meant, after every refresh that may have reordered
    /// the list. Repaints both the tile that is losing it and the one taking it, so no stale highlight is left
    /// drawn on a tile that is no longer hovered.
    private static func reanchorHover(_ session: SwitcherSession) {
        guard let target = session.hoveredTarget else { return }
        let previous = session.hoveredIndex
        let current = SelectionResolver.reanchorHover(target: target, in: list.map { $0.id })
        guard current != previous else { return }
        session.hoveredIndex = current
        if current == nil { session.hoveredTarget = nil }
        [previous, current].compactMap { $0 }.forEach { TilesView.highlight($0) }
    }

    private static func applySelectionDecision(_ decision: SelectionDecision, session: SwitcherSession) {
        switch decision {
        case .clearTargetAndHover:
            session.selectedTarget = nil
            session.hoveredIndex = nil
            session.hoveredTarget = nil
        case .resetThenSelect(let idx):
            resetForInitialPick(session)
            updateSelectedAndHoveredWindowIndex(idx)
        case .resetWithoutSelection:
            resetForInitialPick(session)
        case .selectAt(let idx):
            updateSelectedAndHoveredWindowIndex(idx)
        case .ensureTargetSet(let idx):
            if session.selectedTarget == nil && idx < list.count {
                session.selectedTarget = list[idx].id
            }
        }
    }

    /// Wrapper-side reset that mirrors the first half of the old `setInitialSelectedAndHoveredWindowIndex`:
    /// clear `selectedTarget`, reset `selectedIndex` to 0, redraw the old highlight, drop hover.
    private static func resetForInitialPick(_ session: SwitcherSession) {
        let oldIndex = session.selectedIndex
        session.selectedIndex = 0
        session.selectedTarget = nil
        session.userPickedSelection = false
        TilesView.highlight(oldIndex)
        if let oldHovered = session.hoveredIndex {
            session.hoveredIndex = nil
            session.hoveredTarget = nil
            TilesView.highlight(oldHovered)
        }
    }

    static func updateSelectedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        guard let session = SwitcherSession.current else { return }
        guard newIndex >= 0 && newIndex < list.count else { return }
        let newWindow = list[newIndex]
        guard shouldDisplay(newWindow) else { return }
        var index: Int?
        if fromMouse { session.userPickedSelection = true }
        if fromMouse && (newIndex != session.hoveredIndex || lastWindowActivityType == .focus) {
            let oldIndex = session.hoveredIndex
            session.hoveredIndex = newIndex
            session.hoveredTarget = list[newIndex].id
            if let oldIndex {
                TilesView.highlight(oldIndex)
            }
            index = session.hoveredIndex
            lastWindowActivityType = .hover
        }
        if !fromMouse {
            TilesView.thumbnailOverView.resetHoveredWindow()
        }
        // Search can replace the best match at the same index. Its identity must still move so the
        // Preview fetches the new filtered neighborhood instead of treating the previous match as selected.
        if (!fromMouse || Preferences.mouseHoverEnabled)
               && (newIndex != session.selectedIndex || session.selectedTarget != newWindow.id || lastWindowActivityType == .hover) {
            let oldIndex = session.selectedIndex
            session.selectedIndex = newIndex
            session.selectedTarget = newWindow.id
            TilesView.highlight(oldIndex)
            WindowThumbnails.previewSelectedIfNeeded()
            WindowThumbnails.fetchPreviewFrames()
            index = session.selectedIndex
            lastWindowActivityType = .focus
        }
        guard let index else { return }
        TilesView.highlight(index)
        // keyboard/programmatic selection scrolls the target into view; mouse hover must NOT, or hovering a
        // partially-clipped edge tile yanks the whole list — the accidental "edge scroll". Mouse users scroll
        // with the wheel/trackpad instead.
        if !fromMouse {
            let focusedView = TilesView.recycledViews[index]
            TilesView.scrollView.contentView.scrollToVisible(focusedView.frame)
        }
        voiceOverWindow(index)
    }

    static func cycleSelectedWindowIndex(_ step: Int, allowWrap: Bool = true) {
        guard let session = SwitcherSession.current else { return }
        guard list.contains(where: { shouldDisplay($0) }) else { return }
        // `list` can shrink while the panel is open (a window closed), and the selection fix-up runs behind
        // `switcherUiRefreshThrottler`, so a dispatched trackpad/key-repeat step can land here with
        // `selectedIndex` past the end. Clamp like `SelectionResolver` will, instead of trapping.
        let selectedIndex = min(session.selectedIndex, list.count - 1)
        session.userPickedSelection = true  // from here the selection is the USER's pick, not the default
        let nextIndex = selectedWindowIndexAfterCycling(step)
        // don't wrap-around at the end, if key-repeat
        if (((step > 0 && nextIndex < selectedIndex) || (step < 0 && nextIndex > selectedIndex)) &&
            (!allowWrap || ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[selectedIndex].rowIndex) {
            return
        }
        updateSelectedAndHoveredWindowIndex(nextIndex)
    }

    /// The selected window plus up to `radius` displayed windows on each side in cycling order (wrapping
    /// like Tab does). These are the windows the Preview panel may imminently show, so they are the only
    /// ones worth capturing at full resolution (#5861); quick Tab presses land on a pre-captured neighbor.
    static func selectedNeighborhoodIds(_ radius: Int = 2) -> Set<CGWindowID> {
        guard let session = SwitcherSession.current, session.selectedIndex < list.count else { return [] }
        var ids = Set<CGWindowID>()
        if let wid = list[session.selectedIndex].cgWindowId { ids.insert(wid) }
        for step in [1, -1] {
            var index = session.selectedIndex
            var found = 0
            var iterations = 0
            while found < radius && iterations < list.count {
                index = (index + step + list.count) % list.count
                iterations += 1
                if shouldDisplay(list[index]) {
                    found += 1
                    if let wid = list[index].cgWindowId { ids.insert(wid) }
                }
            }
        }
        return ids
    }

    static func selectedWindowIndexAfterCycling(_ step: Int) -> Int {
        let currentIndex = SwitcherSession.current?.selectedIndex ?? 0
        if list.count == 0 || !list.contains(where: { shouldDisplay($0) }) { return currentIndex }
        var iterations = 0
        var targetIndex = currentIndex
        repeat {
            let next = (targetIndex + step) % list.count
            targetIndex = next < 0 ? list.count + next : next
            iterations += 1
        } while !shouldDisplay(list[targetIndex]) && iterations <= list.count
        return targetIndex
    }

    /// lastFocusOrder methods
    //////////////////////////////

    /// Seeds the MRU from window z-order (top-most first), so the order reflects screen stacking for the
    /// windows AltTab was not running to watch being focused. The result is applied by the reducer's
    /// `.zOrderRead` branch, which writes it into the `focusedAt` tiebreak — a real focus is knowledge,
    /// stacking is a guess, and this used to rewrite EVERY window's rank here instead.
    ///
    /// The query BLOCKS, hence the off-main scheduler (#5721), and that is also why it is fired a beat after
    /// launch and never on the first summon: called there, its answer lands after that summon's first render
    /// and the user watches the list re-order. Every in-flight answer re-checks `startupOrderIsAGuess`, so a
    /// launch query that finishes after the first summon is discarded too.
    /// Coalesces the startup re-seeds. A launch discovers windows in bursts and the stacking query BLOCKS,
    /// so this is one seed at the head of a burst plus one trailing seed when it stops, not one per window.
    private static let startupZOrderThrottler = Throttler(delayInMs: 250)

    /// Whether the order is still only the startup guess. True until the user first summons, after which
    /// their own focus history is the order and stacking has no business touching it.
    private(set) static var startupOrderIsAGuess = true

    /// **The startup guess, re-made as windows turn up.**
    ///
    /// AltTab launches into a desktop it did not watch being built, so it has no focus history and has to
    /// guess; screen stacking is that guess. The guess used to be fired once a second after launch and once
    /// more on the first summon. Measured 2026-08-25 across four QA processes: the startup inventory it is
    /// meant to rank lands ~280ms AFTER that timer, because `manuallyRefreshAllWindows` is asynchronous and
    /// `sortByLevel` was called on the line below it. So the launch guess ranked a model that was still
    /// empty, and the only call that did anything was the first-summon one — which answers after that
    /// summon's first render, so the user watched the list re-order under them, and in one run it
    /// moved the MRU front mid-hold.
    ///
    /// Re-seeding per discovery settles the order while nobody is looking instead of guessing once against
    /// whatever happens to exist at one arbitrary instant. It is the same progressive-correction shape the
    /// rest of the pipeline uses: publish as soon as there is better information, rather than waiting for a
    /// moment that can be defined as complete.
    static func reseedZOrderDuringStartup() {
        guard startupOrderIsAGuess else { return }
        startupZOrderThrottler.throttleOrProceed { sortByLevel() }
    }

    /// The user has summoned: from here the order is theirs, not a guess about a past we did not watch.
    static func endStartupOrderSeeding() {
        startupOrderIsAGuess = false
    }

    static func sortByLevel() {
        CGSCallScheduler.windowsInSpaces(Spaces.visibleSpaces) { wids in   // `thenMain`: already on main
            guard startupOrderIsAGuess else { return }
            TrackedWindowStateBridge.dispatch(.zOrderRead(widsTopFirst: wids))
        }
    }

    /// reordered list based on preferences, keeping the original index
    private static func sort() {
        let trimmedQuery = Search.normalizedQuery((SwitcherSession.current?.searchQuery ?? ""))
        let shortcutIndex = (SwitcherSession.current?.shortcutIndex ?? 0)
        // Hoisted once per sort: locals are captured by the comparator closure so each of the
        // O(n log n) comparisons reads them directly.
        let searchActive = !trimmedQuery.isEmpty
        let windowlessAtEnd = Preferences.showWindowlessApps(shortcutIndex) == .showAtTheEnd
        let hiddenAtEnd = Preferences.showHiddenWindows(shortcutIndex) == .showAtTheEnd
        let minimizedAtEnd = Preferences.showMinimizedWindows(shortcutIndex) == .showAtTheEnd
        let sortType = orderSortType(Preferences.windowOrder(shortcutIndex))
        // Precompute each window's ordering facts once (O(n) Search calls), then sort on the snapshots.
        let facts = Dictionary(uniqueKeysWithValues: list.map { (ObjectIdentifier($0), orderWindow($0, trimmedQuery)) })
        list.sort {
            WindowOrderResolver.isOrderedBefore(
                facts[ObjectIdentifier($0)]!, facts[ObjectIdentifier($1)]!,
                searchActive: searchActive,
                windowlessAtEnd: windowlessAtEnd,
                hiddenAtEnd: hiddenAtEnd,
                minimizedAtEnd: minimizedAtEnd,
                sortType: sortType)
        }
    }

    private static func orderWindow(_ window: Window, _ query: String) -> OrderWindow {
        OrderWindow(
            state: window.state,
            app: window.application.state,
            searchMatches: query.isEmpty ? false : Search.matches(window, query: query),
            searchRelevance: query.isEmpty ? 0 : Search.relevance(for: window, query: query))
    }

    private static func orderSortType(_ p: WindowOrderPreference) -> OrderSortType {
        switch p {
            case .recentlyFocused: return .recentlyFocused
            case .recentlyCreated: return .recentlyCreated
            case .alphabetical: return .alphabetical
            case .space: return .space
        }
    }

    static func findOrCreate(_ windowAxUiElement: AXUIElement, _ raw: WsRawWindow, _ app: Application,
                             _ semantic: SemanticSurface, _ isFullscreen: Bool?,
                             _ isMinimized: Bool?) -> (Window?, Bool) {
        let wid = raw.wid
        let existing = byWindowId[wid] ?? (list.first { $0.isEqualRobust(windowAxUiElement, wid) })
        let evidence = existing?.admissionEvidence ?? .discovery
        let decision = WindowAdmissionResolver.resolve(PhysicalSurface(raw), semantic, evidence: evidence)
        guard decision.isDestination else {
            logAdmission(decision, raw, app)
            if let existing { removeWindows([existing], true) }
            return (nil, false)
        }
        if let window = existing {
            // Adopt the freshest element for this wid. Some apps (e.g. Zoom meeting windows) silently rebuild a
            // window's accessibility element while keeping the same CGWindowID, with no destroyed notification,
            // so our cached ref goes stale and every AX call returns kAXErrorInvalidUIElement. Rebinding here
            // heals it on the sync points that already hand us a fresh element: every show (discovery
            // re-acquires the element), app activation (kAXFocusedWindowAttribute), and focus notifications (#5586).
            if window.axUiElement != windowAxUiElement {
                window.rebindAxElement(windowAxUiElement)
            }
            // AX answered for a window that had been kept on WindowServer evidence alone.
            promoteVerified(wid)
            window.semanticSurface = semantic
            // on any window event, we take the opportunity to refresh all window attributes
            window.updateFromAxAttributes(semantic.title, raw.bounds.size, raw.bounds.origin, isFullscreen, isMinimized)
            logAdmission(decision, raw, app)
            return (window, false)
        }
        let window = Window(windowAxUiElement, app, wid, semantic.title, isFullscreen, isMinimized,
            raw.bounds.origin, raw.bounds.size, .axVerified, evidence)
        window.semanticSurface = semantic
        appendWindow(window)
        restoreSurfaceContinuity(window, element: windowAxUiElement)
        logAdmission(decision, raw, app)
        return (window, true)
    }

    /// Re-run admission when mutable AX facts change. The physical inventory keeps removed/latent surfaces
    /// discoverable, so neither acceptance nor rejection latches for the lifetime of a WID.
    @discardableResult
    static func reevaluateAdmission(_ window: Window, _ semantic: SemanticSurface) -> Bool {
        guard let wid = window.cgWindowId,
              let raw = WindowSurfaceInventory.raw(wid) else { return true }
        let decision = WindowAdmissionResolver.resolve(PhysicalSurface(raw), semantic,
            evidence: window.admissionEvidence)
        window.semanticSurface = semantic
        logAdmission(decision, raw, window.application)
        guard decision.isDestination else {
            removeWindows([window], true)
            return false
        }
        return true
    }

    static func reevaluatePhysicalEvidence(_ raws: [WsRawWindow]) {
        WindowSurfaceInventory.upsert(raws)
        for raw in raws {
            guard let window = byWindowId[raw.wid], let semantic = window.semanticSurface else { continue }
            _ = reevaluateAdmission(window, semantic)
        }
    }

    private static func logAdmission(_ decision: SwitchDestinationDecision, _ raw: WsRawWindow,
                                     _ app: Application) {
        Logger.debug { "surface \(decision.isDestination ? "accepted" : "not admitted") \(app.debugId) wid:\(raw.wid) level:\(raw.level) parent:\(raw.parentWid) reason:\(decision.reason.rawValue)" }
    }

    /// **A window exact attention evidence named before ordinary discovery completed.** The WindowServer row
    /// supplies physical state while AX acquisition catches up.
    ///
    /// **Only for a window a click, AltTab, or an app focus notification named.** Retaining every unresolved WindowServer
    /// row was tried and reverted: a healthy app fails to resolve a wid constantly, because a background
    /// native tab exposes no AX window element at all, and tracking those made them look already-tracked to
    /// the inactive-tab brute force, which then never went looking for them. A tab group came back with one
    /// member instead of two. Gating on "is the app unresponsive" did not save it either: at
    /// cold start apps legitimately answer `cannotComplete` for a moment and get flagged.
    ///
    /// Exact attention is different. It names one wid and its pid, so representing that one row does not let
    /// an unrelated background tab claim itself.
    ///
    /// Parentage is resolved first; the parentless surface is admitted because exact attention itself is the
    /// behavioral evidence. Size cannot veto an interaction the user actually performed; placement does,
    /// because an app key-focuses its own HUD exactly as it focuses a window. See
    /// `WindowAdmissionResolver.admissiblePlacement`.
    @discardableResult
    static func findOrCreateCandidate(_ raw: WsRawWindow, _ app: Application) -> Window? {
        let representativeWid = WindowSurfaceInventory.representativeWid(raw.wid)
        if representativeWid != raw.wid {
            guard let representative = WindowSurfaceInventory.raw(representativeWid), representative.pid == raw.pid else { return nil }
            return findOrCreateCandidate(representative, app)
        }
        if let existing = byWindowId[raw.wid] {
            existing.admissionEvidence = .attention
            return existing
        }
        let decision = WindowAdmissionResolver.resolve(PhysicalSurface(raw), nil, evidence: .attention)
        guard decision.isDestination else {
            logAdmission(decision, raw, app)
            return nil
        }
        let window = Window(nil, app, raw.wid, raw.title.isEmpty ? nil : raw.title,
            WsWindowState.isFullscreen(raw), WsWindowState.isMinimized(raw),
            raw.bounds.origin, raw.bounds.size, .attentionCandidate, .attention)
        appendWindow(window)
        logAdmission(decision, raw, app)
        return window
    }

    /// **Attention buys time for accessibility to catch up. This is where the loan is called in.**
    ///
    /// A window held on attention alone has never once been described, and the sweep has now failed to
    /// acquire it `SurfaceAcquisitionPolicy.maxAttemptsPerSituation` times at one unchanged app window set,
    /// which is the point it stops paying for the surface. Without this, "focus went there" stood for the
    /// life of the wid with nothing able to contradict it — the shape that kept an undescribable HUD in the
    /// list for good.
    ///
    /// **Only an admission with no element is dropped.** A window described even once is not held on
    /// attention, so an app that wedges LATER keeps every window it had, and the app itself stays reachable
    /// because losing its last window restores its icon placeholder. Both are pinned live by the QA suite's
    /// WL-11 and WL-12, and this rule's own three shapes by its WL-19, WL-20 and WL-21.
    ///
    /// Not permanent either. The failure record is keyed to the app's window set, so any window or tab change
    /// asks again, and the app's own focus notification re-admits the surface the moment it can speak.
    static func dropUndescribedAttentionAdmission(_ wid: CGWindowID) {
        guard let window = byWindowId[wid], window.axUiElement == nil,
              window.admissionEvidence == .attention, window.axStatus == .attentionCandidate else { return }
        Logger.debug { "surface not admitted \(window.application.debugId) wid:\(wid) reason:neverDescribed" }
        removeWindows([window], true)
    }

    /// AX finally answered for a window that was kept on WindowServer evidence alone. Nothing about the
    /// window changes except what may be claimed about it.
    static func promoteVerified(_ wid: CGWindowID) {
        guard let window = byWindowId[wid], window.axStatus != .axVerified else { return }
        window.axStatus = .axVerified
        window.application.removeWindowlessAppWindow()
    }

    /// Exact attention named this window, so it is shown on that evidence rather than waiting for AX
    /// acquisition. This covers a click, AltTab's own target, and the app's focus notification.
    static func promoteAttentionEvidence(_ wid: CGWindowID) {
        let representativeWid = WindowSurfaceInventory.representativeWid(wid)
        guard let window = byWindowId[representativeWid] else { return }
        window.admissionEvidence = .attention
    }

    /// Bumped whenever an app gains or loses a window. A tab open, close, tear-off or merge all move it, so
    /// it is what `TabReadPolicy` compares against to decide whether a window's tab grouping may be stale —
    /// a monotonic version rather than a window count, because closing one tab and opening another between
    /// two shows leaves the count unchanged.
    private(set) static var appWindowSetVersion = [pid_t: UInt64]()

    static func bumpAppWindowSetVersion(_ pid: pid_t) {
        appWindowSetVersion[pid, default: 0] &+= 1
    }

    static func forgetAppWindowSetVersion(_ pid: pid_t) {
        appWindowSetVersion[pid] = nil
    }

    static func appendWindow(_ window: Window) {
        window.lastFocusOrder = list.count
        list.append(window)
        bumpAppWindowSetVersion(window.application.pid)
        if let wid = window.cgWindowId {
            byWindowId[wid] = window
            WindowServerEvents.subscribe(wid)
            // The freshly-created-window MRU promotion (consuming `windowsPendingFocusPromotion` /
            // `recentlyCreatedWindows`) lives in the reducer's `.discoveryLanded` branch now — every tracked
            // append flows through it.
        }
        if list.count > TilesView.recycledViews.count {
            TilesView.recycledViews.append(TileView())
        }
    }

    /// Capture continuity facts without retaining the old `Window`. A WindowServer destroy can be a shell
    /// replacement while the app keeps one AX window; the record transfers only on explicit AX equality.
    static func retireSurfaceForReplacement(_ wid: CGWindowID) {
        let now = ProcessInfo.processInfo.systemUptime
        surfaceRetirements.removeAll { $0.expiresAt <= now }
        guard let window = byWindowId[wid], let element = window.axUiElement else { return }
        let members = TabGroups.siblingWids(of: wid) ?? [wid]
        let representative = TabGroups.groupId(of: wid).flatMap { TabGroups.representativeByGroup[$0] }
        surfaceRetirements.append(SurfaceRetirement(oldWid: wid, pid: window.application.pid,
            element: element, expiresAt: now + 2, focusedAt: window.focusedAt,
            creationOrder: window.creationOrder, thumbnail: window.thumbnail, groupMembers: members,
            groupRepresentative: representative,
            wasFocusedWindow: window.application.focusedWindow === window))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let now = ProcessInfo.processInfo.systemUptime
            surfaceRetirements.removeAll { $0.expiresAt <= now }
        }
    }

    static func forgetSurfaceRetirements(_ pid: pid_t) {
        surfaceRetirements.removeAll { $0.pid == pid }
    }

    private static func restoreSurfaceContinuity(_ window: Window, element: AXUIElement) {
        let now = ProcessInfo.processInfo.systemUptime
        surfaceRetirements.removeAll { $0.expiresAt <= now }
        guard let i = surfaceRetirements.firstIndex(where: {
            $0.pid == window.application.pid && CFEqual($0.element, element)
        }), let newWid = window.cgWindowId else { return }
        let retirement = surfaceRetirements.remove(at: i)
        window.focusedAt = retirement.focusedAt
        window.creationOrder = retirement.creationOrder
        window.thumbnail = retirement.thumbnail
        let newerFocusExists = list.contains { $0 !== window && $0.focusedAt > retirement.focusedAt }
        let restoreFocus = retirement.wasFocusedWindow && !newerFocusExists
            && window.application.focusedWindow == nil
        if restoreFocus { window.application.focusedWindow = window }
        var state = TrackedWindowStateBridge.snapshot()
        _ = state.recomputeFocusRanks(preferring: restoreFocus ? newWid : nil)
        let members = retirement.groupMembers.map { $0 == retirement.oldWid ? newWid : $0 }
            .filter { state.window($0) != nil }
        if members.count > 1 {
            let representative = retirement.groupRepresentative == retirement.oldWid
                ? newWid : (retirement.groupRepresentative.flatMap { members.contains($0) ? $0 : nil } ?? newWid)
            let mutation = state.formGroup(members, representative: representative,
                reason: "surfaceReplacement")
            for line in mutation.logs { Logger.debug { line } }
        }
        TrackedWindowStateBridge.apply(state)
        Logger.debug { "surface continuity #\(retirement.oldWid)→#\(newWid) pid=\(retirement.pid)" }
    }

    static func removeWindows(_ windows: [Window], _ addWindowlessWindowIfNeeded: Bool) {
        // Release any pooled TileView pinned to a window we're removing so its thumbnail
        // IOSurface can deallocate now. Otherwise the layer.contents reference keeps the
        // IOSurface alive until the next switcher show — which may be much later, and
        // never if the user has already closed many windows in the background.
        // Match by Window identity (not cgWindowId) so windowless-app tiles aren't hit.
        for view in TilesView.recycledViews {
            if let win = view.window_, windows.contains(where: { $0 === win }) {
                view.thumbnail.releaseImage()
                view.appIcon.releaseImage()
                view.window_ = nil
            }
        }
        // Same for PreviewPanel: if the previewed window is being removed, drop its IOSurface.
        for w in windows {
            if let wid = w.cgWindowId {
                PreviewPanel.clearIfShowing(wid)
            }
        }
        for w in windows {
            if w.application.focusedWindow?.cgWindowId == w.cgWindowId {
                w.application.focusedWindow = nil
            }
            if let wid = w.cgWindowId {
                AxObserverRegistry.noteTrackedElement(pid: w.application.pid, wid: wid, element: nil)
                byWindowId.removeValue(forKey: wid)
                windowsPendingFocusPromotion.removeValue(forKey: wid)
                recentlyCreatedWindows.remove(wid)
                windowsPendingSpaceRemoval.removeValue(forKey: wid)
                windowsHeldVisibleForTab.remove(wid)
                // deliberately no `WindowServerEvents.unsubscribe`: leaving the model doesn't mean the wid is
                // gone from the WindowServer, and a wid that comes back only announces itself through the
                // per-window events that opt-in carries.
            }
        }
        let toRemove = windows.map { $0.lastFocusOrder }
        list.removeAll { w in
            if toRemove.contains(w.lastFocusOrder) {
                return true
            }
            let howManyToShift = toRemove.reduce(0) { $1 < w.lastFocusOrder ? $0 + 1 : $0 }
            w.lastFocusOrder -= howManyToShift
            return false
        }
        // Drop the cached `SCWindow` for any window we're removing. Otherwise the array
        // grows over time as new shareable-content refreshes leave stale entries behind
        // (see leak #5).
        if #available(macOS 14.0, *) {
            let removedWids = Set(windows.compactMap { $0.cgWindowId })
            if !removedWids.isEmpty {
                BackgroundWork.screenshotsQueue.addOperation {
                    WindowCaptureScreenshots.cachedSCWindows.withLock { $0.removeAll { removedWids.contains($0.windowID) } }
                }
            }
        }
        for w in windows {
            bumpAppWindowSetVersion(w.application.pid)
            if let wid = w.cgWindowId {
                AXCallScheduler.shared.removeEntries(withPrefix: "wid-\(wid)-")
                // Both key SHAPES this throttler holds for a window: `<wid>-generic` / `<wid>-title` written
                // by the attribute reads, and `wid-<wid>-discover` / `wid-<wid>-wsstate` written by the
                // bridge. Pruning only the first shape left the second accumulating for the whole session.
                Applications.windowAttributesThrottler.removeEntries(withPrefix: "\(wid)-")
                Applications.windowAttributesThrottler.removeEntries(withPrefix: "wid-\(wid)-")
                // likewise both capture resolutions: the full-res Preview fetch keys on `preview-`
                Applications.screenshotThrottler.removeEntry(withKey: "capture-wid-\(wid)")
                Applications.screenshotThrottler.removeEntry(withKey: "preview-wid-\(wid)")
                Applications.forgetTabRead(wid)
                Applications.forgetAcquisitionFailure(wid)
            }
            // when a tabbed window is removed, its group shrinks (or dissolves) in the registry
            if let wid = w.cgWindowId {
                TabGroups.remove(wid, reason: "windowRemoved")
            }
        }
        if addWindowlessWindowIfNeeded {
            windows.forEach { $0.application.addWindowlessWindowIfNeeded() }
        }
        App.refreshOpenUiAfterExternalEvent([], windowRemoved: true)
    }
}

enum WindowActivityType: Int {
    case none = 0
    case hover = 1
    case focus = 2
}

/// Snapshot of per-shortcut preferences used by `refreshIfWindowShouldBeShownToTheUser`. The
/// `Preferences.<arrayPref>` getters each rebuild a `[MacroPreference]` array via N×`macroPref`
/// calls — cheap once, dominant when read inside a per-window loop. Snapshotting once at the
/// start of `updatesBeforeShowing` collapses N_windows × M_prefs accesses into M_prefs.
struct WindowFilters {
    let exceptions: [ExceptionEntry]
    let appsToShow: AppsToShowPreference
    let showHiddenWindows: ShowHowPreference
    let showWindowlessApps: ShowHowPreference
    let showFullscreenWindows: ShowHowPreference
    let showMinimizedWindows: ShowHowPreference
    let spacesToShow: SpacesToShowPreference
    let screensToShow: ScreensToShowPreference
    let groupTabs: GroupTabsPreference

    static func snapshot() -> WindowFilters {
        let i = SwitcherSession.current?.shortcutIndex ?? 0
        return WindowFilters(
            exceptions: Preferences.exceptions,
            appsToShow: Preferences.appsToShow[i],
            showHiddenWindows: Preferences.showHiddenWindows[i],
            showWindowlessApps: Preferences.showWindowlessApps[i],
            showFullscreenWindows: Preferences.showFullscreenWindows[i],
            showMinimizedWindows: Preferences.showMinimizedWindows[i],
            spacesToShow: Preferences.spacesToShow[i],
            screensToShow: Preferences.screensToShow[i],
            groupTabs: Preferences.groupTabs(i))
    }
}
