import Cocoa

// Windows manages the list of windows, search (filtering), and selection (focus).
// Terminology:
// - Search: editing the search bar text; it filters visibility but does not itself define selection.
// - Selection: the focused window (keyboard arrows/programmatic focus).
// - Selection highlight: the visual style applied to the selected (focused) window.
// - Hover: cursor hover; does not affect selection or selection highlight.
class Windows {
    static var list = [Window]()
    // Selection (focus): index of the keyboard-focused window
    static var focusedWindowIndex = Int(0)
    // Hover state: last index under the cursor (does not affect selection highlight)
    static var hoveredWindowIndex: Int?
    // Tracks last activity (hover/focus) to limit side-effects (e.g. scroll only on focus changes)
    static var lastWindowActivityType = WindowActivityType.none
    static var searchQuery: String = ""
    // When true, the next UI refresh will force selection to the first visible window
    // When true, the next refresh will focus the first visible window (set on search bar changes)
    static var forceFocusFirstVisibleOnSearchChange: Bool = false

    static func matchesSearch(_ window: Window) -> Bool {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        ensureSearchCache(for: window, query: trimmed)
        return !window.swAppResults.isEmpty || !window.swTitleResults.isEmpty
    }

    static func shouldDisplay(_ window: Window) -> Bool {
        return window.shouldShowTheUser && matchesSearch(window)
    }


    /// Updates windows "lastFocusOrder" to ensure unique values based on window z-order.
    /// Windows are ordered by their position in Spaces.windowsInSpaces() results,
    /// with topmost windows first.
    static func sortByLevel() {
        var windowLevelMap = [CGWindowID?: Int]()
        for (index, cgWindowId) in Spaces.windowsInSpaces(Spaces.visibleSpaces).enumerated() {
            windowLevelMap[cgWindowId] = index
        }
        list = list
            .sorted { w1, w2 in
                (windowLevelMap[w1.cgWindowId] ?? .max) < (windowLevelMap[w2.cgWindowId] ?? .max)
            }
            .enumerated()
            .map { (index, window) -> Window in
                window.lastFocusOrder = index
                return window
            }
    }

