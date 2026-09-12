import Foundation

/// One indirect (trackpad) touch, reduced to what gesture detection needs. `TrackpadEvents` maps
/// `NSTouch` to this on the tap thread; everything below this line is value types, so the trigger
/// state machine is unit-testable without a trackpad.
struct GestureTouch {
    /// Identifies the touch *while it is down*, and only then. From `NSTouch.h`: "while touch
    /// identities may be re-used, they are unique during the life of the touch". So this must never
    /// be treated as recognising a finger across gestures — see `GestureTracker.prune`.
    let id: String
    /// nil when `normalizedPosition` was unreadable; Universal Control forwards such touches (#5499).
    let position: NSPoint?
    /// `phase == .began`: the OS saying the touch is new. Sounder than inferring newness from whether
    /// we happen to hold a start position for `id`, which a recycled identity makes a lie.
    let isBegan: Bool
}

/// Where each finger of the current gesture started, so travelled distance can be measured.
class GestureTracker {
    private var startPositions = [String: NSPoint]()

    var isEmpty: Bool { startPositions.isEmpty }

    /// Forget fingers that have left the trackpad. This is correctness, not tidiness: identities are
    /// recycled, so a start position left behind by a lifted finger gets picked up by an unrelated
    /// finger in a later gesture, and the distance measured from it is meaningless — typically large,
    /// and typically off-axis, which is how it used to latch `GestureTriggerKernel`'s
    /// `swipeStillPossible` off for good (#5137).
    ///
    /// `ids` must be every touch still DOWN, including `.stationary` ones. Pruning to the touches
    /// being measured instead would drop the start position of a finger that paused for one event,
    /// which re-bases the gesture and makes the swipe need extra travel.
    func prune(toTouchesDown ids: Set<String>) {
        if startPositions.contains(where: { !ids.contains($0.key) }) {
            startPositions = startPositions.filter { ids.contains($0.key) }
        }
    }

    /// True when this frame begins a gesture, and then re-bases every start position. A frame begins
    /// one if any touch reports `.began`, or if we hold no start position for it — the latter covers a
    /// finger joining a gesture already under way.
    @discardableResult
    func isNewGesture(_ touches: [GestureTouch]) -> Bool {
        guard touches.contains(where: { $0.isBegan || startPositions[$0.id] == nil }) else { return false }
        for touch in touches {
            if let position = touch.position { startPositions[touch.id] = position }
        }
        return true
    }

    /// Per-touch travel since the gesture began. Touches with no readable position, and touches with
    /// no start position, are skipped, so this can be shorter than `touches` — and empty.
    func distances(_ touches: [GestureTouch]) -> [NSPoint] {
        touches.compactMap { touch in
            guard let position = touch.position, let start = startPositions[touch.id] else { return nil }
            return NSPoint(x: position.x - start.x, y: position.y - start.y)
        }
    }

    func averageDistance(_ touches: [GestureTouch]) -> NSPoint {
        let deltas = distances(touches)
        guard !deltas.isEmpty else { return .zero }
        let total = deltas.reduce(NSPoint.zero) { NSPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return NSPoint(x: total.x / CGFloat(deltas.count), y: total.y / CGFloat(deltas.count))
    }

    func reset() {
        startPositions.removeAll(keepingCapacity: true)
    }

    /// Move the start line to where the fingers are now, on one axis only. Lets a held gesture keep
    /// stepping the selection: each further swipe measures from the last step, not from touchdown.
    func rebase(_ touches: [GestureTouch], horizontally: Bool) {
        for touch in touches {
            guard let position = touch.position else { continue }
            if horizontally {
                startPositions[touch.id]?.x = position.x
            } else {
                startPositions[touch.id]?.y = position.y
            }
        }
    }
}

/// Pure state machine for the trackpad gesture *trigger*: the decision, taken while the switcher is
/// NOT open, of whether the fingers on the trackpad just performed AltTab's summon swipe.
///
/// Extracted from `TrackpadEvents` because #5137 ("the gesture stops working until AltTab is
/// relaunched") was a reset-path bug in here, of a kind no live pass can catch: the trigger has
/// state that outlives a gesture, and two pieces of it could keep a value that made every later
/// swipe fail. `TrackpadEvents` stays the adapter — event taps, `NSTouch` mapping, haptics, showing
/// the UI — and owns one instance of this.
///
/// Distances are fractions of the trackpad surface, as `NSTouch.normalizedPosition` reports them.
final class GestureTriggerKernel {
    /// Travel required before we trigger. macOS makes its own 3-finger Space swipe wait for a small
    /// distance too; we imitate that.
    static let minSwipeDistance: CGFloat = 0.015
    /// Travelling this far across the gesture's axis cancels the swipe until the fingers are raised,
    /// again imitating the native Space swipe.
    static let maxSwipeDistanceInWrongDirection: CGFloat = 0.1

