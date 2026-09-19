import Foundation

/// **Attention is two facts, not one, and they come from different places.**
///
/// Which app has attention comes from `NSWorkspace` and from the click's pid. Which window inside that app
/// normally comes from that app, over Accessibility. Modelled separately, a late answer from app X is only a
/// fact about X; it cannot compete with whichever process is now in front.
///
///     frontProcess                <- NSWorkspace, and the click's pid
///     focusedWindow[process]      <- that app's own answer, the click's wid, one bounded read
///     the visible front           == focusedWindow[frontProcess]
///
/// The design is measured rather than reasoned: twelve focus scenarios with all four signal sources on one
/// clock. What it settled, in the two lines
/// that shape this file: **Accessibility names the window in 10 of 12 scenarios and is the earliest
/// window-naming source in 8**, including the Space follow-up, so it is the primary rather than the fallback;
/// and **the WindowServer is never the best source in any scenario where anything else speaks, and has no
/// exclusive scenario at all**, so 808/815 are not attention inputs. Physical lifecycle may invalidate a
/// cached wid, but it can never name attention.
///
/// `AttentionDriver` feeds it, and its `.front` decisions are the only attention-driven writes to the order.
enum AttentionModel {
    static func reduce(_ state: inout AttentionModelState,
                       _ input: AttentionModelInput) -> AttentionModelDecision {
        switch input {
        case let .processStarted(process):
            if let previous = state.liveGenerations[process.pid], previous != process { forget(&state, previous) }
            state.liveGenerations[process.pid] = process
            return .none
        case let .processExited(process):
            guard isLive(state, process) else { return .ignored(.staleGeneration) }
            state.liveGenerations[process.pid] = nil
            forget(&state, process)
            return .none
        case let .windowInvalidated(wid):
            state.focusedWindow = state.focusedWindow.filter {
                $0.value.observed.wid != wid && $0.value.target.wid != wid
            }
            return .none
        case let .frontProcessChanged(process):
            guard isLive(state, process) else { return .ignored(.staleGeneration) }
            let before = state.visibleFront
            state.frontProcess = process
            state.awaitingAnswer.remove(process)
            // R6, one bounded read, one trigger. An app activation names NO window from any source when the
            // app's focused window did not change — measured, and it is the one hole nothing else fills.
            guard let fact = state.focusedWindow[process] else { return .readFocusedWindow(process) }
            guard fact.target != before else { return .none }
            return .front(fact.target)
        case let .frontProcessChangedAwaitingAnswer(process):
            // R7, an answer already on its way beats the one already here. The app's stored fact is its
            // answer from BEFORE the switch, so fronting it here walks the window the user is leaving to the
            // top of the order and leaves it one tile from the next summon's default pick. No read either:
            // the one that will answer this is already out.
            guard isLive(state, process) else { return .ignored(.staleGeneration) }
            state.frontProcess = process
            state.awaitingAnswer.insert(process)
            return .none
        case let .named(namer, observed, representative, sequence):
            guard isLive(state, observed.process) else { return .ignored(.staleGeneration) }
            guard let target = eligible(observed, representative) else { return .ignored(.ineligible) }
            let process = target.process
            // R1, per-process monotonicity, and nothing else is compared. Sequences are allocated on arrival,
            // so this only ever bites the one answer that carries an OLDER sequence than its arrival: the
            // bounded read, which is issued at the activation and lands after whatever the app said in the
            // meantime. Across processes nothing is compared at all.
            if let existing = state.focusedWindow[process], sequence < existing.sequence {
                return .ignored(.staleSequence)
            }
            let before = state.visibleFront
            // The activation this answers went by without moving the front, so the move is owed here even
            // when the answer names the window the app had already stored: unmoved, the order still has the
            // app the user LEFT on top.
            let owesFront = state.awaitingAnswer.remove(process) != nil
            state.focusedWindow[process] = FocusedWindowFact(observed: observed, target: target,
                sequence: sequence)
            if namer.carriesTheFrontProcess { state.frontProcess = process }
            // R2, every namer writes a fact, never a command. A late answer from an app the user has already
            // left updates that app's entry and moves nothing.
            guard state.frontProcess == process, owesFront || target != before else { return .recorded(target) }
            return .front(target)
        case let .focusedWindowUnknown(process):
            // R5, unknown is a value: do not move the front for this process. A read that came back empty is
            // not evidence against whatever the app said before it, so an existing fact stands.
            guard isLive(state, process) else { return .ignored(.staleGeneration) }
            return .none
        }
    }

    private static func forget(_ state: inout AttentionModelState, _ process: ProcessGeneration) {
        state.focusedWindow[process] = nil
        state.awaitingAnswer.remove(process)
        if state.frontProcess == process { state.frontProcess = nil }
    }

