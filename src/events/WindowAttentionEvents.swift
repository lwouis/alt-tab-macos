import Cocoa

/// **The one channel that names the window the user just clicked, before the app has reacted to anything.**
///
/// When a click activates a window, AppKit posts a type-13 `CGSEvent` carrying the target window id. Measured
/// on macOS 26.6: it arrives ~66ms after the click and **12ms before the WindowServer changes any key
/// appearance** — earlier than anyone else in the system knows, and it works even when the clicked app is
/// wedged and never takes key at all.
///
/// **It covers exactly one scenario: the cross-app click, subtype 9.** Driving all twelve focus scenarios
/// with the mask removed entirely (no record-length gate, no subtype filter, every click hit-tested first)
/// found no acquire subtype of any value for an in-app click or for Cmd+`, on two different apps — only the
/// 22/23 resign pair afterwards. Five minutes of ordinary use produced 17 type-13 events: 2 x sub 9, 7 x sub
/// 22, 8 x sub 23. So `clickReactivate` and `commandBacktick` are decoded but have never been observed
/// firing. Treat this channel as the click channel and nothing more; anything else that needs naming has to
/// come from the app's own Accessibility answer.
///
/// Three placements were compared with the same mask; only the annotated session tap sees events addressed to
/// other processes:
///
/// | placement | sees another app's appearance events |
/// |---|---|
/// | `kCGSessionEventTap` | no |
/// | `kCGAnnotatedSessionEventTap` | yes |
/// | `CGEventTapCreateForPid` | yes, but one tap per app |
///
/// **Listen-only, and masked to type 13 alone.** It is not in the HID stream and it absorbs nothing, so it
/// cannot gate the cursor the way #5911's active tap did. It reads three integer fields and forwards them;
/// keyboard events carry `field 51 = 0` and were verified to expose no key content through this accessor.
///
/// **A stalled app delays this tap only when it is mid-activation.** Eight trials, one variable at a time:
/// an app that simply wedges delays nothing but Accessibility — the tap lands in 1-25 ms
/// and the WindowServer in 30-41 ms while AX waits out the whole stall. But an app that wedges while holding
/// an outstanding key-window request defers **every** source together: tap, 808, NSWorkspace and AX all land
/// at the unwedge, within ~14 ms of each other. `makeKeyWindow` with no raise behaves the same as
/// `makeKeyAndOrderFront`, so it is the focus request and not the ordering. This is reassuring rather than
/// alarming: there is no regime in which the tap goes quiet while another source stays fast, so no rule may
/// be written on "the tap arrived first, therefore nothing else can be pending".
///
/// **This is a prediction, not a transcription.** The acquire side is the app's own private RPC and the
/// WindowServer does not echo it, so nothing confirms the winner. A click on a hung app fires subtype 9 for a
/// window that then never takes key — and stamping it anyway is the deliberate product decision: the
/// WindowServer has already raised that window and made its process frontmost, which is what the user just
/// asked for. Correction, when the app disagrees, is one transaction being corrected rather than two.
///
/// Results reach the model through `AttentionDriver`: a click names both the app and the window at once.
class WindowAttentionEvents {
    /// CGS field ids. Not in `CGEventTypes.h`, but `CGEventGetIntegerValueField` is public API and these are
    /// the ids its private cousin `SLEventGetEventRecord` reads the same values from — cross-checked field by
    /// field against the raw `SLSEventRecord` on macOS 26.6.
    private struct Fields {
        let targetPid: CGEventField
        let windowId: CGEventField
        let recordLength: CGEventField
        let subtype: CGEventField

        init?() {
            guard let targetPid = CGEventField(rawValue: 40),
                  let windowId = CGEventField(rawValue: 51),
                  let recordLength = CGEventField(rawValue: 50),
                  let subtype = CGEventField(rawValue: 83) else { return nil }
            self.targetPid = targetPid
            self.windowId = windowId
            self.recordLength = recordLength
            self.subtype = subtype
        }
    }
    private static let fields = Fields()
    /// AppKit-defined events. `NSEvent.EventType.appKitDefined` is 13; the mask is that bit alone.
    private static let appKitDefinedType = 13
    /// the record length every measured type-13 event carried, used as the layout probe
    private static let expectedRecordLength = 248

    private static var eventTap: CFMachPort?
    /// Independent kill switch: a provider this experimental must be switchable off without touching the
    /// others.
    static var enabled = true

