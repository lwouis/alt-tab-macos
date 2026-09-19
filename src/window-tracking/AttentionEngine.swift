import Cocoa

/// **The live shell around `AttentionModel`: the one place the running app decides which window the user is
/// looking at.** Main-thread only, like the model it feeds.
///
/// Three channels reach it, and they are the only three:
/// - **the reducer's input stream** (`dispatched`), for an app activation and the `kAXFocusedWindow` reads
///   (the per-app seed, the bounded read on activation, and the read after AltTab's own switch);
/// - **the app's own accessibility observer** (`axSemanticFocus`), settled per process;
/// - **the click channel** (`directedAttention`), the type-13 tap in `WindowAttentionEvents`.
///
/// A decision that arrives outside the reducer's input stream is committed back into the model here, as
/// `.attentionCommitted`. Nothing else in the app may move the window order — see `AttentionOrderSpecs.md`.
///
/// Deciding is `AttentionModel`'s, translating is `AttentionDriver`'s; what lives here is the impure part:
/// which process generation a pid currently has, the settle timer, and the commit.
class AttentionEngine {
    private static var driver = AttentionDriver()
    private static var generations = [pid_t: UInt64]()

    static var currentUserContext: CurrentUserContext { driver.attention.currentUserContext }

    static func lastAttendedWindow(_ pid: pid_t) -> CGWindowID? {
        driver.attention.lastAttendedWindow(pid)?.wid
    }

    struct DispatchOutcome {
        var attention: (wid: CGWindowID, observed: CGWindowID)? = nil
        var readPid: pid_t? = nil
    }

    /// A dispatch just ran. Returns the window the attention model decided to put in front, for the bridge to
    /// apply inside the same dispatch: deferring it to the next runloop turn would let the switcher draw one
    /// frame with the old order first.
    @discardableResult
    static func dispatched(_ input: ReducerInput) -> DispatchOutcome {
        // Our own commit coming back through the bridge. Deciding on it again would decide against our own
        // output.
        if case .attentionCommitted = input { return DispatchOutcome() }
        if case let .axFocusedWindowRead(pid, wid, viaActivationRead) = input,
           Windows.byWindowId[WindowSurfaceInventory.representativeWid(wid)] == nil {
            withRepresentedWindow(wid, pid: pid, success: { TrackedWindowStateBridge.dispatch(input) }) {
                if viaActivationRead {
                    TrackedWindowStateBridge.dispatch(.axFocusedWindowReadFailed(pid: pid))
                }
            }
            return DispatchOutcome()
        }
        let context = context()
        let outcome = driver.decide(input, context: context)
        guard let target = outcome.wid else { return DispatchOutcome(attention: nil, readPid: outcome.readPid) }
        Windows.promoteAttentionEvidence(outcome.observedWid ?? target)
        let pid = Windows.byWindowId[target]?.application.pid
        TrackingTelemetryRecorder.attentionCommitted(pid: pid ?? 0, wid: target,
            processGeneration: pid.flatMap { generations[$0] }, source: provider(of: input),
            reason: AttentionDriver.reason(for: input), status: outcome.reason)
        return DispatchOutcome(attention: (target, outcome.observedWid ?? target), readPid: outcome.readPid)
    }

    /// Which channel named the window, for telemetry. The reducer's vocabulary says where an input came from,
    /// and that is exactly what a disagreement has to be attributable to — recording every one of them as
    /// `accessibility` would make an activation and an app's own answer indistinguishable in a capture.
    private static func provider(of input: ReducerInput) -> TrackingProvider {
        switch input {
        case .appActivated: return .workspace
        default: return .accessibility
        }
    }

    /// Commit an attention decision that did not arrive as a reducer input — a click, or an app answering
    /// through its own AX observer.
    private static func commit(_ wid: CGWindowID?, observed: CGWindowID? = nil) {
        guard let wid else { return }
        Windows.promoteAttentionEvidence(observed ?? wid)
        TrackedWindowStateBridge.dispatch(.attentionCommitted(wid: wid, observed: observed ?? wid,
            at: ProcessInfo.processInfo.systemUptime))
    }

    // MARK: process identity

    /// A new process generation. A relaunched pid must NOT inherit the previous process's generation, or a
    /// callback from the dead one would look current to every rule keyed on identity.
    static func processStarted(_ pid: pid_t) {
        generations[pid] = (generations[pid] ?? 0) + 1
        TrackingTelemetryRecorder.trackingGenerationChanged()
    }

    static func processExited(_ pid: pid_t) {
        settlePolicy.forget(pid: pid)
        guard let generation = generations[pid] else { return }
        driver.processExited(ProcessGeneration(pid: pid, generation: generation))
        TrackingTelemetryRecorder.processExited(pid)
    }

