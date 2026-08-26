import Cocoa

class Windows {
    static var list = [Window]()
    private(set) static var byWindowId = [CGWindowID: Window]()
    /// wids that received a focus signal (an 808, a visible-Space join, an in-app raise) while still
    /// untracked, with the time it happened. `.discoveryLanded` consumes it to place the window at the MRU
    /// position that time earns — so a freshly-focused window (one of many from spamming cmd-N, or an app
    /// re-showing a window it had hidden) is neither stranded at the back nor wrongly given a front the user
    /// has since left. Cleared on destroy/removal. See `TrackedWindowState.FocusPromotion`.
    static var windowsPendingFocusPromotion = [CGWindowID: TrackedWindowState.FocusPromotion]()
    /// wids flagged brand-new by a WindowServer `windowCreated` event, not yet promoted in the MRU. A new window
    /// must land at the front, but the focus event (808) that would do it isn't a reliable trigger: it only
    /// fires while the window's app is frontmost, and even then can be *processed* a beat late — after the user
    /// moved on (cmd-N burst, then open AltTab) — where the `isActive` guard in `bumpFocusOrder` drops it and
    /// strands the window at the back. So `appendWindow` promotes any window in this set the moment it's tracked,
    /// independent of discovery path (event or full rescan) and of focus events; `bumpFocusOrder` also honors it
    /// for the create-after-append ordering. Consumed on the first promotion; cleared on destroy/removal.
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
        // Tab grouping (incl. fullscreen siblings) and active→inactive state mirroring are reconciled
        // reactively on WindowServer events (TabGroup.reconcile), so the model is already grouped here —
        // doing it in this synchronous show path would reorder tiles mid-render (UI jump).
        for window in list {
            refreshIfWindowShouldBeShownToTheUser(window, filters)
        }
        refreshWhichWindowsToShowTheUser()
        sort()
        return true
    }

    static func refreshWhichWindowsToShowTheUser() {
        if Preferences.onlyShowMainWindows() {
            // Group windows by application and select the optimal main window
            let windowsGroupedByApp = Dictionary(grouping: list) { $0.application.pid }
            windowsGroupedByApp.forEach { (app, windows) in
                if windows.count > 1, let mainWindow = findMainWindow(windows) {
                    windows.forEach { window in
                        if window.cgWindowId != mainWindow.cgWindowId {
                            window.shouldShowTheUser = false
                        }
                    }
                }
            }
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window, _ f: WindowFilters) {
        // `isOnPreferredScreen` is the one irreducibly OS-coupled fact (touches `Spaces.screenSpacesMap` +
        // multi-screen quartz math); passed as `@autoclosure` so it's only evaluated if the cheaper
        // filters above don't already exclude the window.
        window.shouldShowTheUser = WindowFilterResolver.shouldShow(
            window.state, window.application.state,
            onlyFrontmostApp: f.appsToShow == .active,
            excludeFrontmostApp: f.appsToShow == .nonActive,
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
            isOnPreferredScreen: window.isOnScreen(NSScreen.preferred))
    }

    /// Selects the most appropriate main window from a given list of windows.
    ///
    /// The selection criteria are as follows:
    /// 1. Prefer the focused window if it exists.
    /// 2. Prefer the main window of the application if the focused window is not found.
    ///
    /// - Parameter windows: An array of `Window` objects to select from.
    /// - Returns: The most appropriate `Window` object based on the selection criteria, or `nil` if the array is empty.
    static func findMainWindow(_ windows: [Window]) -> Window? {
        let sortedWindows = windows.sorted { (window1, window2) -> Bool in
            // Prefer the focus window
            if window1.application.focusedWindow?.cgWindowId == window1.cgWindowId {
                return true
            } else if window2.application.focusedWindow?.cgWindowId == window2.cgWindowId {
                return false
            }
            // Prefer the main window (cached AXMain flag — refreshed off-main with the window's other
            // attributes; avoids AX IPC in this comparator on the show path, see #5721 audit)
            if window1.isMainWindow && !window2.isMainWindow {
                return true
            } else if !window1.isMainWindow && window2.isMainWindow {
                return false
            }
            return true
        }
        return sortedWindows.first { $0.shouldShowTheUser }
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

    /// Is the window the user is on among the drawn tiles? Asked of the APP, not of the window: if any tile
    /// belongs to the frontmost app then the window they are looking at is either that tile or one the
    /// filters kept out for a reason of its own, and either way the front of the list is not the window they
    /// want to land on. Only when no tile at all belongs to the frontmost app is it certain the current
    /// window is missing from the list — which is exactly what `Non-active apps` does on purpose (#5941).
    ///
    /// Asking the app rather than `application.focusedWindow` is deliberate: that AX read can be stale or
    /// nil, and answering `false` while the user's window IS drawn would make the default select the window
    /// they are already on. The app-level question cannot fail that way.
    ///
    /// No frontmost app (nothing active, or AltTab launched into an empty front) means nothing is being
    /// filtered against it either, so the ordinary rule applies.
    private static func currentWindowIsDrawn() -> Bool {
        guard let frontmostPid = Applications.frontmostPid else { return true }
        return list.contains { $0.application.pid == frontmostPid && shouldDisplay($0) }
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

    private static func applySelectionDecision(_ decision: SelectionDecision, session: SwitcherSession) {
        switch decision {
        case .clearTargetAndHover:
            session.selectedTarget = nil
            session.hoveredIndex = nil
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
            TilesView.highlight(oldHovered)
        }
    }

    static func updateSelectedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        guard let session = SwitcherSession.current else { return }
        guard newIndex >= 0 && newIndex < list.count else { return }
        guard shouldDisplay(list[newIndex]) else { return }
        var index: Int?
        if fromMouse { session.userPickedSelection = true }
        if fromMouse && (newIndex != session.hoveredIndex || lastWindowActivityType == .focus) {
            let oldIndex = session.hoveredIndex
            session.hoveredIndex = newIndex
            if let oldIndex {
                TilesView.highlight(oldIndex)
            }
            index = session.hoveredIndex
            lastWindowActivityType = .hover
        }
        if !fromMouse {
            TilesView.thumbnailOverView.resetHoveredWindow()
        }
        if (!fromMouse || Preferences.mouseHoverEnabled)
               && (newIndex != session.selectedIndex || lastWindowActivityType == .hover) {
            let oldIndex = session.selectedIndex
            session.selectedIndex = newIndex
            session.selectedTarget = list[newIndex].id
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
        session.userPickedSelection = true  // from here the selection is the USER's pick, not the default
        let nextIndex = selectedWindowIndexAfterCycling(step)
        let isWrapping = (step > 0 && nextIndex < session.selectedIndex) || (step < 0 && nextIndex > session.selectedIndex)
        if CycleWrapResolver.blocksWrap(CycleAdvance(isWrapping: isWrapping, allowWrap: allowWrap,
               lastEventIsARepeat: ATShortcut.lastEventIsARepeat,
               isArtificialRepeatTick: KeyRepeatTimer.isFiringArtificialRepeat))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[session.selectedIndex].rowIndex) {
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
    /// launch and not only on the first summon: called there alone, its answer lands after that summon's
    /// first render and the user watches the list re-order. Seeded at launch, the first summon's call finds
    /// nothing to change and the reducer emits no re-render at all; it still runs there, for whatever the
    /// launch pass could not see yet.
    static func sortByLevel() {
        CGSCallScheduler.windowsInSpaces(Spaces.visibleSpaces) { wids in   // `thenMain`: already on main
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

    static func findOrCreate(_ windowAxUiElement: AXUIElement, _ wid: CGWindowID, _ app: Application, _ level: CGWindowLevel, _ title: String?, _ subrole: String?, _ role: String?, _ size: CGSize?, _ position: CGPoint?, _ isFullscreen: Bool?, _ isMinimized: Bool?) -> (Window?, Bool) {
        if let window = byWindowId[wid] ?? (list.first { $0.isEqualRobust(windowAxUiElement, wid) }) {
            // Adopt the freshest element for this wid. Some apps (e.g. Zoom meeting windows) silently rebuild a
            // window's accessibility element while keeping the same CGWindowID, with no destroyed notification,
            // so our cached ref goes stale and every AX call returns kAXErrorInvalidUIElement. Rebinding here
            // heals it on the sync points that already hand us a fresh element: every show (discovery
            // re-acquires the element), app activation (kAXFocusedWindowAttribute), and focus notifications (#5586).
            if window.axUiElement != windowAxUiElement {
                window.rebindAxElement(windowAxUiElement)
            }
            // on any window event, we take the opportunity to refresh all window attributes
            window.updateFromAxAttributes(title, size, position, isFullscreen, isMinimized)
            return (window, false)
        }
        guard WindowDiscriminator.isActualWindow(app, wid, level, title, subrole, role, size) else { return (nil, false) }
        let window = Window(windowAxUiElement, app, wid, title, isFullscreen, isMinimized, position, size)
        appendWindow(window)
        return (window, true)
    }

    static func appendWindow(_ window: Window) {
        window.lastFocusOrder = list.count
        list.append(window)
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
            if let wid = w.cgWindowId {
                AXCallScheduler.shared.removeEntries(withPrefix: "wid-\(wid)-")
                Applications.windowAttributesThrottler.removeEntries(withPrefix: "\(wid)-")
                Applications.screenshotThrottler.removeEntry(withKey: "capture-wid-\(wid)")
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
