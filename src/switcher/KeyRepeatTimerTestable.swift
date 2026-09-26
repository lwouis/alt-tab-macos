import Foundation

/// Pure decision for the artificial key-repeat: given wall-clock timestamps, should this repeat tick actually
/// advance the selection? Extracted from `KeyRepeatTimer` so the timing rule is unit-tested in isolation
/// (no timer, no DispatchSource, no AppKit). See `KeyRepeatTimerSpecs.md`.
enum KeyRepeatTimerTestable {
    /// If NEITHER anchor is known, fall back to arm-relative timing after this extra budget so hold-to-cycle
    /// can't get permanently wedged. A genuine safety net now — it used to be the normal path, see below.
    static let missedVisibleSignalBudget: TimeInterval = 1

    /// Floor for `lateBudget`, so `defaults write -g KeyRepeat 0` (a legal value the OS reads as "no delay
    /// between repeats") cannot turn the late-tick rule into "refuse every tick".
    static let minimumLateBudget: TimeInterval = 0.02

    /// How late a tick may reach the main thread and still count. One repeat interval: past that, the tick
    /// the timer fired next has already superseded it.
    static func lateBudget(_ repeatRate: TimeInterval) -> TimeInterval {
        max(repeatRate, minimumLateBudget)
    }

    /// Stop when the shortcut is known released, by its own event or by reading the key itself.
    ///
    /// **The key's physical state is read because Carbon's hotkey-released event can go missing** (#6075).
    /// While the hold modifier stays down, that event is the only thing that sets a key shortcut's state to
    /// `.up`, so without it the timer kept cycling after a single tap, pinned the selection on the last tile
    /// (cycling refuses to wrap while the timer runs), and every later tap was refused the same way. The read
    /// stays true for a held key while Secure Input is on (checked with a synthetic F19 press).
    static func shouldStop(shortcutIsUp: Bool, keyIsPhysicallyDown: Bool?, holdModifierIsReleased: Bool) -> Bool {
        shortcutIsUp || keyIsPhysicallyDown == false || holdModifierIsReleased
    }

    /// A slow show (WindowServer busy after a fullscreen/Space transition) can present the panel ~500ms after
    /// the timer was armed. The initial-delay grace must be measured from when the user could actually SEE the
    /// switcher, else repeats queued during the invisible gap fire the instant it appears and jump the
    /// selection several tiles.
    ///
    /// **Two anchors, because the accurate one can be absent.** `panelBecameVisibleAt` is the true "pixels on
    /// screen" moment (our own panel's WindowServer `orderedIn`) and wins whenever it is known — but it is not
    /// known today at all: order-in delivery needs the per-window opt-in (`WindowServerEvents.wsWindows`) and
    /// the panel is not in it, so that notification never arrives. Every tick therefore took the fallback and
    /// the first cycle landed a full second late — measured live at 1377ms against a system `InitialKeyRepeat`
    /// of 417ms, on EVERY hold, not merely a slow show. `panelShownAt` is the anchor that cannot go missing
    /// (`TilesPanel.show()` sets it as it orders the panel front). It is slightly EARLY, since the WindowServer
    /// paints after the order-front call returns, which is exactly why the visible signal stays above it rather
    /// than replacing it.
    ///
    /// **`firedAt` is when the timer fired; `now` is when the main thread got to it.** The two differ whenever
    /// the main thread is busy, and a tick that waited is not evidence that the key is still held: the key-up
    /// that would have stopped the timer is an event source, and the run loop drains the whole main dispatch
    /// queue before it reads the next event, so a backlog of ticks is always applied BEFORE the release that
    /// cancels them. That is what walked the selection ~8 tiles on the first summon after a few idle minutes
    /// (#5977): a stall after the panel was ordered front, with the grace measured from the show, made every
    /// queued tick eligible at once.
    static func shouldApplyArtificialRepeat(now: TimeInterval, firedAt: TimeInterval, armedAt: TimeInterval,
                                            panelBecameVisibleAt: TimeInterval?, panelShownAt: TimeInterval?,
                                            initialDelay: TimeInterval, repeatRate: TimeInterval) -> Bool {
        if now - firedAt >= lateBudget(repeatRate) { return false }
        if let anchor = panelBecameVisibleAt ?? panelShownAt {
            return now - anchor >= initialDelay
        }
        return now - armedAt >= initialDelay + missedVisibleSignalBudget
    }
}
