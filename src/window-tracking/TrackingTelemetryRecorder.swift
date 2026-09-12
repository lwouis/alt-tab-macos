import Cocoa

/// The live end of `TrackingTelemetryState`: the one place the running app writes into it. Main-thread only,
/// like the model it observes.
///
/// **It observes and never decides.** Every entry point here is called after the decision it describes has
/// already been made — by `AttentionEngine`, by `AxObserverRegistry`, by `WindowAttentionEvents` — so
/// switching telemetry off cannot change what AltTab does.
class TrackingTelemetryRecorder {
    static var state = TrackingTelemetryState()

    private static func now() -> TimeInterval { Date().timeIntervalSince1970 }

    // MARK: attention

    /// One committed attention decision, whoever made it.
    static func attentionCommitted(pid: pid_t, wid: CGWindowID, processGeneration: UInt64?,
                                   source: TrackingProvider, reason: String, status: String) {
        state.recordAttention(pid: pid, wid: wid, processGeneration: processGeneration, source: source,
            reason: reason, status: status, at: now())
    }

    /// A provider named a window and the rules declined it.
    static func attentionRefused(pid: pid_t, wid: CGWindowID, source: TrackingProvider, reason: String) {
        state.recordAttentionRefused(pid: pid, wid: wid, source: source, reason: reason, at: now())
    }

    static func trackingGenerationChanged() {
        state.bumpTrackingGeneration()
    }

    static func processExited(_ pid: pid_t) {
        state.axByPid[pid] = nil
        state.bumpTrackingGeneration()
    }

    // MARK: AX provider health

    static func axProviderHealth(pid: pid_t, state providerState: AxProviderLifecycle,
                                 observerGeneration: UInt64, attempts: Int,
                                 capabilities: [AxNotificationCapability], lastError: AxObserverError?) {
        state.recordAxProvider(pid: pid, state: providerState, observerGeneration: observerGeneration,
            attempts: attempts, capabilities: capabilities, lastError: lastError, at: now())
    }

    static func axProviderFailed(_ process: ProcessGeneration, _ error: AxObserverError) {
        DispatchQueue.main.async {
            state.recordAxProvider(pid: process.pid, state: .unregistered,
                observerGeneration: process.generation, attempts: 1, capabilities: [], lastError: error,
                at: now())
        }
    }

    static func axNotification(_ pid: pid_t) {
        DispatchQueue.main.async { state.recordAxNotification(pid: pid, at: now()) }
    }

    /// A focused-tab notification, recorded with the window it named. **Nothing acts on it**, and the probe
    /// is off by default (`AxNotificationCapability.focusedTabProbeEnabled`): the go/no-go for this channel
    /// is a measurement, and this is the measurement.
    static func axFocusedTabSignal(pid: pid_t, wid: CGWindowID) {
        state.recordAttentionRefused(pid: pid, wid: wid, source: .accessibility, reason: "focusedTabProbe",
            at: now())
    }

    // MARK: the click channel

    static func sessionTapEvent(subtype: Int, pid: pid_t?, wid: CGWindowID?, decoded: Bool) {
        state.recordSessionTapEvent(subtype: subtype, pid: pid, wid: wid, decoded: decoded, at: now())
    }

    /// A window losing key. Counted, never used to name a winner.
    static func attentionResign(pid: pid_t, wid: CGWindowID, subtype: Int) {
        state.recordSessionTapEvent(subtype: subtype, pid: pid, wid: wid, decoded: true, at: now())
    }

    static func attentionTapInvalid(subtype: Int?) {
        DispatchQueue.main.async {
            state.recordSessionTapEvent(subtype: subtype, pid: nil, wid: nil, decoded: false, at: now())
        }
    }

    static func attentionTapLifecycle(installed: Bool, enabled: Bool) {
        onMain { state.recordSessionTapLifecycle(installed: installed, enabled: enabled, at: now()) }
    }

    static func drain() -> [TelemetryRecord] {
        state.drainRecords()
    }

    private static func onMain(_ block: @escaping () -> Void) {
        guard !Thread.isMainThread else { return block() }
        DispatchQueue.main.async(execute: block)
    }
}