    /// Computes a relevance score for `window` given the current `searchQuery`.
    /// Higher is better. Prefers contiguous/whole-word matches over scattered
    /// subsequence matches, and boosts app-name matches slightly over title matches.
    private static func searchRelevance(_ window: Window) -> Double {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0.0 }
        // Ensure cache populated and reuse computed result for ranking
        ensureSearchCache(for: window, query: trimmed)
        return window.swBestSimilarity
    }

    /// reordered list based on preferences, keeping the original index
    private static func sort() {
        // Remember the currently selected window instance to preserve selection across reorders
        let previouslySelected = focusedWindow()
        list.sort {
            // separate buckets for these types of windows
            if Preferences.showWindowlessApps[App.app.shortcutIndex] == .showAtTheEnd && $0.isWindowlessApp != $1.isWindowlessApp {
                return $1.isWindowlessApp
            }
            if Preferences.showHiddenWindows[App.app.shortcutIndex] == .showAtTheEnd && $0.isHidden != $1.isHidden {
                return $1.isHidden
            }
            if Preferences.showMinimizedWindows[App.app.shortcutIndex] == .showAtTheEnd && $0.isMinimized != $1.isMinimized {
                return $1.isMinimized
            }
            // While searching, prioritize by Smith–Waterman similarity score
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let s0 = searchRelevance($0)
                let s1 = searchRelevance($1)
                if s0 != s1 { return s0 > s1 }
            }
            // sort within each buckets
            let sortType = Preferences.windowOrder[App.app.shortcutIndex]
            if sortType == .recentlyFocused {
                return $0.lastFocusOrder < $1.lastFocusOrder
            }
            if sortType == .recentlyCreated {
                return $1.creationOrder < $0.creationOrder
            }
            var order = ComparisonResult.orderedSame
            if sortType == .alphabetical {
                order = compareByAppNameThenWindowTitle($0, $1)
            }
            if sortType == .space {
                if $0.isOnAllSpaces && $1.isOnAllSpaces {
                    order = .orderedSame
                } else if $0.isOnAllSpaces {
                    order = .orderedAscending
                } else if $1.isOnAllSpaces {
                    order = .orderedDescending
                } else if let spaceIndex0 = $0.spaceIndexes.first, let spaceIndex1 = $1.spaceIndexes.first {
                    order = spaceIndex0.compare(spaceIndex1)
                }
                if order == .orderedSame {
                    order = compareByAppNameThenWindowTitle($0, $1)
                }
            }
            if order == .orderedSame {
                order = $0.lastFocusOrder.compare($1.lastFocusOrder)
            }
            return order == .orderedAscending
        }
        // Preserve selection after reordering (e.g., when search changes order)
        if let previouslySelected,
           let newIndex = list.firstIndex(where: { $0 === previouslySelected }) {
            focusedWindowIndex = newIndex
        }
    }

    static func updateIsFullscreenOnCurrentSpace() {
        let windowsOnCurrentSpace = Windows.list.filter { !$0.isWindowlessApp }
        for window in windowsOnCurrentSpace {
            AXUIElement.retryAxCallUntilTimeout(context: window.debugId(), after: .now() + humanPerceptionDelay, callType: .updateWindow) { [weak window] in
                guard let window else { return }
                try AccessibilityEvents.updateWindowSizeAndPositionAndFullscreen(window.axUiElement!, window.cgWindowId!, window)
            }
        }
    }

    private static func compareByAppNameThenWindowTitle(_ w1: Window, _ w2: Window) -> ComparisonResult {
        let order = w1.application.localizedName.localizedStandardCompare(w2.application.localizedName)
        if order == .orderedSame {
            return w1.title.localizedStandardCompare(w2.title)
        }
        return order
    }

    static func setInitialFocusedAndHoveredWindowIndex() {
        // Reset state and clear previous highlights/hover
        let oldIndex = focusedWindowIndex
        focusedWindowIndex = 0
        ThumbnailsView.highlight(oldIndex)
        if let oldIndex = hoveredWindowIndex {
            hoveredWindowIndex = nil
            ThumbnailsView.highlight(oldIndex)
        }

        // New behavior: when the UI opens, select the first visible window in the current order.
        // This avoids auto-selecting the 2nd window by cycling forward.
        if let firstVisible = Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) {
            updateFocusedAndHoveredWindowIndex(firstVisible)
        } else {
            updateFocusedAndHoveredWindowIndex(0)
        }
    }

    static func getLastFocusedWindowIndex() -> Int? {
        var index: Int? = nil
        var lastFocusOrderMin = Int.max
        Windows.list.enumerated().forEach {
            if !$0.element.isWindowlessApp && $0.element.lastFocusOrder < lastFocusOrderMin {
                lastFocusOrderMin = $0.element.lastFocusOrder
                index = $0.offset
            }
        }
        return index
    }

    static func appendAndUpdateFocus(_ window: Window) {
        list.forEach {
            $0.lastFocusOrder += 1
        }
        list.append(window)
        if list.count > ThumbnailsView.recycledViews.count {
            ThumbnailsView.recycledViews.append(ThumbnailView())
        }
    }

    static func removeWindow(_ index: Int, _ pid: pid_t) {
        let window = Windows.list[index]
        removeAndUpdateFocus(window)
        if window.application.addWindowlessWindowIfNeeded() != nil {
            Applications.find(pid)?.focusedWindow = nil
        }
        if Windows.list.count > 0 {
            moveFocusedWindowIndexAfterWindowDestroyedInBackground(index)
            App.app.refreshOpenUi([], .refreshUiAfterExternalEvent, windowRemoved: true)
        } else {
            App.app.hideUi()
        }
    }

    private static func removeAndUpdateFocus(_ window: Window) {
        let removedWindowOldFocusOrder = window.lastFocusOrder
        list.removeAll {
            if $0.lastFocusOrder == removedWindowOldFocusOrder {
                return true
            }
            if $0.lastFocusOrder > removedWindowOldFocusOrder {
                $0.lastFocusOrder -= 1
            }
            return false
        }
    }

    static func updateLastFocus(_ otherWindowAxUiElement: AXUIElement, _ otherWindowWid: CGWindowID) -> [Window]? {
        if let focusedWindow = (list.first { $0.isEqualRobust(otherWindowAxUiElement, otherWindowWid) }) {
            let focusedWindowOldFocusOrder = focusedWindow.lastFocusOrder
            var windowsToRefresh = [focusedWindow]
            list.forEach {
                if $0.lastFocusOrder == focusedWindowOldFocusOrder {
                    $0.lastFocusOrder = 0
                } else if $0.lastFocusOrder < focusedWindowOldFocusOrder {
                    $0.lastFocusOrder += 1
                }
                if $0.lastFocusOrder == 0 {
                    windowsToRefresh.append($0)
                }
            }
            return windowsToRefresh
        }
        return nil
    }

    static func updateFocusedAndHoveredWindowIndex(_ newIndex: Int, _ fromMouse: Bool = false) {
        var oldFocused: Int? = nil
        var oldHovered: Int? = nil
        // Update hover state (optional feature). Hover never changes selection.
        if fromMouse && Preferences.mouseHoverEnabled && (newIndex != hoveredWindowIndex || lastWindowActivityType == .focus) {
            oldHovered = hoveredWindowIndex
            hoveredWindowIndex = newIndex
            lastWindowActivityType = .hover
        }
        // Update selection (focus) only when not coming from the mouse.
        if !fromMouse && (newIndex != focusedWindowIndex || lastWindowActivityType == .hover) {
            oldFocused = focusedWindowIndex
            if hoveredWindowIndex != nil { oldHovered = hoveredWindowIndex; hoveredWindowIndex = nil }
            focusedWindowIndex = newIndex
            previewFocusedWindowIfNeeded()
            lastWindowActivityType = .focus
        }
        // Repaint changed indices and the current selected (focused) index
        if let of = oldFocused { ThumbnailsView.highlight(of) }
        if let oh = oldHovered { ThumbnailsView.highlight(oh) }
        ThumbnailsView.highlight(hoveredWindowIndex ?? focusedWindowIndex)
        // Only auto-scroll and voice over on focus changes
        if lastWindowActivityType == .focus {
            let index = focusedWindowIndex
            let focusedView = ThumbnailsView.recycledViews[index]
            App.app.thumbnailsPanel.thumbnailsView.scrollView.contentView.scrollToVisible(focusedView.frame)
            voiceOverWindow(index)
        }
    }

    static func previewFocusedWindowIfNeeded() {
        if App.app.appIsBeingUsed && ScreenRecordingPermission.status == .granted
               && Preferences.previewFocusedWindow && !Preferences.onlyShowApplications()
               && App.app.thumbnailsPanel.isKeyWindow,
           let window = focusedWindow(),
           let id = window.cgWindowId,
           let thumbnail = window.thumbnail,
           let position = window.position,
           let size = window.size {
            App.app.previewPanel.show(id, thumbnail, position, size)
        } else {
            App.app.previewPanel.orderOut(nil)
        }
    }

    static func voiceOverWindow(_ windowIndex: Int = focusedWindowIndex) {
        guard App.app.appIsBeingUsed && App.app.thumbnailsPanel.isKeyWindow else { return }
        // Do not steal focus from the search field while user is typing.
        // Check now and again right before focusing the thumbnail to avoid races
        // with code that focuses the search field shortly after a UI refresh.
        if App.app.thumbnailsPanel.thumbnailsView.searchField.currentEditor() != nil { return }
        // it seems that sometimes makeFirstResponder is called before the view is visible
        // and it creates a delay in showing the main window; calling it with some delay seems to work around this
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
            // If the user entered search in the meantime, keep focus there.
            if App.app.thumbnailsPanel.thumbnailsView.searchField.currentEditor() != nil { return }
            let window = ThumbnailsView.recycledViews[windowIndex]
            if window.window_ != nil && window.window != nil {
                App.app.thumbnailsPanel.makeFirstResponder(window)
            }
        }
    }

    static func focusedWindow() -> Window? {
        return list.count > focusedWindowIndex ? list[focusedWindowIndex] : nil
    }

    static func cycleFocusedWindowIndex(_ step: Int, allowWrap: Bool = true) {
        let nextIndex = windowIndexAfterCycling(step)
        // don't wrap-around at the end, if key-repeat
        if (((step > 0 && nextIndex < focusedWindowIndex) || (step < 0 && nextIndex > focusedWindowIndex)) &&
            (!allowWrap || ATShortcut.lastEventIsARepeat || !KeyRepeatTimer.timerIsSuspended))
               // don't cycle to another row, if !allowWrap
               || (!allowWrap && list[nextIndex].rowIndex != list[focusedWindowIndex].rowIndex) {
            return
        }
        updateFocusedAndHoveredWindowIndex(nextIndex)
    }

    static func windowIndexAfterCycling(_ step: Int) -> Int {
        if list.count == 0 { return 0 }
        var iterations = 0
        var targetIndex = focusedWindowIndex
        repeat {
            let next = (targetIndex + step) % list.count
            targetIndex = next < 0 ? list.count + next : next
            iterations += 1
        } while !shouldDisplay(list[targetIndex]) && iterations <= list.count
        return targetIndex
    }

    private static func moveFocusedWindowIndexAfterWindowDestroyedInBackground(_ index: Int) {
        if index < focusedWindowIndex {
            cycleFocusedWindowIndex(-1)
        }
    }

    static func updateFocusedWindowIndex() {
        // If a search keystroke updated the query, force selection to the first visible result
        if forceFocusFirstVisibleOnSearchChange {
            if let firstVisible = Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) {
                updateFocusedAndHoveredWindowIndex(firstVisible)
            }
            forceFocusFirstVisibleOnSearchChange = false
            return
        }
        if let focusedWindow = focusedWindow() {
            if !shouldDisplay(focusedWindow) {
                // Keep selection stable while filtering. If the current selection
                // is no longer visible, select the first visible window instead
                // of moving to an adjacent one.
                if let firstVisible = Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) {
                    updateFocusedAndHoveredWindowIndex(firstVisible)
                }
            } else {
                previewFocusedWindowIfNeeded()
            }
        } else {
            // Fallback: if no window is currently focused, try selecting the first visible
            if let firstVisible = Windows.list.firstIndex(where: { Windows.shouldDisplay($0) }) {
                updateFocusedAndHoveredWindowIndex(firstVisible)
            } else {
                cycleFocusedWindowIndex(-1)
            }
        }
    }

    /// tabs detection is a flaky work-around the lack of public API to observe OS tabs
    /// see: https://github.com/lwouis/alt-tab-macos/issues/1540
    private static func detectTabbedWindows(_ window: Window, _ cgsWindowIds: [CGWindowID], _ visibleCgsWindowIds: [CGWindowID]) {
        if let cgWindowId = window.cgWindowId {
            if window.isMinimized || window.isHidden {
                if #available(macOS 13.0, *) {
                    // not exact after window merging
                    window.isTabbed = !cgsWindowIds.contains(cgWindowId)
                } else {
                    // not known
                    window.isTabbed = false
                }
            } else {
                window.isTabbed = !visibleCgsWindowIds.contains(cgWindowId)
            }
        }
    }

    static func updatesBeforeShowing() -> Bool {
        if list.count == 0 || MissionControl.state() == .showAllWindows || MissionControl.state() == .showFrontWindows { return false }
        // TODO: find a way to update space info when spaces are changed, instead of on every trigger
        // workaround: when Preferences > Mission Control > "Displays have separate Spaces" is unchecked,
        // switching between displays doesn't trigger .activeSpaceDidChangeNotification; we get the latest manually
        Spaces.refresh()
        let spaceIdsAndIndexes = Spaces.idsAndIndexes.map { $0.0 }
        lazy var cgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes)
        lazy var visibleCgsWindowIds = Spaces.windowsInSpaces(spaceIdsAndIndexes, false)
        for window in list {
            detectTabbedWindows(window, cgsWindowIds, visibleCgsWindowIds)
            updatesWindowSpace(window)
            refreshIfWindowShouldBeShownToTheUser(window)
        }
        refreshWhichWindowsToShowTheUser()
        sort()
        if (!list.contains { $0.shouldShowTheUser }) { return false }
        return true
    }

    static func updatesWindowSpace(_ window: Window) {
        // macOS bug: if you tab a window, then move the tab group to another space, other tabs from the tab group will stay on the current space
        // you can use the Dock to focus one of the other tabs and it will teleport that tab in the current space, proving that it's a macOS bug
        // note: for some reason, it behaves differently if you minimize the tab group after moving it to another space
        if let cgWindowId = window.cgWindowId {
            let spaceIds = cgWindowId.spaces()
            window.spaceIds = spaceIds
            window.spaceIndexes = spaceIds.compactMap { spaceId in Spaces.idsAndIndexes.first { $0.0 == spaceId }?.1 }
            window.isOnAllSpaces = spaceIds.count > 1
        }
    }

    // dispatch screenshot requests off the main-thread, then wait for completion
    static func refreshThumbnailsAsync(_ windows: [Window], _ source: RefreshCausedBy, windowRemoved: Bool = false) {
        guard (!windows.isEmpty || windowRemoved) && ScreenRecordingPermission.status == .granted
               && !Preferences.onlyShowApplications()
               && (!Appearance.hideThumbnails || Preferences.previewFocusedWindow) else { return }
        var eligibleWindows = [Window]()
        for window in windows {
            if !window.isWindowlessApp, let cgWindowId = window.cgWindowId, cgWindowId != CGWindowID(bitPattern: -1) {
                eligibleWindows.append(window)
            }
        }
        guard (!eligibleWindows.isEmpty || windowRemoved) else { return }
        if #available(macOS 14.0, *) {
            WindowCaptureScreenshots.oneTimeScreenshots(eligibleWindows, source)
        } else {
            WindowCaptureScreenshotsPrivateApi.oneTimeScreenshots(eligibleWindows, source)
        }
    }

    static func refreshWhichWindowsToShowTheUser() {
        if Preferences.onlyShowApplications() {
            // Group windows by application and select the optimal main window
            let windowsGroupedByApp = Dictionary(grouping: list) { $0.application.pid }
            windowsGroupedByApp.forEach { (app, windows) in
                if windows.count > 1, let mainWindow = selectMainWindow(windows) {
                    windows.forEach { window in
                        if window.cgWindowId != mainWindow.cgWindowId {
                            window.shouldShowTheUser = false
                        }
                    }
                }
            }
        }
    }

    private static func refreshIfWindowShouldBeShownToTheUser(_ window: Window) {
        window.shouldShowTheUser =
            !(window.application.bundleIdentifier.flatMap { id in
                Preferences.blacklist.contains {
                    id.hasPrefix($0.bundleIdentifier) &&
                        ($0.hide == .always || (window.isWindowlessApp && $0.hide != .none))
                }
            } ?? false) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .active && window.application.pid != NSWorkspace.shared.frontmostApplication?.processIdentifier) &&
            !(Preferences.appsToShow[App.app.shortcutIndex] == .nonActive && window.application.pid == NSWorkspace.shared.frontmostApplication?.processIdentifier) &&
            !(!(Preferences.showHiddenWindows[App.app.shortcutIndex] != .hide) && window.isHidden) &&
            ((Preferences.showWindowlessApps[App.app.shortcutIndex] != .hide && window.isWindowlessApp) ||
                !window.isWindowlessApp &&
                !(!(Preferences.showFullscreenWindows[App.app.shortcutIndex] != .hide) && window.isFullscreen) &&
                !(!(Preferences.showMinimizedWindows[App.app.shortcutIndex] != .hide) && window.isMinimized) &&
                !(Preferences.spacesToShow[App.app.shortcutIndex] == .visible && !Spaces.visibleSpaces.contains { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) &&
                !(Preferences.screensToShow[App.app.shortcutIndex] == .showingAltTab && !window.isOnScreen(NSScreen.preferred)) &&
                (Preferences.showTabsAsWindows || !window.isTabbed))
    }

    /// Selects the most appropriate main window from a given list of windows.
    ///
    /// The selection criteria are as follows:
    /// 1. Prefer the focused window if it exists.
    /// 2. Prefer the main window of the application if the focused window is not found.
    ///
    /// - Parameter windows: An array of `Window` objects to select from.
    /// - Returns: The most appropriate `Window` object based on the selection criteria, or `nil` if the array is empty.
    static func selectMainWindow(_ windows: [Window]) -> Window? {
        let sortedWindows = windows.sorted { (window1, window2) -> Bool in
            // Prefer the focus window
            if window1.application.focusedWindow?.cgWindowId == window1.cgWindowId {
                return true
            } else if window2.application.focusedWindow?.cgWindowId == window2.cgWindowId {
                return false
            }
            // Prefer the main window
            if window1.isAppMainWindow() && !window2.isAppMainWindow() {
                return true
            } else if !window1.isAppMainWindow() && window2.isAppMainWindow() {
                return false
            }
            return true
        }
        return sortedWindows.first { $0.shouldShowTheUser }
    }
}

