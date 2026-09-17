import Cocoa

// TODO: underlying content scrolls if both Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though.
class TrackpadEvents {
    /// Detection. LISTEN-ONLY on purpose: an active tap on `cghidEventTap` makes the WindowServer wait for
    /// our callback on EVERY gesture event before it processes anything queued behind it — including the
    /// mouse-moves that carry the cursor. Gesture events flow the whole time a finger is on the trackpad,
    /// so with one active tap here the cursor's latency was gated on this process for as long as the user
    /// was touching the trackpad. That is #5911: unusable cursor over the Dock and the menu bar (where you
    /// point slowly and deliberately), no CPU spike anywhere, and "disabling Gestures fixes it" — which the
    /// reporter confirmed. Listening costs the WindowServer nothing: it hands us a copy and moves on.
    private static var detectTap: CFMachPort!
    /// Absorption. This one IS active, because returning nil is the only way to keep the focused app from
    /// also acting on the gesture — but it is enabled only while absorbing is possible: the switcher is
    /// open, or enough fingers are down to trigger. Outside that, nothing in `touchEventHandler` can ever
    /// return true (verified by reading every path: absorb happens when the session is active, or on the
    /// single event that fires the trigger), so being absent from the stream changes no behaviour.
    private static var absorbTap: CFMachPort!
    private static var absorbTapEnabled = false
    /// Whether the detection pass wants the current gesture swallowed. Written by `touchEventHandler` and
    /// read by `absorbTap`'s callback — both on the tap thread — and also cleared from main when the
    /// session ends (`reset`). That last one is a cross-thread write of a Bool whose only failure mode is
    /// one extra or one missing swallowed event at a session boundary, the same latitude the pre-existing
    /// `shouldBeEnabled` takes; a lock here would sit in the input hot path to buy nothing.
    private static var absorbGestures = false
    private static var shouldBeEnabled: Bool!
    /// All of the trigger's state. Owned here, mutated only from the tap thread and from `reset`'s hop
    /// onto that thread.
    static let triggerKernel = GestureTriggerKernel()

    static func observe() {
        observe_()
        TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
        ScrollwheelEvents.observe()
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if let detectTap {
            CGEvent.tapEnable(tap: detectTap, enable: enabled)
        }
        // The absorbing tap follows the gesture, not the preference: with gestures off nothing can ever ask
        // for absorption, so leaving it out of the stream is both correct and one less active tap.
        if !enabled { setAbsorbTapEnabled(false) }
    }

    static func reEnableTapIfNeeded() {
        if CGEvent.reEnableTapIfNeeded(detectTap, wanted: shouldBeEnabled) {
            Logger.warning { "" }
        }
    }

    /// Called from the main thread (`App.hideUi`), while the detectors it clears are otherwise only ever
    /// touched from tap callbacks on the input-events thread. Their state includes `GestureTracker`'s
    /// dictionary, and a `removeAll` racing an insert in a tap callback over-releases its buffer: the
    /// callback then dereferences freed memory and the app segfaults inside the reset. So we hop to the
    /// owning thread rather than lock the input hot path.
    static func reset() {
        BackgroundWork.keyboardAndMouseAndTrackpadEventsThread?.async {
            // The session is over, so absorbing is over. Without this the active tap would sit in the stream
            // until the next trackpad touch re-evaluated it — harmless, but it is exactly the state #5911 is
            // about, and a session that ends with no finger down is the common case (focus on release).
            setAbsorbTapEnabled(false)
            ScrollwheelEvents.toggle(false)
            NavigationSwipeDetector.reset()
            triggerKernel.reset()
        }
    }

