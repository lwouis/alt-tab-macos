import Cocoa

/// Pure decisions for drag-and-drop over the switcher — extracted from `TilesDocumentView` (the
/// `NSDraggingDestination`) and `CursorEvents` (the global mouse tap) so the behavior is unit-testable
/// without AppKit drag sessions, timers, or an event tap (same idea as `AxEventRouting`). The two call
/// sites turn these decisions into real `NSDragOperation`s, timers, and tap pass-through.
enum DragAndDropResolver {
    /// what a drag-over of the tiles should do for the cursor position handed to us.
    enum DragOver: Equatable {
        /// no tile under the cursor (off the grid) — report no drop and clear any hover.
        case noTarget
        /// a tile is under the cursor, but the pointer hasn't cleared the show-time movement deadzone yet:
        /// report a `.link` drop, but don't select or arm the timer. So a drag already in flight when the
        /// switcher appears doesn't grab a window on the first stray pixel (same deadzone as mouse hover).
        case inDeadzone
        /// a tile is under the cursor and we're past the deadzone — select it (hover highlight) and, when
        /// `restartTimer`, (re)arm the auto-select timer.
        case track(restartTimer: Bool)
    }

    /// Targeting reuses hover's `findTarget` (which expands each tile by 1px so the inter-tile gap still
    /// resolves to a tile) and hover's movement deadzone, so dragging feels exactly like hovering. But
    /// dragging is a stronger intent than hover, so the auto-select timer ALWAYS runs here — hover gates it
    /// on a preference, dragging never does. The timer (re)arms on a target change or once the pointer
    /// leaves the reset radius, and a sub-radius jitter lets the running timer fire.
    static func dragOver(hasTarget: Bool, pastDeadzone: Bool, targetChanged: Bool, movedBeyondResetRadius: Bool) -> DragOver {
        guard hasTarget else { return .noTarget }
        guard pastDeadzone else { return .inDeadzone }
        return .track(restartTimer: targetChanged || movedBeyondResetRadius)
    }

    /// has the pointer moved at least `resetRadius` from `anchor` (where the timer was last armed)? A `nil`
    /// anchor means the timer isn't armed yet, so it counts as "yes" (the first move (re)arms it).
    static func movedBeyondResetRadius(from anchor: CGPoint?, to location: CGPoint, resetRadius: CGFloat) -> Bool {
        guard let anchor else { return true }
        return hypot(location.x - anchor.x, location.y - anchor.y) >= resetRadius
    }

    /// The global mouse tap must NOT consume a `leftMouseUp` ending a gesture it didn't initiate. A file drag
    /// over the switcher can only have started in another app BEFORE the switcher showed (downs outside the
    /// panel are swallowed, and tiles aren't drag sources), so the tap never saw its `leftMouseDown`. Yield
    /// such an up so AppKit / the source app concludes the drop — whether released on a tile, the padding
    /// around the tiles, or outside the panel — otherwise the file stays glued to the cursor. A normal
    /// click's down IS seen, so clicks (select tile, dismiss) route normally and are not yielded.
    static func passesThroughMouseUp(mouseDownWasSeen: Bool) -> Bool {
        !mouseDownWasSeen
    }

    /// A drop opens the dragged URLs with the targeted tile's app, so it needs a target tile, that tile's
    /// window, the app's bundle URL, and at least one URL; otherwise it's rejected (the drag snaps back).
    static func canDrop(hasTarget: Bool, hasWindow: Bool, hasAppBundleURL: Bool, urlCount: Int) -> Bool {
        hasTarget && hasWindow && hasAppBundleURL && urlCount > 0
    }
}
