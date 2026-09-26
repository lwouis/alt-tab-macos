import XCTest

final class KeyRepeatTimerTests: XCTestCase {
    private let initialDelay: TimeInterval = 0.4
    private let repeatRate: TimeInterval = 0.1

    private func shouldApply(now: TimeInterval, firedAt: TimeInterval? = nil, armedAt: TimeInterval,
                             panelBecameVisibleAt: TimeInterval? = nil, panelShownAt: TimeInterval? = nil,
                             repeatRate: TimeInterval? = nil) -> Bool {
        KeyRepeatTimerTestable.shouldApplyArtificialRepeat(
            now: now, firedAt: firedAt ?? now, armedAt: armedAt, panelBecameVisibleAt: panelBecameVisibleAt,
            panelShownAt: panelShownAt, initialDelay: initialDelay, repeatRate: repeatRate ?? self.repeatRate)
    }

    // MARK: A. Visible timestamp known — gate from visibility

    /// visible 0.5s ago, initialDelay 0.4s → applies.
    func testAppliesOnceVisibleForInitialDelay() {
        XCTAssertTrue(shouldApply(now: 100, armedAt: 99.4, panelBecameVisibleAt: 99.5))
    }

    /// visible 0.1s ago, initialDelay 0.4s → skips. The core fix: the slow show finally presented the
    /// panel, but the grace hasn't elapsed since it became visible, so a queued repeat mustn't fire.
    func testSkipsWhenNotVisibleLongEnough() {
        XCTAssertFalse(shouldApply(now: 100, armedAt: 99.5, panelBecameVisibleAt: 99.9))
    }

    /// visible exactly initialDelay ago → applies (boundary is inclusive).
    func testAppliesExactlyAtInitialDelayBoundary() {
        XCTAssertTrue(shouldApply(now: 100, armedAt: 99.6, panelBecameVisibleAt: 100 - initialDelay))
    }

    // MARK: A2. The show-time anchor — the guaranteed one

    /// **The 1.4s bug.** `panelBecameVisibleAt` comes from our own panel's WindowServer `orderedIn`, and that
    /// notification never arrives: order-in needs the per-window opt-in (`WindowServerEvents.wsWindows`), which
    /// the panel is not in. So EVERY tick took the fallback branch below and the first cycle landed at
    /// `armedAt + initialDelay + 1s` — measured live at 1377ms against a system `InitialKeyRepeat` of 417ms,
    /// on every hold-to-cycle, not just a slow show. The 1s budget was the normal path, not a safety net.
    ///
    /// `TilesPanel.show()` supplies an anchor that cannot go missing. It is slightly early (the WindowServer
    /// paints after the order-front returns), which is why the WS signal stays as the correction above it.
    func testAppliesFromTheShowAnchorWhenNoWindowServerSignalArrives() {
        XCTAssertTrue(shouldApply(now: 100, armedAt: 99.4, panelShownAt: 99.5))
        XCTAssertFalse(shouldApply(now: 100, armedAt: 99.4, panelShownAt: 99.9))
    }

    /// The WindowServer signal is the CORRECTION, not a peer: it is the true "pixels on screen" moment and
    /// lands after the show, so when both are known it wins — a slow show must not start the grace early.
    func testTheWindowServerSignalOverridesTheShowAnchor() {
        XCTAssertFalse(shouldApply(now: 100, armedAt: 99.0, panelBecameVisibleAt: 99.9, panelShownAt: 99.1))
    }

    // MARK: B. Neither anchor known — arm-relative fallback

    /// never visible, armed 0.5s ago, initialDelay 0.4s → skips. The queued-burst case: repeats due at
    /// ~arm+initialDelay are suppressed while the panel still isn't up. Fallback opens at initialDelay + 1s.
    func testSkipsBeforeFallbackBudgetWhenNeverVisible() {
        XCTAssertFalse(shouldApply(now: 100, armedAt: 99.5))
    }