    /// One gesture event, already reduced to values by `TrackpadEvents`.
    struct Frame {
        /// Touches in `.began`, `.moved` or `.stationary` — i.e. fingers on the trackpad.
        let fingersDown: Int
        /// The subset being measured: `.began` or `.moved`, and not resting. A stationary finger is
        /// excluded on purpose; `isResting` never reports true on macOS, and dropping stationary
        /// touches is the closest we can get to ignoring a resting thumb or palm.
        let activeTouches: [GestureTouch]
        /// Identities of every touch still down, for pruning. Superset of `activeTouches`' ids.
        let touchesDownIds: Set<String>
        /// 3 or 4, per the user's preference.
        let requiredFingers: Int
        /// Whether the configured gesture is horizontal; decides which axis is the swipe's.
        let horizontal: Bool
    }

    enum Outcome: Equatable {
        case ignore
        /// Summon the switcher, and swallow this event so the focused app doesn't also act on it.
        case trigger
    }

    /// The most fingers seen down while the trigger swipe was being performed. Read once the switcher
    /// is open, to tell "the user lifted the fingers that did the swipe" (focus on release) from "the
    /// user lifted a thumb they happened to be resting". Cleared when the gesture ends.
    private(set) var maxFingersDownDuringTrigger = 0

    private let triggerTracker = GestureTracker()
    private let nonFreshTracker = GestureTracker()
    /// The user already spent this finger-down session on another gesture, so we must not also read it
    /// as ours. Only *more* fingers than we want count (a system swipe): that is what prevents a 4→3
    /// trigger. Fewer fingers deliberately do not — a 2-finger scroll followed by a third finger still
    /// triggers. Widening this to any non-matching count was tried and reverted: it drags in fingers
    /// arriving one by one and fingers pausing mid-swipe, which needs per-configuration baselines to
    /// stay safe, and that complexity buys less than it costs.
    private var userHasDoneAnotherGesture = false
    /// False once the fingers wandered too far across the swipe's axis. The entry guard in
    /// `swipeCompleted` reads this before anything can recompute it, so it is a latch by design, and
    /// its scope is the whole finger-down session: only raising the fingers clears it. A finger merely
    /// pausing must NOT, or a long off-axis wander is forgiven mid-gesture and the swipe that follows
    /// triggers (see `rebaseTrigger` vs `resetTrigger`).
    private var swipeStillPossible = true

