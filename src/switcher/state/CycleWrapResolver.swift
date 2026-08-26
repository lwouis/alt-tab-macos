import Foundation

/// One selection advance, as seen by the wrap decision.
struct CycleAdvance: Equatable {
    /// This advance would leave the list by its end and land at the other end.
    let isWrapping: Bool
    /// The caller allows wrapping at all (row-bounded navigation passes false).
    let allowWrap: Bool
    /// The OS said the key event driving this advance was an auto-repeat (`NSEvent.isARepeat`).
    let lastEventIsARepeat: Bool
    /// This advance IS one of `KeyRepeatTimer`'s synthesized ticks, rather than a key event.
    ///
    /// Deliberately a fact about THIS advance, not about the timer. Asking instead whether a timer was
    /// ARMED — as this rule used to — silently blocks real presses: a modifier-only shortcut (the default
    /// `previousWindowShortcut` = ⇧) holds its timer armed for the entire time the key is down, so every
    /// ⌥⇧+⇥ press during the hold read as a repeat and backwards cycling dead-ended at the first tile.
    let isArtificialRepeatTick: Bool
}

/// Pure decision for "may this advance wrap around the end of the list?". Extracted from
/// `Windows.cycleSelectedWindowIndex` and `TilesView.nextRow`, which carried the same rule twice.
/// See `CycleWrapResolverSpecs.md`.
enum CycleWrapResolver {
    static func blocksWrap(_ advance: CycleAdvance) -> Bool {
        guard advance.isWrapping else { return false }
        return !advance.allowWrap || advance.lastEventIsARepeat || advance.isArtificialRepeatTick
    }
}
