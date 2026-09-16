import Cocoa
import ShortcutRecorder

/// Pairs delayed Carbon hotkeys with the modifier release that followed their physical key press.
///
/// Carbon delivers registered hotkeys on the main run loop, while the session event tap sees the physical
/// input on its own thread. When main stalls, two complete Alt-Tab gestures can accumulate there and the
/// two sources may drain in either order. Live modifier state cannot separate them: by then it belongs to a
/// later gesture. Nor can Carbon's `EventRef` timestamp them: `GetEventTime` reports dequeue time for a
/// delayed hotkey, not when the key was pressed (measured by F-08).
///
/// The passive event tap therefore records just enough source order to answer the exact question Carbon
/// cannot: did the hold modifier go up after THIS shortcut key-down and before the NEXT switch shortcut?
/// It observes keyDown but never handles or suppresses one; the active HID keyDown tap remains disabled
/// outside a switcher session, preserving the input-method isolation required by #5766.
///
/// Invariant: the log holds exactly the key-downs Carbon will report, one per physical press. A claim takes
/// the OLDEST unclaimed key-down, so one entry Carbon never reports shifts every later pairing onto a stale
/// press, and its answer is then about the wrong gesture. Three things keep the invariant:
/// - Only the registered switching chords are recorded (`setSwitchingChords`). Every other key-down is the
///   user typing, which Carbon never reports; recording it kept the key codes of shifted typing in memory
///   for nothing and let a burst of it evict the one entry a delayed hotkey needed.
/// - Auto-repeats are not recorded. Carbon stays silent through a held key's repeats (measured: a 3s ⌥⇥
///   hold posted 30 repeat key-downs and fired one hotkey; `KeyRepeatTimer` exists because of that).
/// - Registration changes reset the log, so a key-down Carbon could not report is never claimed after
///   re-registration.
/// Carbon can also overtake the tap's key-down callback. A claim made while its modifiers are physically
/// held consumes that late callback instead of leaving it available to poison the next gesture.
enum ModifierReleaseLog {
    struct Chord: Hashable {
        let keyCode: UInt32
        let modifiers: CarbonModifierFlags

        /// Caps Lock is dropped on both sides: a Carbon hotkey fires with it on, while the tap reports it
        /// in the event's flags, and the two chords would otherwise never match while it is lit.
        init(keyCode: UInt32, modifiers: CarbonModifierFlags) {
            self.keyCode = keyCode
            self.modifiers = modifiers.cleaned() & ~UInt32(alphaLock)
        }
    }

    private enum Input {
        case flags(sequence: UInt64, modifiers: CarbonModifierFlags)
        case keyDown(sequence: UInt64, chord: Chord, claimed: Bool)

        var sequence: UInt64 {
            switch self {
                case let .flags(sequence, _), let .keyDown(sequence, _, _): return sequence
            }
        }
    }

    private static let capacity = 64
    private static var inputs = [Input]()
    private static var sequence: UInt64 = 0
    private static var claimsAwaitingKeyDown = [Chord: Int]()
    private static var latestModifiers: CarbonModifierFlags = 0
    /// The chords Carbon can report: every registered `nextWindowShortcut`.
    private static var switchingChords = Set<Chord>()
    private static let lock = NSLock()

    /// Registration changed. The log is reset with it: a key-down recorded under the previous registration
    /// is one Carbon may never report.
    static func setSwitchingChords(_ chords: Set<Chord>) {
        lock.lock()
        defer { lock.unlock() }
        switchingChords = chords
        resetLocked()
    }

    static func record(_ flags: NSEvent.ModifierFlags) {
        let modifiers = cocoaToCarbonFlags(flags).cleaned()
        lock.lock()
        defer { lock.unlock() }
        latestModifiers = modifiers
        appendLocked(.flags(sequence: nextSequence(), modifiers: modifiers))
        if modifiers == 0 { claimsAwaitingKeyDown.removeAll(keepingCapacity: true) }
    }

    static func recordKeyDown(_ keyCode: UInt32, _ flags: NSEvent.ModifierFlags, isARepeat: Bool = false) {
        guard !isARepeat else { return }
        let chord = Chord(keyCode: keyCode, modifiers: cocoaToCarbonFlags(flags))
        lock.lock()
        defer { lock.unlock() }
        guard switchingChords.contains(chord) else { return }
        if let count = claimsAwaitingKeyDown[chord], count > 0 {
            claimsAwaitingKeyDown[chord] = count == 1 ? nil : count - 1
            return
        }
        appendLocked(.keyDown(sequence: nextSequence(), chord: chord, claimed: false))
    }

    /// Claims the oldest physical key-down matching this Carbon hotkey. A release after a later switch key
    /// belongs to that later selection, so the search stops at the next recorded key-down, every one of
    /// which is a switching chord. This is what keeps two Tab taps under one held Option as one session
    /// while splitting two Option-Tab pairs.
    static func claimRelease(after chord: Chord, holdModifiers: CarbonModifierFlags) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = inputs.firstIndex(where: { input in
            if case let .keyDown(_, candidate, claimed) = input { return !claimed && candidate == chord }
            return false
        }), case let .keyDown(keySequence, _, _) = inputs[index] else {
            if latestModifiers == (latestModifiers | chord.modifiers) {
                claimsAwaitingKeyDown[chord, default: 0] += 1
            }
            return false
        }
        inputs[index] = .keyDown(sequence: keySequence, chord: chord, claimed: true)
        let nextKeySequence = inputs.dropFirst(index + 1).first(where: { input in
            if case .keyDown = input { return true }
            return false
        })?.sequence ?? UInt64.max
        let required = holdModifiers.cleaned()
        return inputs.dropFirst(index + 1).contains { input in
            guard input.sequence < nextKeySequence, case let .flags(_, modifiers) = input else { return false }
            return modifiers != (modifiers | required)
        }
    }

    private static func nextSequence() -> UInt64 {
        sequence &+= 1
        return sequence
    }

    /// Consecutive flags entries fold into one carrying the AND of their modifiers. A claim only asks whether
    /// SOME entry between two key-downs lacked a hold modifier, and a bit is missing from the AND exactly
    /// when it is missing from some entry, so nothing a claim can read changes. What it buys is that typing
    /// during a stall (two flags changes per capital letter) no longer grows the log or evicts the one
    /// key-down a delayed hotkey needs.
    private static func appendLocked(_ input: Input) {
        if case let .flags(_, modifiers) = input, case let .flags(sequence, previous)? = inputs.last {
            inputs[inputs.count - 1] = .flags(sequence: sequence, modifiers: previous & modifiers)
            return
        }
        inputs.append(input)
        if inputs.count > capacity { inputs.removeFirst(inputs.count - capacity) }
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        resetLocked()
    }

    private static func resetLocked() {
        inputs.removeAll(keepingCapacity: true)
        claimsAwaitingKeyDown.removeAll(keepingCapacity: true)
        sequence = 0
        latestModifiers = 0
    }
}
