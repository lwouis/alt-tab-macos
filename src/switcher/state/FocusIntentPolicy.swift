import Foundation
import CoreGraphics

/// Names one focus request. Monotonic, so a later request is always the newer intent.
struct FocusGeneration: RawRepresentable, Hashable, Comparable {
    let rawValue: UInt64
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// **Whether a switch that reported success left another app's window over its target** (#6064). See "Verifying
/// the result" in FocusIntentPolicySpecs.md.
struct FocusOutcomePolicy {
    struct Surface {
        let wid: CGWindowID
        let pid: pid_t
        let layer: Int
        let bounds: CGRect
        let alpha: Double
    }

    /// Re-read at the execution boundary: a native click or Cmd-Tab does not create an AltTab generation.
    /// Unknown focus and work delayed more than a second are not grounds for moving another window.
    static func mayRaise(_ targetWid: CGWindowID, _ targetPid: pid_t, frontPid: pid_t?, focusedWid: CGWindowID?,
                         current: Bool, now: TimeInterval, deadline: TimeInterval) -> Bool {
        current && now <= deadline && frontPid == targetPid && focusedWid == targetWid
    }

    static func needsRaise(_ targetWid: CGWindowID, _ targetPid: pid_t, _ frontPid: pid_t?, _ current: Bool,
                           _ surfaces: [Surface]) -> Bool {
        guard current, frontPid == targetPid,
              let targetIndex = surfaces.firstIndex(where: { $0.wid == targetWid }) else { return false }
        let target = surfaces[targetIndex]
        return surfaces[..<targetIndex].contains {
            $0.layer == 0 && $0.alpha > 0 && $0.pid != targetPid && $0.bounds.intersects(target.bounds)
        }
    }
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
    /// **The switch AltTab has asked for and not yet heard about.** Once an operation has run, it reads the
    /// app's focused window back (`readFocusedWindowAfterFocusing`); until that answer lands, what the app
    /// would say about its focused window is about the window the user is LEAVING. Its one reader does not
    /// write the order from the request either: attention refuses to reuse that previous answer on the
    /// activation this focus provokes, and waits for the real one.
    private var awaited: Intent?
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
        awaited = current
        repairedAt = nil
        return generation
    }

    /// The app answered where focus landed. Only the app the pending switch aimed at can answer for it, so a
    /// read about anyone else leaves it waiting.
    mutating func heardBack(pid: pid_t) {
        guard awaited?.pid == pid else { return }
        awaited = nil
    }

    /// Bounded by `repairHorizon`, like a repair and for the same reason: an operation that bailed before its
    /// read never answers at all, and past that horizon what the app says is more likely the user's own doing.
    func awaitedAnswer(now: TimeInterval) -> Intent? {
        guard let awaited, now - awaited.at <= Self.repairHorizon else { return nil }
        return awaited
    }

    /// A focus that this policy cannot re-assert took over: `Window.focus()` also lands on AltTab's own
    /// window and on a windowless app, and neither is a wid this can front. Pending operations still have to
    /// stop, so they are superseded with nothing to repair to.
    mutating func supersede() {
        current = nil
        awaited = nil
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

    func heardBack(pid: pid_t) {
        withPolicy { $0.heardBack(pid: pid) }
    }

    /// Is AltTab still waiting to hear where its own switch into this app landed? See
    /// `FocusIntentPolicy.awaited`.
    func isAwaitingAnswer(from pid: pid_t) -> Bool {
        withPolicy { $0.awaitedAnswer(now: ProcessInfo.processInfo.systemUptime)?.pid == pid }
    }

    #if DEBUG
    private var holdVerificationForQa = false
    private var heldVerificationForQa: (() -> Void)?

    func holdNextVerificationForQa() {
        lock.lock()
        holdVerificationForQa = true
        lock.unlock()
    }

    /// Pose the covering window before the snapshot, without racing the production settle delay.
    func deferVerificationForQa(_ verification: @escaping () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard holdVerificationForQa else { return false }
        holdVerificationForQa = false
        heldVerificationForQa = verification
        return true
    }

    func resumeVerificationForQa() {
        lock.lock()
        let verification = heldVerificationForQa
        heldVerificationForQa = nil
        holdVerificationForQa = false
        lock.unlock()
        verification?()
    }

    private var verificationDelayForQa = 0

    func delayNextVerificationForQa(_ milliseconds: Int) {
        lock.lock()
        verificationDelayForQa = min(800, max(0, milliseconds))
        lock.unlock()
    }

    func consumeVerificationDelayForQa() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let delay = verificationDelayForQa
        verificationDelayForQa = 0
        return delay
    }

    private var refusalArmedForQa = false

    /// **Fault injection (`--qa-refuse-next-focus`): the next focus operation makes none of its OS calls**, as
    /// if macOS had refused the switch. That is the state #6055 is about, a switch AltTab asked for and the OS
    /// never carried out, and no app can be made to refuse one on demand.
    func refuseNextForQa() {
        lock.lock()
        refusalArmedForQa = true
        lock.unlock()
    }

    func consumeRefusalForQa() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let armed = refusalArmedForQa
        refusalArmedForQa = false
        return armed
    }
    #endif
}
