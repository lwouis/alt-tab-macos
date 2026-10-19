import Cocoa

/// The live end of `TrackingTelemetryState`: the one place the running app writes into it. Main-thread only,
/// like the model it observes.
///
/// **It observes and never decides.** Every entry point here is called after the decision it describes has
/// already been made — by `AttentionEngine`, by `AxObserverRegistry`, by `WindowAttentionEvents` — so
/// switching telemetry off cannot change what AltTab does. Release builds do: the only readers are the
/// debug-only `--qa-state` and `--qa-telemetry`, so every entry point compiles to an empty body there.
enum TrackingTelemetryRecorder {
    #if DEBUG
    static var state = TrackingTelemetryState()

    private static func now() -> TimeInterval { Date().timeIntervalSince1970 }
    #endif

    // MARK: attention

    /// One committed attention decision, whoever made it.
    static func attentionCommitted(pid: pid_t, wid: CGWindowID, processGeneration: UInt64?,
                                   source: TrackingProvider, reason: String, status: String) {
        #if DEBUG
        state.recordAttention(pid: pid, wid: wid, processGeneration: processGeneration, source: source,
            reason: reason, status: status, at: now())
        #endif
    }

    /// A provider named a window and the rules declined it.
    static func attentionRefused(pid: pid_t, wid: CGWindowID, source: TrackingProvider, reason: String) {
        #if DEBUG
        state.recordAttentionRefused(pid: pid, wid: wid, source: source, reason: reason, at: now())
        #endif
    }

    static func trackingGenerationChanged() {
        #if DEBUG
        state.bumpTrackingGeneration()
        #endif
    }

    static func processExited(_ pid: pid_t) {
        #if DEBUG
        state.axByPid[pid] = nil
        state.bumpTrackingGeneration()
        #endif
    }

    // MARK: AX provider health

    static func axProviderHealth(pid: pid_t, state providerState: AxProviderLifecycle,
                                 observerGeneration: UInt64, attempts: Int,
                                 capabilities: [AxNotificationCapability], lastError: AxObserverError?) {
        #if DEBUG
        state.recordAxProvider(pid: pid, state: providerState, observerGeneration: observerGeneration,
            attempts: attempts, capabilities: capabilities, lastError: lastError, at: now())
        #endif
    }

    static func axProviderFailed(_ process: ProcessGeneration, _ error: AxObserverError) {
        #if DEBUG
        DispatchQueue.main.async {
            state.recordAxProvider(pid: process.pid, state: .unregistered,
                observerGeneration: process.generation, attempts: 1, capabilities: [], lastError: error,
                at: now())
        }
        #endif
    }

    static func axNotification(_ pid: pid_t) {
        #if DEBUG
        DispatchQueue.main.async { state.recordAxNotification(pid: pid, at: now()) }
        #endif
    }

    /// A focused-tab notification, recorded with the window it named. **Nothing acts on it**, and the probe
    /// is off by default (`AxNotificationCapability.focusedTabProbeEnabled`): the go/no-go for this channel
    /// is a measurement, and this is the measurement.
    static func axFocusedTabSignal(pid: pid_t, wid: CGWindowID) {
        #if DEBUG
        state.recordAttentionRefused(pid: pid, wid: wid, source: .accessibility, reason: "focusedTabProbe",
            at: now())
        #endif
    }

    // MARK: the click channel

    static func sessionTapEvent(subtype: Int, pid: pid_t?, wid: CGWindowID?, decoded: Bool) {
        #if DEBUG
        state.recordSessionTapEvent(subtype: subtype, pid: pid, wid: wid, decoded: decoded, at: now())
        #endif
    }

    /// A window losing key. Counted, never used to name a winner.
    static func attentionResign(pid: pid_t, wid: CGWindowID, subtype: Int) {
        #if DEBUG
        state.recordSessionTapEvent(subtype: subtype, pid: pid, wid: wid, decoded: true, at: now())
        #endif
    }

    static func attentionTapInvalid(subtype: Int?) {
        #if DEBUG
        DispatchQueue.main.async {
            state.recordSessionTapEvent(subtype: subtype, pid: nil, wid: nil, decoded: false, at: now())
        }
        #endif
    }

    static func attentionTapLifecycle(installed: Bool, enabled: Bool) {
        #if DEBUG
        onMain { state.recordSessionTapLifecycle(installed: installed, enabled: enabled, at: now()) }
        #endif
    }

    #if DEBUG
    static func drain() -> [TelemetryRecord] {
        state.drainRecords()
    }

    private static func onMain(_ block: @escaping () -> Void) {
        guard !Thread.isMainThread else { return block() }
        DispatchQueue.main.async(execute: block)
    }
    #endif
}
