import Foundation

/// Decides the display order of windows in the switcher. When a search query is active, ranks by
/// match-then-relevance; otherwise applies the user's chosen order (recently-focused / recently-created
/// / alphabetical / by-space), after grouping the screen showing AltTab first (when configured) and
/// pushing any "show at the end" buckets (windowless / hidden / minimized) to the back of each group,
/// with a stable `lastFocusOrder` tiebreak. Pure kernel.
///
/// `OrderWindow` bundles the canonical `WindowState` + `ApplicationState` for a window with its
/// **query-derived** search rank (`searchMatches` / `searchRelevance`) — that bundling earns its
/// keep because `OrderWindow`s are precomputed once per window and read repeatedly during sort.
/// The other config knobs are plain labeled params with defaults.

enum OrderSortType: Equatable { case recentlyFocused, recentlyCreated, alphabetical, space }

/// A window's data + its app's data + its (query-dependent) search rank, for ordering.
struct OrderWindow: Equatable {
    let state: WindowState
    let app: ApplicationState
    let searchMatches: Bool       // Search.matches (only meaningful when search is active)
    let searchRelevance: Double   // Search.relevance
    /// `Window.isOnScreen(NSScreen.preferred)`; only computed (and only read) when grouping by screen.
    var isOnPreferredScreen = true
}

struct ApplicationRepresentativeCandidate: Equatable {
    let id: String
    let isCurrentAttention: Bool
    let isLastAttention: Bool
    let isMainWindow: Bool
    let lastFocusOrder: Int
    let creationOrder: Int
}

enum ApplicationRepresentativeResolver {
    static func pick(_ candidates: [ApplicationRepresentativeCandidate], stableId: String?) -> String? {
        guard !candidates.isEmpty else { return nil }
        if let current = best(candidates.filter { $0.isCurrentAttention }) { return current.id }
        if let stableId, candidates.contains(where: { $0.id == stableId }) { return stableId }
        if let attended = best(candidates.filter { $0.isLastAttention }) { return attended.id }
        if let main = best(candidates.filter { $0.isMainWindow }) { return main.id }
        return best(candidates)?.id
    }

    private static func best(_ candidates: [ApplicationRepresentativeCandidate])
        -> ApplicationRepresentativeCandidate? {
        candidates.min {
            if $0.lastFocusOrder != $1.lastFocusOrder { return $0.lastFocusOrder < $1.lastFocusOrder }
            if $0.creationOrder != $1.creationOrder { return $0.creationOrder > $1.creationOrder }
            return $0.id < $1.id
        }
    }
}

/// Folds the other screens' windows into one stack tile while grouping by screen. Pure kernel behind
/// `Windows.applyFold` and `Windows.unfoldIfUserArrivedOnStack`.
enum ScreenFoldResolver {
    struct Fold: Equatable {
        /// The window drawn as the stack: the other screens' first shown window in display order.
        let stack: Int
        /// The other shown windows of those screens, hidden inside the stack.
        let foldedAway: [Int]
    }

    /// `otherScreenShown[i]`: the window at display position `i` is in the other screens' group and passes
    /// the filters. Nil when there is nothing to fold: folding is off, or one window alone stands for itself.
    static func fold(_ otherScreenShown: [Bool], enabled: Bool) -> Fold? {
        let others = otherScreenShown.indices.filter { otherScreenShown[$0] }
        guard enabled, others.count > 1 else { return nil }
        return Fold(stack: others[0], foldedAway: Array(others.dropFirst()))
    }

    /// The stack opens when the user moves the selection onto it with the keyboard — not when the default pick
    /// lands on it (a quick Cmd-Tab back to the other screen must not unfold it), and not on mouse hover.
    static func opensOnArrival(isStack: Bool, userPickedSelection: Bool, fromMouse: Bool, fromRefresh: Bool) -> Bool {
        isStack && userPickedSelection && !fromMouse && !fromRefresh
    }
}

enum WindowOrderResolver {
    /// Strict-weak-ordering "should `a` sort before `b`?"
    static func isOrderedBefore(_ a: OrderWindow, _ b: OrderWindow,
                                searchActive: Bool = false,
                                windowlessAtEnd: Bool = false,   // showWindowlessApps == .showAtTheEnd
                                hiddenAtEnd: Bool = false,       // showHiddenWindows == .showAtTheEnd
                                minimizedAtEnd: Bool = false,    // showMinimizedWindows == .showAtTheEnd
                                groupByScreen: Bool = false,     // screensToShow == .allShowingAltTabFirst
                                sortType: OrderSortType = .recentlyFocused) -> Bool {
        if searchActive {
            if a.searchMatches != b.searchMatches { return a.searchMatches }
            if a.searchRelevance != b.searchRelevance { return a.searchRelevance > b.searchRelevance }
            return a.state.lastFocusOrder < b.state.lastFocusOrder
        }
        // the screen showing AltTab is the outermost group, so each "show at the end" bucket sinks within its group
        if groupByScreen && a.isOnPreferredScreen != b.isOnPreferredScreen { return a.isOnPreferredScreen }
        // separate buckets for these window types (pushed to the end)
        if windowlessAtEnd && a.state.isWindowlessApp != b.state.isWindowlessApp { return b.state.isWindowlessApp }
        if hiddenAtEnd && a.app.isHidden != b.app.isHidden { return b.app.isHidden }
        if minimizedAtEnd && a.state.isMinimized != b.state.isMinimized { return b.state.isMinimized }
        // sort within each bucket
        if sortType == .recentlyFocused { return a.state.lastFocusOrder < b.state.lastFocusOrder }
        if sortType == .recentlyCreated { return b.state.creationOrder < a.state.creationOrder }
        var order = ComparisonResult.orderedSame
        if sortType == .alphabetical {
            order = compareByAppNameThenTitle(a, b)
        }
        if sortType == .space {
            if a.state.isOnAllSpaces && b.state.isOnAllSpaces {
                order = .orderedSame
            } else if a.state.isOnAllSpaces {
                order = .orderedAscending
            } else if b.state.isOnAllSpaces {
                order = .orderedDescending
            } else if let s0 = a.state.spaceIndexes.first, let s1 = b.state.spaceIndexes.first {
                order = intOrder(s0, s1)
            } else if a.state.spaceIndexes.first != nil {
                order = .orderedAscending
            } else if b.state.spaceIndexes.first != nil {
                order = .orderedDescending
            }
            if order == .orderedSame {
                order = compareByAppNameThenTitle(a, b)
            }
        }
        if order == .orderedSame {
            order = intOrder(a.state.lastFocusOrder, b.state.lastFocusOrder)
        }
        return order == .orderedAscending
    }

    static func compareByAppNameThenTitle(_ a: OrderWindow, _ b: OrderWindow) -> ComparisonResult {
        let order = (a.app.localizedName ?? "").localizedStandardCompare(b.app.localizedName ?? "")
        if order == .orderedSame {
            return a.state.title.localizedStandardCompare(b.state.title)
        }
        return order
    }

    private static func intOrder(_ a: Int, _ b: Int) -> ComparisonResult {
        a < b ? .orderedAscending : (a > b ? .orderedDescending : .orderedSame)
    }
}
