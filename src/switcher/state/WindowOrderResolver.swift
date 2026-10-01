import Foundation

/// Decides the display order of windows in the switcher. When a search query is active, ranks by
/// match-then-relevance; otherwise applies the user's chosen order (recently-focused / recently-created
/// / alphabetical / by-space), after pushing any "show at the end" buckets (windowless / hidden /
/// minimized) to the back, with a stable `lastFocusOrder` tiebreak. Pure kernel.
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

enum WindowOrderResolver {
    /// Strict-weak-ordering "should `a` sort before `b`?"
    static func isOrderedBefore(_ a: OrderWindow, _ b: OrderWindow,
                                searchActive: Bool = false,
                                windowlessAtEnd: Bool = false,   // showWindowlessApps == .showAtTheEnd
                                hiddenAtEnd: Bool = false,       // showHiddenWindows == .showAtTheEnd
                                minimizedAtEnd: Bool = false,    // showMinimizedWindows == .showAtTheEnd
                                sortType: OrderSortType = .recentlyFocused) -> Bool {
        if searchActive {
            if a.searchMatches != b.searchMatches { return a.searchMatches }
            if a.searchRelevance != b.searchRelevance { return a.searchRelevance > b.searchRelevance }
            return a.state.lastFocusOrder < b.state.lastFocusOrder
        }
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