    static func observe() {
        guard enabled else { return }
        guard fields != nil else {
            Logger.debug { "attention tap: event fields unsupported" }
            TrackingTelemetryRecorder.attentionTapLifecycle(installed: false, enabled: false)
            return
        }
        eventTap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << appKitDefinedType),
            callback: handler,
            userInfo: nil)
        guard let eventTap else {
            Logger.debug { "attention tap: not installed" }
            TrackingTelemetryRecorder.attentionTapLifecycle(installed: false, enabled: false)
            return
        }
        guard let runLoop = BackgroundWork.keyboardAndMouseAndTrackpadEventsThread?.runLoop else {
            Logger.debug { "attention tap: no runloop to install on" }
            return
        }
        CFRunLoopAddSource(runLoop, CFMachPortCreateRunLoopSource(nil, eventTap, 0), .commonModes)
        TrackingTelemetryRecorder.attentionTapLifecycle(installed: true, enabled: true)
    }

    static func reEnableTapIfNeeded() {
        if CGEvent.reEnableTapIfNeeded(eventTap, wanted: enabled) {
            TrackingTelemetryRecorder.attentionTapLifecycle(installed: true, enabled: true)
            Logger.warning { "attention tap re-enabled" }
        }
    }

    private static let handler: CGEventTapCallBack = { _, type, event, _ in
        guard type.rawValue == UInt32(appKitDefinedType) else { return Unmanaged.passUnretained(event) }
        decode(event)
        return Unmanaged.passUnretained(event)
    }

    /// **Fails closed on an unknown layout.** If the record length is not what every measurement produced,
    /// the field ids may mean something else on this OS build and a wid read from them would be a guess. The
    /// event is counted as invalid and nothing is stamped.
    private static func decode(_ event: CGEvent) {
        guard let fields else { return }
        let length = event.getIntegerValueField(fields.recordLength)
        guard length == expectedRecordLength else { return invalid(nil) }
        let subtype = Int(event.getIntegerValueField(fields.subtype))
        guard let kind = AttentionSubtype(rawValue: subtype) else { return other(subtype) }
        let wid = CGWindowID(truncatingIfNeeded: event.getIntegerValueField(fields.windowId))
        let pid = pid_t(truncatingIfNeeded: event.getIntegerValueField(fields.targetPid))
        guard wid != 0, pid > 0 else { return invalid(subtype) }
        DispatchQueue.main.async { deliver(kind, pid: pid, wid: wid) }
    }

    private static func deliver(_ kind: AttentionSubtype, pid: pid_t, wid: CGWindowID) {
        guard !isOurOwnPanel(pid) else { return }
        switch kind {
        case .clickActivate, .clickReactivate:
            AttentionEngine.directedAttention(.clickActivation, pid: pid, wid: wid, subtype: kind.rawValue)
        case .commandBacktick:
            AttentionEngine.directedAttention(.commandBacktick, pid: pid, wid: wid, subtype: kind.rawValue)
        case .resignA, .resignB:
            // Diagnostics only, never a winner. A resign fires in pairs a millisecond apart, and one of them
            // has been measured naming the window that had just ACQUIRED key — so "the last resign names who
            // really had it" is false, and a hung app can leave a Space with no key window at all while its
            // resign still fired.
            TrackingTelemetryRecorder.attentionResign(pid: pid, wid: wid, subtype: kind.rawValue)
        }
    }

    /// AltTab's own panels take no attention: the switcher appearing is not the user going somewhere.
    private static func isOurOwnPanel(_ pid: pid_t) -> Bool {
        pid == AXUIElement.currentProcessPid
    }

    private static func invalid(_ subtype: Int?) {
        DispatchQueue.main.async { TrackingTelemetryRecorder.attentionTapInvalid(subtype: subtype) }
    }

    private static func other(_ subtype: Int) {
        guard Logger.debugEnabled else { return }
        Logger.debug { "attention tap: unhandled subtype \(subtype)" }
    }
}

/// The type-13 subtypes with a known sender inside the WindowServer. Every one of these was traced to its
/// `CPXPostEvent` call site; the rest are recorded only as counts.
///
/// The call sites exist, but only 9 has ever been seen posting. 18 and 19 are kept decoded rather than
/// deleted so that an OS build which does start using them shows up as a subtype we already name, instead of
/// as an unhandled count nobody reads.
enum AttentionSubtype: Int {
    /// `CGXSendDeferredAct` — a click that activates another app's window. **The only one measured firing.**
    case clickActivate = 9
    /// `CGXSendReactivate` — would be a click re-activating the already-front app's window. Never observed:
    /// that click emits no type-13 at all (SCENARIOS §C).
    case clickReactivate = 18
    /// `_XCycleWindows` — would be the WindowServer's own Cmd+` cycle. Never observed: Cmd+` emits KeyDown,
    /// KeyUp and the resign pair, and nothing else (SCENARIOS §E, §M).
    case commandBacktick = 19
    case resignA = 22
    case resignB = 23
}
