import Foundation

/// Pure scheduling decisions extracted from `Throttler` / `ThrottlerWithKey` and `AXCallScheduler`, so the
/// timing logic is unit-testable without real clocks or queues (same pattern as `SelectionResolver` /
/// `AxQueryRouting`). The owners keep the actual clock reads + queue dispatch; they just branch on these.

/// The coalescing decision for one `throttleOrProceed` call: leading-edge runs immediately; calls within
/// the window collapse to a single trailing run.
enum ThrottleDecision: Equatable {
    case runNow                            // leading edge (or window already elapsed): run now, (re)start the window
    case scheduleTail(remainingNs: UInt64) // within window, no trailing run pending yet: schedule one after `remaining`
    case coalesce                          // within window, a trailing run is already pending: drop (latest runs on the tail)

    static func decide(lastFireNs: UInt64?, nowNs: UInt64, delayNs: UInt64, tailScheduled: Bool) -> ThrottleDecision {
        // first call ever, or a (practically impossible) backwards clock → treat as a fresh leading edge
        guard let last = lastFireNs, nowNs >= last else { return .runNow }
        let elapsed = nowNs - last
        if elapsed >= delayNs { return .runNow }
        return tailScheduled ? .coalesce : .scheduleTail(remainingNs: delayNs - elapsed)
    }
}

/// Backoff + give-up policy for retrying an AX call against an unresponsive app.
enum RetryPolicy {
    static let backoffStepsNs: [UInt64] = [200_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000] // 200ms, 1s, 2s, 5s…
    static let giveUpAfterNs: UInt64 = 60_000_000_000 // 60s

    /// retry N uses step N, clamped to the last (so it stays at 5s); negative counts floor to the first step.
    static func backoffDelayNs(retryCount: Int) -> UInt64 {
        backoffStepsNs[min(max(0, retryCount), backoffStepsNs.count - 1)]
    }

    static func shouldGiveUp(elapsedSinceStartNs: UInt64) -> Bool {
        elapsedSinceStartNs >= giveUpAfterNs
    }
}

/// May we brute-force this app's AX tree for the inactive tabs its AXTabGroup named but we hold no window for
/// (`Applications.discoverInactiveTabs`)? An inactive tab appears in no CGS list, so this scan is the ONLY way
/// to adopt one — and it is expensive (a full walk of the app's accessibility tree), so it can't simply run on
/// every tab read.
///
/// The gate is per-app and keyed on the SITUATION (the untracked titles plus the app's window count), because
/// that is what says whether anything has changed since we last looked: a tab getting adopted, opened or closed
/// moves the count or the titles. A new situation is always eligible.
///
/// **An attempt that adopted nothing must be RETRYABLE, which is where this went wrong.** The situation used to
/// be recorded before the scan even ran, and once recorded it was refused forever — so a single fruitless
/// attempt (the app's AX tree not ready yet, the classic at launch) permanently gave up on that situation, with
/// no retry and no later trigger. Measured live: 82 tab reads named untracked tabs and the scan
/// adopted nothing at all, while a run where the first attempt happened to land adopted 57.
///
/// So a situation gets a small number of attempts rather than exactly one. Bounded, because the fruitless case
/// is ORDINARY and not an error: Finder destroys a backgrounded tab's window, so its AXTabGroup routinely names
/// tabs that have no window to find (`testFinderTabsAllUntracked`) and no number of scans will ever resolve
/// them. The cap is what keeps that from re-walking the tree on every show forever.
enum InactiveTabScanPolicy {
    static let maxAttemptsPerSituation = 3

    static func shouldScan(recordedSituation: String?, attempts: Int, situation: String) -> Bool {
        guard recordedSituation == situation else { return true }
        return attempts < maxAttemptsPerSituation
    }

    /// The attempt count to store after a scan: a scan that ADOPTED something made progress, and the situation
    /// it produces is new anyway (the window count moved), so it never needs to spend the budget. Only a
    /// fruitless attempt consumes one.
    static func attemptsAfterScan(previousAttempts: Int, sameSituation: Bool, adopted: Int) -> Int {
        guard adopted == 0 else { return 0 }
        return (sameSituation ? previousAttempts : 0) + 1
    }

    /// How far BELOW an app's lowest known element id a sweep starts. Sized against the measured throughput
    /// (~9.7k ids per 250ms budget) so one attempt still covers a good stretch ABOVE the anchor too.
    static let scanMargin: UInt64 = 4000