    /// The generation the tracking pipeline currently associates with this pid. Lazily assigned, so an app
    /// that was already running when AltTab started has an identity too.
    static func generation(of pid: pid_t) -> UInt64 {
        let generation = generations[pid] ?? 1
        generations[pid] = generation
        return generation
    }

    // MARK: the app's own answer

    /// **An app's answers are debounced per process, and only the last one commits.**
    ///
    /// An app raising all its windows really does move its key window to each of them in turn (#5974's
    /// shape, measured at 29ms apart), and the accessibility channel reports every step faithfully. Each step
    /// is a true statement and the run as a whole is one z-order change in which the user went nowhere: the
    /// app puts keys back where they started at the end. Committing each answer scrambled the order.
    ///
    /// The last answer is the right one for both cases — the raise ends where it started, a genuine switch
    /// ends on the new window — so waiting for the run to stop is enough, and nothing has to be guessed in
    /// advance and taken back. A recent hardware event identifies user navigation and keeps the measured
    /// 60ms wait; answers with no recent key or mouse input use 200ms, covering A-11's 150ms programmatic
    /// sequence without adding latency to genuine switches.
    ///
    /// A click is NOT debounced: it names its target exactly, and it is the user's own action. Cmd+` reaches
    /// attention only through this same accessibility channel — the tap is silent for it — and is debounced
    /// with everything else the app says.
    static func axSemanticFocus(pid: pid_t, wid: CGWindowID) {
        guard let offer = driver.offerSemantic(pid: pid, wid: wid, context: context()) else { return }
        let settle = AttentionSettlePolicy.settle(recentInputAge: recentInputAge())
        let armed = settlePolicy.offer(offer, now: ProcessInfo.processInfo.systemUptime, settle: settle)
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) {
            guard let target = settlePolicy.fire(pid: pid, token: armed.token) else { return }
            applySemanticFocus(target)
        }
    }

    private static func recentInputAge() -> TimeInterval {
        [CGEventType.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    /// Which answer survives a run is `AttentionSettlePolicy`'s (a pure triad); the timer is this file's.
    private static var settlePolicy = AttentionSettlePolicy()

    private static func applySemanticFocus(_ offer: SemanticAttentionOffer) {
        let pid = offer.process.pid
        let wid = offer.wid
        let representativeWid = WindowSurfaceInventory.representativeWid(wid)
        guard Windows.byWindowId[representativeWid] != nil else {
            return withRepresentedWindow(wid, pid: pid,
                success: { applySemanticFocus(offer) }) {
                    TrackingTelemetryRecorder.attentionRefused(pid: pid, wid: wid,
                        source: .accessibility, reason: "unrepresented")
                }
        }
        let outcome = driver.decideSemantic(offer, context: context())
        // Only a COMMITTED result is attention. Writing the refused ones as attention too would leave
        // `lastAttention` reporting a window the rules had just declined, which is the opposite of what a
        // reader of that field is asking.
        guard let target = outcome.wid else {
            return TrackingTelemetryRecorder.attentionRefused(pid: pid, wid: wid, source: .accessibility,
                reason: outcome.reason)
        }
        TrackingTelemetryRecorder.attentionCommitted(pid: pid, wid: target,
            processGeneration: generations[pid], source: .accessibility, reason: "axObserver",
            status: outcome.reason)
        commit(target, observed: outcome.observedWid)
    }

    // MARK: the click channel

    /// A click naming its target window (subtype 9; the reactivate and Cmd+` subtypes are decoded but have
    /// never been observed firing). It names both the app and the window at once, so it is the one input
    /// that commits immediately, without waiting for the app to speak. Field 40 has public target-pid
    /// semantics; matching it against a tracked window's cached owner makes the private wid field fail
    /// closed without another WindowServer call.
    static func directedAttention(_ kind: DirectedAttentionKind, pid: pid_t, wid: CGWindowID, subtype: Int) {
        TrackingTelemetryRecorder.sessionTapEvent(subtype: subtype, pid: pid, wid: wid, decoded: true)
        guard Windows.byWindowId[wid] != nil else {
            return withRepresentedWindow(wid, pid: pid, success: {
                applyDirectedAttention(kind, pid: pid, wid: wid)
            }) {
                TrackingTelemetryRecorder.attentionRefused(pid: pid, wid: wid,
                    source: .annotatedSession, reason: "unrepresented")
            }
        }
        applyDirectedAttention(kind, pid: pid, wid: wid)
    }

    private static func applyDirectedAttention(_ kind: DirectedAttentionKind, pid: pid_t, wid: CGWindowID) {
        let representativeWid = WindowSurfaceInventory.representativeWid(wid)
        guard let window = Windows.byWindowId[representativeWid] else {
            return TrackingTelemetryRecorder.attentionRefused(pid: pid, wid: wid,
                source: .annotatedSession, reason: "unrepresented")
        }
        guard window.application.pid == pid else {
            return TrackingTelemetryRecorder.attentionRefused(pid: pid, wid: wid,
                source: .annotatedSession, reason: "pidMismatch")
        }
        Windows.promoteAttentionEvidence(wid)
        let outcome = driver.decideDirected(pid: pid, wid: wid, context: context())
        guard let target = outcome.wid else {
            return TrackingTelemetryRecorder.attentionRefused(pid: pid, wid: wid, source: .annotatedSession,
                reason: outcome.reason)
        }
        TrackingTelemetryRecorder.attentionCommitted(pid: pid, wid: target,
            processGeneration: generations[pid], source: .annotatedSession,
            reason: kind == .commandBacktick ? "type13cycle" : "type13click", status: outcome.reason)
        commit(target, observed: outcome.observedWid)
    }

    /// Attention can beat discovery by several milliseconds. Hold the decision until the WindowServer row has
    /// a model object, or the reducer would correctly reject an unknown wid and no later event would replay it.
    private struct RepresentationWaiter {
        let process: ProcessGeneration
        let success: () -> Void
        let failure: () -> Void
    }

    private static var representationWaiters = [CGWindowID: [RepresentationWaiter]]()

    private static func withRepresentedWindow(_ wid: CGWindowID, pid: pid_t,
                                              success: @escaping () -> Void,
                                              failure: @escaping () -> Void) {
        let knownRepresentative = WindowSurfaceInventory.representativeWid(wid)
        guard Windows.byWindowId[knownRepresentative] == nil else { return success() }
        let process = ProcessGeneration(pid: pid, generation: generation(of: pid))
        let waiter = RepresentationWaiter(process: process, success: success, failure: failure)
        if representationWaiters[wid] != nil {
            representationWaiters[wid]?.append(waiter)
            return
        }
        representationWaiters[wid] = [waiter]
        CGSCallScheduler.run {
            guard let observed = WindowServerQuery.query([wid]).first else {
                return DispatchQueue.main.async {
                    representationWaiters.removeValue(forKey: wid)?.forEach { $0.failure() }
                }
            }
            var rows = [observed]
            if observed.parentWid != 0, let parent = WindowServerQuery.query([observed.parentWid]).first {
                rows.append(parent)
            }
            DispatchQueue.main.async {
                guard let waiters = representationWaiters.removeValue(forKey: wid) else { return }
                let live = waiters.filter { generations[$0.process.pid] == $0.process.generation }
                WindowSurfaceInventory.upsert(rows)
                let matching = live.filter { $0.process.pid == observed.pid }
                live.filter { $0.process.pid != observed.pid }.forEach { $0.failure() }
                guard !matching.isEmpty else { return }
                let representativeWid = WindowSurfaceInventory.representativeWid(wid)
                guard let representative = WindowSurfaceInventory.raw(representativeWid) else {
                    return matching.forEach { $0.failure() }
                }
                if Windows.byWindowId[representativeWid] == nil {
                    guard let app = Applications.findOrCreate(representative.pid, evidence: .attention) else {
                        return matching.forEach { $0.failure() }
                    }
                    WindowServerEvents.subscribe(representativeWid)
                    guard Windows.findOrCreateCandidate(observed, app) != nil else {
                        return matching.forEach { $0.failure() }
                    }
                    Applications.discoverWindow(representativeWid)
                }
                for waiter in matching { waiter.success() }
            }
        }
    }

    /// The facts the model needs but a reducer input does not carry. Closures because the live answers come
    /// from `Applications`/`TabGroups`, and tests supply their own.
    private static func context() -> AttentionDriver.Context {
        AttentionDriver.Context(
            generation: { pid in
                let generation = generations[pid] ?? 1
                generations[pid] = generation
                return ProcessGeneration(pid: pid, generation: generation)
            },
            representativeOf: { wid in
                let physicalRepresentative = WindowSurfaceInventory.representativeWid(wid)
                guard Windows.byWindowId[physicalRepresentative] != nil else { return nil }
                return TabGroups.groupId(of: physicalRepresentative).flatMap { TabGroups.representativeByGroup[$0] }
                    ?? physicalRepresentative
            },
            frontmostPid: { Applications.frontmostPid },
            answerPending: { FocusIntents.shared.isAwaitingAnswer(from: $0) })
    }
}