enum WindowActivityType: Int {
    case none = 0
    case hover = 1
    case focus = 2
}

// MARK: - Smith–Waterman local alignment (linear gap)

struct SWOp {
    let op: Character // 'M' match, 'S' substitute, 'I' insertion, 'D' deletion
    let qi: Int       // index in query (if applicable)
    let tj: Int       // index in text (if applicable)
}

struct SWResult {
    let score: Int
    let similarity: Double
    let span: Range<Int>      // [start, end) in text
    let subspans: [Range<Int>]// exact-match subspans within span
    let ops: [SWOp]
}

/// Computes Smith–Waterman local alignment between `query` and `text`.
///
/// Notes:
/// - Default matching is case-insensitive to better match typical search behavior.
///   This only affects character equality checks; indices returned still refer to the
///   original `text` character positions since lowercasing does not change the
///   character count for common scripts we display.
func smithWatermanHighlights(query: String,
                             text: String,
                             match: Int = 2,
                             mismatch: Int = -1,
                             gap: Int = -2,
                             topK: Int = 1,
                             minScore: Int = 1,
                             allowOverlaps: Bool = false,
                             caseInsensitive: Bool = true) -> [SWResult] {
    // For case-insensitive matching, operate on lowercased copies for equality checks.
    // We still use indices against the original strings, which have the same Character count.
    let qArr = Array(caseInsensitive ? query.lowercased() : query)
    let tArr = Array(caseInsensitive ? text.lowercased() : text)
    let n = qArr.count
    let m = tArr.count
    if n == 0 || m == 0 { return [] }

    var H = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
    var bt = Array(repeating: Array(repeating: Character("\0"), count: m + 1), count: n + 1)

    for i in 1...n {
        for j in 1...m {
            let sDiag = H[i-1][j-1] + (qArr[i-1] == tArr[j-1] ? match : mismatch)
            let sUp   = H[i-1][j] + gap
            let sLeft = H[i][j-1] + gap
            var val = sDiag
            var ptr: Character = "D"
            if sUp > val { val = sUp; ptr = "U" }
            if sLeft > val { val = sLeft; ptr = "L" }
            if val < 0 { val = 0; ptr = "\0" }
            H[i][j] = val
            bt[i][j] = ptr
        }
    }

    var candidates: [(score: Int, i: Int, j: Int)] = []
    for i in 1...n {
        for j in 1...m {
            let s = H[i][j]
            if s > 0 { candidates.append((s, i, j)) }
        }
    }
    if candidates.isEmpty { return [] }
    candidates.sort { (a, b) in a.score > b.score }

    var results: [SWResult] = []
    var usedSpans: [Range<Int>] = []

    func rangesOverlap(_ a: Range<Int>, _ b: Range<Int>) -> Bool {
        return a.lowerBound < b.upperBound && b.lowerBound < a.upperBound
    }

    func backtrack(_ iStart: Int, _ jStart: Int) -> (ops: [SWOp], span: Range<Int>, subspans: [Range<Int>], score: Int) {
        var opsRev: [SWOp] = []
        var consumedJ: [Int] = []
        var i = iStart
        var j = jStart
        while i > 0 && j > 0 && H[i][j] > 0 {
            let p = bt[i][j]
            if p == "D" {
                opsRev.append(SWOp(op: qArr[i-1] == tArr[j-1] ? "M" : "S", qi: i-1, tj: j-1))
                consumedJ.append(j-1)
                i -= 1; j -= 1
            } else if p == "U" {
                opsRev.append(SWOp(op: "D", qi: i-1, tj: j))
                i -= 1
            } else if p == "L" {
                opsRev.append(SWOp(op: "I", qi: i, tj: j-1))
                consumedJ.append(j-1)
                j -= 1
            } else {
                break
            }
        }
        let ops = opsRev.reversed()
        let jStartIdx = consumedJ.min() ?? jStart
        let jEndIdx = (consumedJ.max() ?? (jStart-1)) + 1
        let span = jStartIdx..<jEndIdx
        var subs: [Range<Int>] = []
        var runStart: Int? = nil
        var jCursor = jStartIdx
        for op in ops {
            switch op.op {
            case "M":
                if runStart == nil { runStart = jCursor }
                jCursor += 1
            case "S":
                if let rs = runStart { subs.append(rs..<jCursor); runStart = nil }
                jCursor += 1
            case "I":
                if let rs = runStart { subs.append(rs..<jCursor); runStart = nil }
                jCursor += 1
            case "D":
                if let rs = runStart { subs.append(rs..<jCursor); runStart = nil }
            default:
                break
            }
        }
        if let rs = runStart { subs.append(rs..<jCursor) }
        return (Array(ops), span, subs, H[iStart][jStart])
    }

    for (score, i, j) in candidates {
        if results.count >= topK { break }
        if score < minScore { break }
        let res = backtrack(i, j)
        if !allowOverlaps && usedSpans.contains(where: { rangesOverlap($0, res.span) }) { continue }
        let sim = Double(res.score) / Double(max(1, match * n))
        results.append(SWResult(score: res.score, similarity: sim, span: res.span, subspans: res.subspans, ops: res.ops))
        usedSpans.append(res.span)
    }
    return results
}

