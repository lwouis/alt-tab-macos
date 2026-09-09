import Foundation
import CoreGraphics

/// Names one focus request. Monotonic, so a later request is always the newer intent.
struct FocusGeneration: RawRepresentable, Hashable, Comparable {
    let rawValue: UInt64
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// **Which of several in-flight focus operations may still touch the screen.**
///
/// `Window.focus()` puts the whole activate-key-raise sequence on the shared 4-wide
/// `accessibilityCommandsQueue` and returns without waiting, so two quick alt-tabs are two concurrent
/// operations that start in order and finish in any order. Only `_SLPSSetFrontProcessWithOptions` sets the
/// front process; `makeKeyWindow` and `kAXRaiseAction` only move the z-order. When the older operation's
/// z-order call lands after the newer one's front-switch, the menu bar names the new app while the old app's
/// window sits on top.
///
/// Checking here before each step stops an operation blocked in the 1s AX messaging timeout from spending its
/// #5586 retry budget on a target the user has left. But a z-order call is a post to another process and
/// cannot be recalled, so a bail alone still leaves the screen wrong for an operation that already acted —
/// hence the repair, which re-asserts the current intent. This is that rule as a pure function; `FocusIntents`
/// holds it behind a lock and `Window.focus()` does the actual calls.
struct FocusIntentPolicy {
    /// The process-wide AX messaging timeout (`AXUIElement.globalMessagingTimeoutInSeconds`), which is the
    /// longest a stale operation can plausibly have been blocked. Past it, the front the user is looking at is
    /// more likely one they chose than one AltTab owes them.
    static let repairHorizon: TimeInterval = 1

    struct Intent: Equatable {
        let generation: FocusGeneration
        let wid: CGWindowID
        let pid: pid_t
        let at: TimeInterval
    }

    private var nextGeneration = UInt64(1)
    private(set) var current: Intent?
    /// When each live operation LAST moved the z-order — every such call reports, so the newest stamp is
    /// the one the one-repair rule compares against. Absent means the operation bailed before touching
    /// anything.
    private var reorderedAt = [FocusGeneration: TimeInterval]()
    /// When `current` was last re-asserted, so a second stale operation whose last touch predates it owes
    /// nothing.
    private var repairedAt: TimeInterval?

    /// A focus was asked for. It supersedes whatever was pending.
    mutating func request(wid: CGWindowID, pid: pid_t, now: TimeInterval) -> FocusGeneration {
        let generation = FocusGeneration(rawValue: nextGeneration)
        nextGeneration += 1
        current = Intent(generation: generation, wid: wid, pid: pid, at: now)
        repairedAt = nil
        return generation
    }

    /// A focus that this policy cannot re-assert took over: `Window.focus()` also lands on AltTab's own
    /// window and on a windowless app, and neither is a wid this can front. Pending operations still have to
    /// stop, so they are superseded with nothing to repair to.
    mutating func supersede() {
        current = nil
        repairedAt = nil
    }

    /// May the operation stamped `generation` run its next step?
    func mayProceed(_ generation: FocusGeneration) -> Bool {
        current?.generation == generation
    }

    /// The operation stamped `generation` moved the target in the z-order, by fronting it, making it key, or
    /// raising it. Only such an operation can owe a repair. Called after EVERY one of those calls, not just
    /// the first: the raise can land a second after the front, and the one-repair rule below compares against
    /// when the operation last touched anything.
    mutating func noteReordered(_ generation: FocusGeneration, now: TimeInterval) {
        reorderedAt[generation] = now
    }

    /// The operation stamped `generation`, which was focusing `wid`, is done. Returns the intent to
    /// re-assert, or nil.
    mutating func finish(_ generation: FocusGeneration, wid: CGWindowID, now: TimeInterval) -> Intent? {
        guard let touchedAt = reorderedAt.removeValue(forKey: generation) else { return nil }
        guard let current, current.generation != generation else { return nil }
        guard current.wid != wid else { return nil }
        guard now - current.at <= Self.repairHorizon else { return nil }
        guard touchedAt > (repairedAt ?? -.greatestFiniteMagnitude) else { return nil }
        repairedAt = now
        return current
    }
}

/// The lock-holding shell around `FocusIntentPolicy`, since focus operations run on several queue workers at
/// once. It branches on nothing: every decision is the policy's.
class FocusIntents {
    static let shared = FocusIntents()
    private let lock = NSLock()
    private var policy = FocusIntentPolicy()

    private func withPolicy<T>(_ body: (inout FocusIntentPolicy) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&policy)
    }

    func request(wid: CGWindowID, pid: pid_t) -> FocusGeneration {
        withPolicy { $0.request(wid: wid, pid: pid, now: ProcessInfo.processInfo.systemUptime) }
    }

    func supersede() {
        withPolicy { $0.supersede() }
    }

    func mayProceed(_ generation: FocusGeneration) -> Bool {
        withPolicy { $0.mayProceed(generation) }
    }

    func noteReordered(_ generation: FocusGeneration) {
        withPolicy { $0.noteReordered(generation, now: ProcessInfo.processInfo.systemUptime) }
    }

    func finish(_ generation: FocusGeneration, wid: CGWindowID) -> FocusIntentPolicy.Intent? {
        withPolicy { $0.finish(generation, wid: wid, now: ProcessInfo.processInfo.systemUptime) }
    }
}