    private static func observe_() {
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        // ORDER MATTERS, and it is decided by `tapCreate` order, not by when the runloop source is added
        // (measured on macOS 26.5 with two taps at the same point: the one created SECOND runs FIRST, and
        // swapping the `CFRunLoopAddSource` order changed nothing). The absorbing tap consults a verdict
        // the detecting tap writes, so detection has to run first — i.e. be created LAST. Created the
        // other way round, `absorbGestures` was always one event stale, which would leak precisely the
        // event that fires the trigger.
        absorbTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: absorbEvent,
            userInfo: nil)
        detectTap = CGEvent.tapCreate(
            tap: .cghidEventTap, // we need raw data
            place: .headInsertEventTap,
            options: .listenOnly, // see `detectTap`: an active tap here gates the cursor on us (#5911)
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: handleEvent,
            userInfo: nil)
        guard let detectTap, let absorbTap else { App.restart(); return }
        CGEvent.tapEnable(tap: absorbTap, enable: false)
        for tap in [absorbTap, detectTap] {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
        }
    }

    /// Put the absorbing tap in or out of the stream. Called only at gesture boundaries (the finger count
    /// crossing the trigger threshold, the session opening or closing), never per event: `CGEvent.tapEnable`
    /// is IPC, and doing it per event would reintroduce exactly the cost this split removes.
    private static func setAbsorbTapEnabled(_ enabled: Bool) {
        guard enabled != absorbTapEnabled, let absorbTap else { return }
        absorbTapEnabled = enabled
        CGEvent.tapEnable(tap: absorbTap, enable: enabled)
        if !enabled { absorbGestures = false }
    }

    /// The active tap: it exists to swallow, so it does nothing else. `absorbGestures` is decided by the
    /// detection pass on the listen-only tap.
    private static let absorbEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type.rawValue == NSEvent.EventType.gesture.rawValue {
            if absorbGestures { return nil } // focused app won't receive the event
        } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            // Named at INFO for the same reason as in `KeyboardEvents`: a dead gesture tap looks exactly
            // like #5137 from the outside, and nothing in the log used to say a tap had died.
            Logger.info { "absorb tap disabled \(type == .tapDisabledByTimeout ? "byTimeout" : "byUserInput") wanted:\(absorbTapEnabled)" }
            if absorbTapEnabled { CGEvent.tapEnable(tap: absorbTap!, enable: true) }
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    /// Detection only. Its return value is ignored by the OS (the tap is listen-only); what it decides is
    /// carried by `absorbGestures`, which the active tap applies.
    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type.rawValue == NSEvent.EventType.gesture.rawValue {
            absorbGestures = touchEventHandler(cgEvent)
        } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
            // This is the tap that detects gestures at all: if it stays down, gestures are simply gone
            // and the only cure is relaunching AltTab. Say so in the log (#5137).
            Logger.info { "detect tap disabled \(type == .tapDisabledByTimeout ? "byTimeout" : "byUserInput") wanted:\(shouldBeEnabled == true)" }
            if shouldBeEnabled { CGEvent.tapEnable(tap: detectTap!, enable: true) }
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private static func touchEventHandler(_ cgEvent: CGEvent) -> Bool {
        guard let nsEvent = cgEvent.toNSEvent() else {
            logFirstGesture { "gesture decode: the CGEvent did not convert to an NSEvent" }
            return false // don't absorb the touch event
        }
        // Gesture detection only applies to indirect (trackpad) touches. Drop direct touches up front
        // (touchscreen, Touch Bar): they aren't trackpad fingers and have no `normalizedPosition`, so
        // they'd break the gesture math and make the getter throw. This does NOT cover Universal
        // Control touches (those report as .indirect); `safeNormalizedPosition` guards those reads.
        let touches = nsEvent.allTouches().filter { $0.type == .indirect }
        if !didLogFirstGesture { reportFirstDecode(touches) }
        // macOS often sends faulty events with no touches between valid events; we ignore these as they would break our gesture logic
        guard touches.count > 0 else  { return false }
        let touchesDown = touches.filter { $0.phase == .began || $0.phase == .moved || $0.phase == .stationary }
        let fingersDown = touchesDown.count
        let requiredFingers = Preferences.nextWindowGesture.isThreeFinger() ? 3 : 4
        // Arm the absorbing tap only once absorbing is possible at all. The trigger needs `requiredFingers`
        // down AND `minSwipeDistance` travelled after that, so arming on the finger count lands many
        // events before the one that has to be swallowed. One- and two-finger use — pointing, scrolling,
        // the whole of #5911 — never puts an active tap in the HID stream.
        setAbsorbTapEnabled(SwitcherSession.isActive || fingersDown >= requiredFingers)
        let touchesDownIds = Set(touchesDown.map { identity($0) })
        // isResting seems to always return false. It's not doing its job to detect resting thumb/palm/finger
        // on macOS, the finger contact surface is not exposed in NSTouch, so we can't detect big contact == palm, for example
        // the closest thing we can do to detect resting inputs is remove touches which have .phase == .stationary
        //
        // Skipped for a lone finger with the switcher closed: that is pointer mode, where the kernel only
        // needs to hear the gesture is over, and reading positions would put an exception-guarded
        // `normalizedPosition` read per touch per event into the plain-pointing hot path (#5911).
        let activeTouches = SwitcherSession.isActive || fingersDown > 1
            ? touches.filter { !$0.isResting && ($0.phase == .began || $0.phase == .moved) }.map { gestureTouch($0) }
            : []
        if SwitcherSession.isActive {
            handleEventIfAppIsBeingUsed(fingersDown, activeTouches, touchesDownIds, requiredFingers)
            return true // absorb the touch event
        }
        let frame = GestureTriggerKernel.Frame(
            fingersDown: fingersDown, activeTouches: activeTouches, touchesDownIds: touchesDownIds,
            requiredFingers: requiredFingers, horizontal: Preferences.nextWindowGesture.isHorizontal())
        guard triggerKernel.handle(frame) == .trigger else { return false } // don't absorb the touch event
        DispatchQueue.main.async {
            ScrollwheelEvents.toggle(true)
            performHapticFeedback()
            App.showUiOrCycleSelection(Preferences.gestureIndex, false)
        }
        return true // absorb the touch event, so the focused app doesn't also act on it
    }

    /// **One line per launch on the first gesture that reaches the decoder**, so a run's log says whether
    /// this macOS still hands us what the gesture math needs: an `NSEvent` out of the tap's `CGEvent`, its
    /// trackpad touches, and a readable `normalizedPosition` on each. Every one of those is a private
    /// bridge Apple rewrites freely, and a break in any of them is silent (the swipe simply never triggers).
    /// Logged from the tap thread; both counters are only ever touched there.
    private static var didLogFirstGesture = false
    /// An empty event is normal between valid ones, so a swipe that decodes is always reported from a real
    /// touch. **A run of them is the break itself** — events arriving with nothing in them is what a rewritten
    /// bridge looks like from here — and it has to be told apart from a trackpad nobody touched, which
    /// produces no event at all. So a report is forced once this many have arrived with no touch.
    private static let emptyTouchEventsBeforeReporting = 20
    private static var emptyTouchEvents = 0

    private static func reportFirstDecode(_ touches: Set<NSTouch>) {
        if touches.isEmpty {
            emptyTouchEvents += 1
            guard emptyTouchEvents >= emptyTouchEventsBeforeReporting else { return }
        }
        logFirstGesture { describeDecodedGesture(touches) }
    }

    private static func logFirstGesture(_ line: () -> String) {
        guard !didLogFirstGesture else { return }
        didLogFirstGesture = true
        let text = line()
        Logger.info { text }
    }

    /// The touch count comes first in the line either way, so a reader can judge it without parsing prose.
    private static func describeDecodedGesture(_ touches: Set<NSTouch>) -> String {
        guard !touches.isEmpty else { return "gesture decode: 0 touches on \(emptyTouchEvents) events" }
        let readable = touches.filter { safeNormalizedPosition($0) != nil }.count
        let position = readable == touches.count ? "position ok" : "position unavailable on \(touches.count - readable)"
        return "gesture decode: \(touches.count) touches, \(position)"
    }

    /// `NSTouch.identity` is an opaque object; its description is all we need, since `GestureTracker`
    /// only ever compares identities of touches that are down at the same moment.
    private static func identity(_ touch: NSTouch) -> String {
        "\(touch.identity)"
    }

    private static func gestureTouch(_ touch: NSTouch) -> GestureTouch {
        GestureTouch(id: identity(touch), position: safeNormalizedPosition(touch), isBegan: touch.phase == .began)
    }

    /// `normalizedPosition` is the only API for an indirect touch's position, but its getter throws
    /// NSInternalInconsistencyException for some valid indirect touches (notably ones Universal Control
    /// forwards from another Mac's trackpad). Swift can't catch NSException, so read it through
    /// ObjCExceptionCatcher and treat a throw as "position unavailable"; the kernel then skips that
    /// touch, so the gesture simply doesn't trigger over Universal Control instead of crashing (#5499).
    private static var didWarnUnreadableTouch = false
    private static func safeNormalizedPosition(_ touch: NSTouch) -> NSPoint? {
        var position: NSPoint?
        ObjCExceptionCatcher.attempt { position = touch.normalizedPosition }
        if position == nil, !didWarnUnreadableTouch {
            didWarnUnreadableTouch = true
            Logger.debug { "NSTouch.normalizedPosition unavailable for some touches (e.g. Universal Control); ignoring them for gestures" }
        }
        return position
    }

    private static func handleEventIfAppIsBeingUsed(_ fingersDown: Int, _ activeTouches: [GestureTouch], _ touchesDownIds: Set<String>, _ requiredFingers: Int) {
        if fingersDown <= triggerKernel.maxFingersDownDuringTrigger - requiredFingers {
            if let session = SwitcherSession.current,
               session.shortcutIndex == Preferences.gestureIndex,
               !session.forceDoNothingOnRelease,
               Preferences.effectiveShortcutStyle(session.shortcutIndex) == .focusOnRelease {
                DispatchQueue.main.async {
                    App.focusTarget()
                }
            }
            return
        }
        if activeTouches.count > 1 {
            ScrollwheelEvents.toggle(true)
            CursorEvents.deadZoneInitialPosition = nil
            NavigationSwipeDetector.hasDetected(activeTouches, touchesDownIds)
        }
        // if activeTouches.count == 1, ignore (finger is in pointer-mode)
    }
}