    /// Feed one gesture event. Only call this while the switcher is closed; once it is open,
    /// `TrackpadEvents` routes to the navigation detector instead and this state is left alone.
    func handle(_ frame: Frame) -> Outcome {
        triggerTracker.prune(toTouchesDown: frame.touchesDownIds)
        nonFreshTracker.prune(toTouchesDown: frame.touchesDownIds)
        // At most one finger left: that is pointer mode, not a gesture, so the gesture is over and all
        // of its state goes with it. Clearing only `userHasDoneAnotherGesture` here was #5137 —
        // `swipeStillPossible` gates its own recomputation, so once one swipe wandered off-axis
        // nothing ever set it back and the trigger stayed dead until AltTab was relaunched. A
        // 2-finger scroll happened to clear it via the `requiredFingers` mismatch below, which is why
        // the symptom came and went.
        if frame.fingersDown <= 1 {
            endGesture()
            return .ignore
        }
        if hasDoneAnotherGesture(frame) { return .ignore }
        if frame.activeTouches.count != frame.requiredFingers {
            // Only the start positions go: a finger arriving or pausing means the next measurement has
            // to start from here, but it is not a fresh gesture and must not forgive an off-axis wander.
            rebaseTrigger()
            return .ignore
        }
        return swipeCompleted(frame) ? .trigger : .ignore
    }

    /// Drop everything. Called when the switcher session ends, so the next gesture starts clean
    /// whatever state the fingers were left in.
    func reset() {
        resetTrigger()
        nonFreshTracker.reset()
        userHasDoneAnotherGesture = false
        maxFingersDownDuringTrigger = 0
    }

    /// `reset()`, but silent and free when there is nothing to reset — `handle` reaches this on every
    /// event while a single finger rests on the trackpad, which is most events.
    private func endGesture() {
        guard !isClean else { return }
        let wasPossible = swipeStillPossible
        Logger.debug { "gesture over; clearing trigger state (swipeStillPossible was \(wasPossible))" }
        reset()
    }

    private var isClean: Bool {
        triggerTracker.isEmpty && nonFreshTracker.isEmpty && !userHasDoneAnotherGesture
            && swipeStillPossible && maxFingersDownDuringTrigger == 0
    }

    /// Forget where the fingers were, but keep the verdict on this finger-down session.
    private func rebaseTrigger() {
        triggerTracker.reset()
    }

    private func resetTrigger() {
        rebaseTrigger()
        swipeStillPossible = true
    }

    /// Once the user has used this finger-down session for another gesture, the session is ours no
    /// more, until the fingers are raised. See `userHasDoneAnotherGesture` for why only extra fingers
    /// count here.
    private func hasDoneAnotherGesture(_ frame: Frame) -> Bool {
        guard !userHasDoneAnotherGesture else { return true }
        let count = frame.activeTouches.count
        let isNew = nonFreshTracker.isNewGesture(frame.activeTouches)
        guard count > frame.requiredFingers, !isNew else { return false }
        let distances = nonFreshTracker.distances(frame.activeTouches)
        userHasDoneAnotherGesture = distances.contains {
            abs($0.x) >= Self.minSwipeDistance || abs($0.y) >= Self.minSwipeDistance
        }
        if userHasDoneAnotherGesture {
            Logger.debug { "\(count) travelling fingers claimed this session (we want \(frame.requiredFingers))" }
        }
        return userHasDoneAnotherGesture
    }

    private func swipeCompleted(_ frame: Frame) -> Bool {
        guard swipeStillPossible, !triggerTracker.isNewGesture(frame.activeTouches) else { return false }
        maxFingersDownDuringTrigger = max(maxFingersDownDuringTrigger, frame.fingersDown)
        let distances = triggerTracker.distances(frame.activeTouches)
        // Every touch's position was unreadable (see `GestureTouch.position`). With no distances the
        // loop below falls straight through to triggering, so stop here.
        guard !distances.isEmpty else { return false }
        for distance in distances {
            let (absX, absY) = (abs(distance.x), abs(distance.y))
            let onAxis = frame.horizontal ? absX : absY
            let offAxis = frame.horizontal ? absY : absX
            if offAxis >= Self.maxSwipeDistanceInWrongDirection {
                swipeStillPossible = false
                Logger.debug { "swipe cancelled: travelled \(offAxis) across its axis" }
                return false
            }
            guard onAxis >= Self.minSwipeDistance else { return false }
        }
        resetTrigger()
        return true
    }
}