    /// Child, sheet, panel and utility targets enter as the window that stands for them in the switcher. A
    /// missing or cross-process representative is refused rather than guessed.
    private static func eligible(_ observed: WindowIdentity,
                                 _ representative: WindowIdentity?) -> WindowIdentity? {
        guard let representative, representative.process == observed.process else { return nil }
        return representative
    }

    private static func isLive(_ state: AttentionModelState, _ process: ProcessGeneration) -> Bool {
        state.liveGenerations[process.pid] == process
    }
}

struct AttentionModelState: Equatable {
    var liveGenerations = [Int32: ProcessGeneration]()
    var frontProcess: ProcessGeneration?
    var focusedWindow = [ProcessGeneration: FocusedWindowFact]()
    /// Processes that took the front while an answer about their focused window was already on its way, so
    /// the front was not moved for them. The answer owes that move, whichever window it names.
    var awaitingAnswer = Set<ProcessGeneration>()

    /// **Nil means "nobody has said", not "nothing is focused".** The decision stream is the API: a consumer
    /// moves the order when it is handed `.front`, and does nothing otherwise. Writing this value through
    /// would clear the front every time an app is activated before it has answered, which is exactly the
    /// guess the design refuses to make.
    var visibleFront: WindowIdentity? { frontProcess.flatMap { focusedWindow[$0]?.target } }

    var currentUserContext: CurrentUserContext {
        guard let frontProcess else { return .unknown }
        guard let visibleFront else { return .application(frontProcess) }
        return .window(visibleFront)
    }

    func lastAttendedWindow(_ pid: Int32) -> WindowIdentity? {
        guard let process = liveGenerations[pid] else { return nil }
        return focusedWindow[process]?.target
    }
}

/// The strongest current statement the attention model can make for downstream UX. App-only is distinct
/// from unknown, and neither is treated as evidence that the user is looking at no window.
enum CurrentUserContext: Equatable {
    case unknown
    case application(ProcessGeneration)
    case window(WindowIdentity)

    var pid: Int32? {
        switch self {
        case .unknown: return nil
        case .application(let process): return process.pid
        case .window(let window): return window.process.pid
        }
    }

    var wid: UInt32? {
        guard case .window(let window) = self else { return nil }
        return window.wid
    }
}

/// One app's answer about one of its own windows, with the sequence that answer arrived (or, for the bounded
/// read, was issued) under.
struct FocusedWindowFact: Equatable {
    var observed: WindowIdentity
    var target: WindowIdentity
    var sequence: IngressSequence
}

/// Who named the window. The click carries the front process with it, because the user's action names the app
/// and the window in the same breath; the other two are the app talking about itself.
enum AttentionNamer: Equatable {
    /// the type-13 click channel — the earliest source there is, and the only one that survives a wedged app
    case click
    /// the app's own accessibility answer about which of its windows is focused
    case app
    /// the one bounded `kAXFocusedWindow` read fired on an activation that named no window
    case activationRead

    var carriesTheFrontProcess: Bool { self == .click }
}

enum AttentionModelInput: Equatable {
    case processStarted(ProcessGeneration)
    case processExited(ProcessGeneration)
    /// Lifecycle invalidation removes a cached answer; it does not name attention or move the front.
    case windowInvalidated(UInt32)
    /// `NSWorkspace` named an app. It names no window, and that is the whole point of the split.
    case frontProcessChanged(ProcessGeneration)
    /// The same, for the activation provoked by a switch AltTab asked for and has not heard back about. The
    /// app's stored answer predates that switch, so it names nothing here either — and this time not even a
    /// read, because the answer is already out.
    case frontProcessChangedAwaitingAnswer(ProcessGeneration)
    case named(AttentionNamer, observed: WindowIdentity, representative: WindowIdentity?, IngressSequence)
    /// the bounded read came back with no window
    case focusedWindowUnknown(ProcessGeneration)
}

enum AttentionModelDecision: Equatable {
    /// the visible front moved to this window
    case front(WindowIdentity)
    /// a fact landed, and nothing the user can see moved: either for an app that is not in front, or naming
    /// the window that already held the front
    case recorded(WindowIdentity)
    /// this process took the front and nobody has ever named a window for it. Fire exactly one
    /// `kAXFocusedWindow` read, off-main, with a 250 ms messaging timeout.
    case readFocusedWindow(ProcessGeneration)
    case ignored(AttentionIgnoreReason)
    case none
}

enum AttentionIgnoreReason: Equatable {
    case staleGeneration
    case staleSequence
    case ineligible
}
