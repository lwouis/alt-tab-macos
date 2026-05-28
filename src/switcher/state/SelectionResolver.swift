import Foundation

/// One window as seen by the selection kernel — just the fields selection logic needs.
/// Decouples the pure decision from the `Window` AppKit class so this is unit-testable.
struct SelectionWindow: Equatable {
    let id: String
    let visible: Bool
    let lastFocusOrder: Int
    let isMinimized: Bool
    let isWindowlessApp: Bool
}

/// Snapshot of everything the kernel needs to pick the next selection. No globals, no AppKit.
struct SelectionInputs: Equatable {
    let list: [SelectionWindow]
    let selectedIndex: Int
    let selectedTarget: String?
    /// True iff `Preferences.windowOrder[shortcutIndex] != .recentlyFocused`
    /// AND `Applications.frontmostPid != nil`. Gates the alpha/space-ordering initial-pick path.
    let useLastFocusedRule: Bool
    let restoreDefaultOnSearchClear: Bool
    let bestMatchOnSearchChange: Bool
}

/// What the kernel recommends. Wrapper translates this into side effects (highlight redraws,
/// scroll-to-visible, thumbnail preview, etc.).
enum SelectionDecision: Equatable {
    /// Post-firstVisible-guard empty case. Wrapper: clear `selectedTarget` and `hoveredIndex`.
    case clearTargetAndHover

    /// "From scratch" initial-pick path with a valid pick. Wrapper: clear hovered + reset
    /// `selectedTarget` first, then move selection to `index`.
    case resetThenSelect(Int)

    /// "From scratch" but list has nothing to land on (e.g. search-clear with no visible).
    /// Wrapper: clear hovered + reset `selectedTarget`; leave `selectedIndex`.
    case resetWithoutSelection

    /// Move selection to `index`. `selectedTarget` follows to `list[index].id`.
    case selectAt(Int)

    /// `selectedIndex` is fine; just ensure `selectedTarget == list[index].id` (backfill).
    case ensureTargetSet(Int)
}

enum SelectionResolver {
    /// Pure port of `Windows.updateSelectedWindow`. Branching order matches the original so the
    /// behavior-preserving extraction can be verified against the running app before we touch
    /// the logic.
    static func decide(_ i: SelectionInputs) -> SelectionDecision {
        // 1) Search-clear path takes precedence — runs even when no visible windows.
        if i.restoreDefaultOnSearchClear {
            return resetInitialPick(i)
        }
        // 2) Empty visible list.
        let visibleIndexes = i.list.indices.filter { i.list[$0].visible }
        guard let firstVisibleIndex = visibleIndexes.first else {
            return .clearTargetAndHover
        }
        // 3) Search-best-match path.
        if i.bestMatchOnSearchChange {
            return .selectAt(firstVisibleIndex)
        }
        // 4) "From scratch" only when there's no user selection yet — first refresh of the
        // session. Previously this also fired whenever the MRU-focused window changed mid-show,
        // which short-circuited past target preservation and made the highlight jump (#5665).
        // Removed: AX events that reorder the list during display now fall through to
        // `findTarget` below, keeping the user's pick stable.
        if i.selectedTarget == nil {
            return resetInitialPick(i)
        }
        // 5) Try to restore the user's chosen target by id.
        if let targetIndex = findTarget(i.list, i.selectedTarget) {
            return .selectAt(targetIndex)
        }
        // 6) Target gone — adapt to the closest visible.
        return adapt(i, visibleIndexes: visibleIndexes, lastVisible: visibleIndexes.last!)
    }

    /// Mirrors `setInitialSelectedAndHoveredWindowIndex` — picks the index, defers reset to wrapper.
    static func initialPickIndex(_ i: SelectionInputs) -> Int? {
        if i.useLastFocusedRule, let idx = getLastFocusedOrderWindowIndex(i.list) {
            return idx
        }
        // Edge case: top two windows both minimized — land on index 0 rather than cycling past.
        if i.list.count >= 2 && i.list[0].isMinimized && i.list[1].isMinimized {
            return i.list[0].visible ? 0 : nil
        }
        return cycleFromZero(i.list)
    }

    /// Cycles from index 0 by step +1, wrapping around the list, stopping at the first visible
    /// window. Returns 0 if only index 0 is visible (the wrap lands back on it). Returns nil if
    /// the list is empty or no window is visible.
    static func cycleFromZero(_ list: [SelectionWindow]) -> Int? {
        guard !list.isEmpty else { return nil }
        // Try indices 1, 2, …, count-1, then 0 (wrap). Single return point — the trailing
        // `return nil` covers the "no window visible" case without needing a separate guard.
        for offset in 1...list.count {
            let idx = offset % list.count
            if list[idx].visible {
                return idx
            }
        }
        return nil
    }

    /// Returns the index of the visible non-windowless window with the lowest `lastFocusOrder`.
    /// Mirrors `Windows.getLastFocusedOrderWindowIndex`.
    static func getLastFocusedOrderWindowIndex(_ list: [SelectionWindow]) -> Int? {
        var bestIndex: Int? = nil
        var bestOrder = Int.max
        for (idx, w) in list.enumerated() {
            if !w.isWindowlessApp && w.visible && w.lastFocusOrder < bestOrder {
                bestOrder = w.lastFocusOrder
                bestIndex = idx
            }
        }
        return bestIndex
    }

    /// Find the user's chosen window by id, returning its current index if visible.
    /// Mirrors the lookup in the old `Windows.restoreSelectionTargetIfVisible`.
    static func findTarget(_ list: [SelectionWindow], _ targetId: String?) -> Int? {
        guard let targetId else { return nil }
        return list.firstIndex { $0.id == targetId && $0.visible }
    }

    // MARK: - Internal

    private static func resetInitialPick(_ i: SelectionInputs) -> SelectionDecision {
        if let idx = initialPickIndex(i) {
            return .resetThenSelect(idx)
        }
        return .resetWithoutSelection
    }

    /// Mirrors `adaptSelectionToVisibleIndexes`. `visibleIndexes` is non-empty by caller's guard,
    /// and `decide()` only invokes `adapt` after the `selectedTarget == nil` early-return — so
    /// the only branching here is "is `selectedIndex` still in `visibleIndexes`?"
    private static func adapt(_ i: SelectionInputs, visibleIndexes: [Int], lastVisible: Int) -> SelectionDecision {
        if !visibleIndexes.contains(i.selectedIndex) {
            let closest = visibleIndexes.last(where: { $0 < i.selectedIndex }) ?? lastVisible
            return .selectAt(closest)
        }
        // selectedIndex is in visibleIndexes (so it's already between firstVisible and lastVisible),
        // and the target is set (non-nil) by decide()'s contract. Return an idempotent target
        // backfill — the wrapper treats a no-change as a no-op.
        return .ensureTargetSet(i.selectedIndex)
    }
}