    /// **Where to begin the brute-force sweep, which is what actually decides whether it finds anything.** The
    /// scan walks AXUIElementIDs one by one under a wall-clock budget, so it covers a WINDOW of the id space,
    /// never the space — and starting at 0 pointed that window at wherever the app was hours ago. Measured live
    /// (2026-07-30): three attempts covered ids 0..<30000 and adopted nothing, while Finder's window elements
    /// sat at ~31000 — stopping just short, every time, forever.
    ///
    /// A tab's window element is minted when the tab is, so an app's windows cluster in a narrow band, and a
    /// window we already track names that band. Anchor a margin below it (the tabs we are missing are usually
    /// OLDER than the active tab that named them) and the same 250ms lands on them immediately. A `cursor` from
    /// a previous fruitless attempt wins, so retries make progress instead of re-walking what already failed.
    static func scanStart(cursor: UInt64?, lowestKnownId: UInt64?) -> UInt64 {
        if let cursor { return cursor }
        guard let anchor = lowestKnownId else { return 0 }
        return anchor > scanMargin ? anchor - scanMargin : 0
    }

    /// Where the NEXT sweep of this app resumes.
    ///
    /// A sweep stops as soon as it has as many title matches as there are untracked tabs, and the caller then
    /// throws away the ones parked on ANOTHER window of the same app — they are that window's tabs, not the
    /// requester's. Those are not "nothing here": they are a find for a different requester, and advancing
    /// the cursor past them is what made two tab groups of one app permanently uncrossable. Measured, cold
    /// launch, Finder with two 3-tab groups: the sweep for group B's active tab stopped on group A's two
    /// tabs and dropped them, the cursor moved past their ids, and the sweep for group A's active tab then
    /// started ABOVE them and found group B's instead — each requester repeatedly finding only the other's
    /// tabs, six tabs collapsing to the two that were active (measured live).
    ///
    /// So a deferred candidate rewinds the cursor to itself: the very next sweep starts on it, and whichever
    /// requester owns it adopts it. The attempt budget above still bounds the whole thing.
    static func nextCursor(adopted: Int, deferredId: UInt64?, sweptTo: UInt64) -> UInt64 {
        guard adopted == 0 else { return 0 }
        guard let deferredId else { return sweptTo }
        return min(deferredId, sweptTo)
    }
}

/// May the inventory sweep spend a brute-force acquisition on this surface AGAIN
/// (`Applications.refreshWindowsViaWindowServer`)? Sibling of `InactiveTabScanPolicy`, same shape and for the
/// same reason: a bounded, situation-keyed budget over a scan that is expensive and routinely fruitless.
///
/// **The cost this exists to stop, measured live (2026-08-28, a 4-window desktop).** Before inventory
/// acquisition was batched by process, every WindowServer surface started its own wall-clock-capped remote
/// token sweep. Twelve non-window surfaces (Dock, Spotlight, Control Center, WallpaperAgent, BetterDisplay,
/// CopyQ, a Chrome surface, PAH_Extension) therefore occupied the 6-wide pool for ~550ms per show and issued
/// 82,167 of its 82,221 AX round trips. The inventory now shares one traversal across all eligible wids of a
/// process, but a repeatedly unresolved set is still ordinary and still needs a finite retry budget.
///
/// **Only the periodic SWEEP is gated, never an event.** A surface that changes state (order-in, move, focus,
/// Space join) reaches `Applications.discoverWindow` on its own event, and that path uses the cheap
/// `kAXWindows` route with no brute-force at all. So refusing the sweep cannot make a window undiscoverable;
/// it only stops re-asking a question three attempts have already answered.
///
/// The situation is the owning app's window-set version (`Windows.appWindowSetVersion`), because an app
/// gaining or losing a window is what plausibly makes a previously-unreachable element reachable — an app
/// still building its accessibility tree at launch moves it repeatedly, so a genuinely-slow app keeps
/// getting fresh budget rather than being written off on a startup race.
enum SurfaceAcquisitionPolicy {
    static let maxAttemptsPerSituation = 3

    static func shouldAttempt(recordedSituation: UInt64?, attempts: Int, situation: UInt64) -> Bool {
        guard recordedSituation == situation else { return true }
        return attempts < maxAttemptsPerSituation
    }

    /// The attempt count to store after a FAILED acquisition. A success records nothing — the caller drops
    /// the entry entirely, because a surface that acquired is a tracked window and the sweep skips it anyway.
    static func attemptsAfterFailure(previousAttempts: Int, sameSituation: Bool) -> Int {
        (sameSituation ? previousAttempts : 0) + 1
    }

    /// Whether the sweep has now DEFINITIVELY given up on a surface, as opposed to merely being between
    /// tries. `shouldAttempt` answers "ask again?"; this answers "will anything ever describe it, at this
    /// arrangement?", which is the question an admission resting on attention alone has been waiting on.
    ///
    /// Same threshold, deliberately: the give-up point must be the moment the sweep stops paying for the
    /// surface, or a caller could act on a verdict the sweep had not reached yet.
    static func hasGivenUp(attempts: Int) -> Bool {
        attempts >= maxAttemptsPerSituation
    }
}