    /// never visible, armed 1.5s ago, initialDelay 0.4s → applies (>= 0.4 + 1), so a missed visible
    /// signal can't wedge hold-to-cycle forever.
    func testAppliesAfterFallbackBudgetWhenNeverVisible() {
        XCTAssertTrue(shouldApply(now: 100, armedAt: 98.5))
    }

    // MARK: C. The tick reached the main thread late — it stands for nothing

    /// **#5977.** The first summon after a few idle minutes stalls the main thread AFTER the panel was
    /// ordered front, so every tick the timer fired during the stall was eligible at once and the selection
    /// walked ~8 tiles. A tick a whole repeat interval late is refused, whatever the anchors say.
    func testSkipsATickThatWaitedLongerThanOneRepeatInterval() {
        XCTAssertFalse(shouldApply(now: 100, firedAt: 99.4, armedAt: 99.0, panelShownAt: 99.0))
    }

    /// The ordinary main-queue hop is microseconds, and it must not cost the user a repeat.
    func testAppliesATickThatReachedMainPromptly() {
        XCTAssertTrue(shouldApply(now: 100, firedAt: 99.999, armedAt: 99.0, panelShownAt: 99.0))
    }

    /// The boundary is one repeat interval, so a slower `KeyRepeat` tolerates a proportionally longer wait.
    func testTheLateBudgetIsOneRepeatInterval() {
        XCTAssertFalse(shouldApply(now: 100, firedAt: 99.8, armedAt: 99.0, panelShownAt: 99.0, repeatRate: 0.1))
        XCTAssertTrue(shouldApply(now: 100, firedAt: 99.8, armedAt: 99.0, panelShownAt: 99.0, repeatRate: 0.5))
    }

    /// `defaults write -g KeyRepeat 0` is legal, and a zero-length budget would refuse every tick and wedge
    /// hold-to-cycle. The floor keeps a prompt tick applying.
    func testAZeroRepeatRateStillAppliesPromptTicks() {
        XCTAssertTrue(shouldApply(now: 100, firedAt: 99.995, armedAt: 99.0, panelShownAt: 99.0, repeatRate: 0))
        XCTAssertFalse(shouldApply(now: 100, firedAt: 99.9, armedAt: 99.0, panelShownAt: 99.0, repeatRate: 0))
    }

    // MARK: D. When the repeat stops

    /// **#6075.** Carbon's hotkey-released event never arrived, so the shortcut still read `.down` and one tap
    /// walked the selection to the last tile. The key read as physically up stops the repeat anyway.
    func testStopsWhenTheKeyIsUpThoughItsReleaseWasLost() {
        XCTAssertTrue(KeyRepeatTimerTestable.shouldStop(shortcutIsUp: false, keyIsPhysicallyDown: false, holdModifierIsReleased: false))
    }

    /// Holding the key and the hold modifier keeps cycling.
    func testKeepsRepeatingWhileTheKeyIsHeld() {
        XCTAssertFalse(KeyRepeatTimerTestable.shouldStop(shortcutIsUp: false, keyIsPhysicallyDown: true, holdModifierIsReleased: false))
    }

    /// A modifier-only shortcut has no key to read, so only its own state and the hold modifier count.
    func testAModifierOnlyShortcutIgnoresTheKeyRead() {
        XCTAssertFalse(KeyRepeatTimerTestable.shouldStop(shortcutIsUp: false, keyIsPhysicallyDown: nil, holdModifierIsReleased: false))
        XCTAssertTrue(KeyRepeatTimerTestable.shouldStop(shortcutIsUp: true, keyIsPhysicallyDown: nil, holdModifierIsReleased: false))
        XCTAssertTrue(KeyRepeatTimerTestable.shouldStop(shortcutIsUp: false, keyIsPhysicallyDown: nil, holdModifierIsReleased: true))
    }
}