func smithWatermanSimilarity(query: String, text: String) -> Double {
    return smithWatermanHighlights(query: query, text: text, topK: 1).first?.similarity ?? 0.0
}

// MARK: - Search cache helpers

extension Windows {
    /// Computes and caches Smith–Waterman results for the given window and query,
    /// reusing previous values if the query hasn't changed.
    fileprivate static func ensureSearchCache(for window: Window, query: String) {
        if window.lastSearchQuery == query { return }
        if query.isEmpty {
            window.lastSearchQuery = query
            window.swAppResults = []
            window.swTitleResults = []
            window.swBestSimilarity = 0
            return
        }
        let appName = window.application.localizedName ?? ""
        let title = window.title ?? ""
        // Capture multiple non-overlapping high-scoring local alignments so we can
        // highlight discontinuous parts. Keep topK small for performance.
        let topK = 3
        let appResList = smithWatermanHighlights(query: query, text: appName, topK: topK, allowOverlaps: false)
        let titleResList = smithWatermanHighlights(query: query, text: title, topK: topK, allowOverlaps: false)
        window.swAppResults = appResList
        window.swTitleResults = titleResList
        let nameSim = appResList.first?.similarity ?? 0.0
        let titleSim = titleResList.first?.similarity ?? 0.0
        // slight boost to app-name matches to prefer whole-app hits
        window.swBestSimilarity = max(nameSim * 1.02, titleSim)
        window.lastSearchQuery = query
    }
}