/// Steps the selection while the switcher is open and the fingers are still down. Separate from the
/// trigger because it re-bases as it goes (each further swipe steps again) and because it is reset on
/// every `hideUi`, so it never accumulates state across sessions the way the trigger could (#5137).
class NavigationSwipeDetector {
    static let MIN_SWIPE_DISTANCE: CGFloat = 0.03 // % of trackpad surface traveled

    private static var gestureTracker = GestureTracker()

    static func hasDetected(_ activeTouches: [GestureTouch], _ touchesDownIds: Set<String>) {
        gestureTracker.prune(toTouchesDown: touchesDownIds)
        guard !gestureTracker.isNewGesture(activeTouches) else { return }
        let averageDistance = gestureTracker.averageDistance(activeTouches)
        let (absX, absY) = (abs(averageDistance.x), abs(averageDistance.y))
        let maxIsX = absX >= absY
        guard (maxIsX ? absX : absY) > MIN_SWIPE_DISTANCE else { return }
        gestureTracker.rebase(activeTouches, horizontally: maxIsX)
        let direction: Direction = maxIsX ? (averageDistance.x < 0 ? .left : .right) : (averageDistance.y < 0 ? .down : .up)
        DispatchQueue.main.async {
            performHapticFeedback()
            App.cycleSelection(direction, allowWrap: false)
        }
    }

    static func reset() {
        gestureTracker.reset()
    }
}

fileprivate func performHapticFeedback() {
    if Preferences.trackpadHapticFeedbackEnabled {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}
