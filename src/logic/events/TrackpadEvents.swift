import Cocoa

// TODO: underlying content scrolls if both Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though.
class TrackpadEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!
    private static var cursorMovedDistance = CGFloat(0.0)

    static func observe() {
        observe_()
        TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
        ScrollwheelEvents.observe()
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    private static func observe_() {
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap, // we need raw data
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
            callback: handleEvent,
            userInfo: nil)
        if let eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
        } else {
            App.app.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type.rawValue == NSEvent.EventType.gesture.rawValue {
            if touchEventHandler(cgEvent) {
                return nil // focused app won't receive the event
            }
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
    }

    private static func touchEventHandler(_ cgEvent: CGEvent) -> Bool {
        guard let nsEvent = cgEvent.toNSEvent() else { return false } // don't absorb the touch event
        let touches = nsEvent.allTouches()
        // Logger.error { (touches.count, touches.map { $0.phase.readable}) }
        // sometimes the os sends events with no touches; we ignore these as they could break our gesture logic
        if touches.count == 0 {
            return false
        }
        let activeTouches = touches.filter { !$0.isResting && ($0.phase == .began || $0.phase == .moved || $0.phase == .stationary) }
        let requiredFingers = Preferences.nextWindowGesture.isThreeFinger() ? 3 : 4
        if App.app.appIsBeingUsed {
            handleEventIfAppIsBeingUsed(activeTouches, requiredFingers)
            return true // absorb the touch event
        }
        return handleEventIfAppIsNotBeingUsed(touches, activeTouches, requiredFingers) // absorb or not the touch event, depending on the situation
    }

    private static func handleEventIfAppIsBeingUsed(_ activeTouches: Set<NSTouch>, _ requiredFingers: Int) {
        if activeTouches.count == 0 {
            NavigationSwipeDetector.reset()
            if App.app.shortcutIndex == Preferences.gestureIndex && !App.app.forceDoNothingOnRelease && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
                DispatchQueue.main.async {
                    ScrollwheelEvents.toggle(false)
                    App.app.focusTarget()
                }
            }
        } else if activeTouches.count > 1 {
            CursorEvents.deadZoneInitialPosition = nil
            NavigationSwipeDetector.hasDetected(activeTouches)
        } else {
            // if activeTouches.count == 1, ignore (finger is in pointer-mode)
        }
    }

    private static func handleEventIfAppIsNotBeingUsed(_ touches: Set<NSTouch>, _ activeTouches: Set<NSTouch>, _ requiredFingers: Int) -> Bool {
        if touches.count <= 1 {
            NonFreshGestureDetector.reset()
            return false // don't absorb the touch event
        }
        if NonFreshGestureDetector.hasDetected(activeTouches, requiredFingers) {
            return false // don't absorb the touch event
        }
        if activeTouches.count != requiredFingers {
            TriggerSwipeDetector.reset()
            return false // don't absorb the touch event
        } else {
            return TriggerSwipeDetector.hasDetected(activeTouches) // absorb or not the touch event, depending on the situation
        }
    }
}

class NonFreshGestureDetector {
    private static var userHasDoneAnotherGesture = false
    private static var gestureTracker = GestureTracker()

    /// if the user has already used a gesture-action (e.g. 2-finger scroll), we consider this "session" invalid, until all fingers are released
    /// This prevents: 4->3 trigger (System swipe already happened), or 2->3 trigger (System scroll already happened)
    static func hasDetected(_ activeTouches: Set<NSTouch>,_ requiredFingers: Int) -> Bool {
        guard !userHasDoneAnotherGesture else { return true }
        let new = gestureTracker.isNewGesture(activeTouches)
        guard activeTouches.count != requiredFingers && !new else { return false }
        let distances = gestureTracker.computeDistance(activeTouches)
        userHasDoneAnotherGesture = distances.contains(where: { abs($0.x) >= TriggerSwipeDetector.MIN_SWIPE_DISTANCE || abs($0.y) >= TriggerSwipeDetector.MIN_SWIPE_DISTANCE })
        return userHasDoneAnotherGesture
    }

    static func reset() {
        userHasDoneAnotherGesture = false
        gestureTracker.reset()
    }
}

class TriggerSwipeDetector {
    // when the native using 3-finger swipe to shift Space, macOS will wait that a small distance is traveled before acting
    // We imitate this behavior
    static let MIN_SWIPE_DISTANCE: Double = 0.015 // % of trackpad surface traveled
    // when the native using 3-finger swipe to shift Space, macOS will prevent a swipe until the fingers are raised,
    // if the user moves too much in the vertical direction. We imitate this behavior
    static let MAX_SWIPE_DISTANCE_IN_WRONG_DIRECTION: Double = 0.1 // % of trackpad surface traveled

    private static var gestureTracker = GestureTracker()
    private static var swipeStillPossible = true

    static func hasDetected(_ activeTouches: Set<NSTouch>) -> Bool {
        guard swipeStillPossible && !gestureTracker.isNewGesture(activeTouches) else { return false }
        let distances = gestureTracker.computeDistance(activeTouches)
        for distance in distances {
            let (absX, absY) = (abs(distance.x), abs(distance.y))
            let horizontal = Preferences.nextWindowGesture.isHorizontal()
            let distanceInRightDirection = horizontal ? absX : absY
            let distanceInWrongDirection = horizontal ? absY : absX
            swipeStillPossible = distanceInWrongDirection < MAX_SWIPE_DISTANCE_IN_WRONG_DIRECTION
            guard swipeStillPossible && distanceInRightDirection >= MIN_SWIPE_DISTANCE else { return false }
        }
        reset()
        DispatchQueue.main.async {
            ScrollwheelEvents.toggle(true)
            performHapticFeedback()
            App.app.showUiOrCycleSelection(Preferences.gestureIndex, false)
        }
        return true
    }

    static func reset() {
        gestureTracker.reset()
        swipeStillPossible = true
    }
}

class NavigationSwipeDetector {
    static let MIN_SWIPE_DISTANCE: Double = 0.03 // % of trackpad surface traveled

    private static var gestureTracker = GestureTracker()

    static func hasDetected(_ activeTouches: Set<NSTouch>) {
        guard !gestureTracker.isNewGesture(activeTouches) else { return }
        let averageDistance = gestureTracker.computeAverageDistance(activeTouches)
        let (absX, absY) = (abs(averageDistance.x), abs(averageDistance.y))
        let maxIsX = absX >= absY
        guard (maxIsX ? absX : absY) > MIN_SWIPE_DISTANCE else { return }
        maxIsX ? gestureTracker.resetX(activeTouches) : gestureTracker.resetY(activeTouches)
        let direction: Direction = maxIsX ? (averageDistance.x < 0 ? .left : .right) : (averageDistance.y < 0 ? .down : .up)
        DispatchQueue.main.async {
            performHapticFeedback()
            App.app.cycleSelection(direction, allowWrap: false)
        }
    }

    static func reset() {
        gestureTracker.reset()
    }
}

class GestureTracker {
    var startPositions = [String: NSPoint]()

    @discardableResult
    func isNewGesture(_ activeTouches: Set<NSTouch>) -> Bool {
        // if touches are new, record their startPositions
        if (activeTouches.contains { startPositions["\($0.identity)"] == nil }) {
            for touch in activeTouches {
                startPositions["\(touch.identity)"] = touch.normalizedPosition
            }
            return true
        }
        return false
    }

    func computeAverageDistance(_ activeTouches: Set<NSTouch>) -> NSPoint {
        var totalDelta = NSPoint(x: 0, y: 0)
        for touch in activeTouches {
            totalDelta = totalDelta + (touch.normalizedPosition - startPositions["\(touch.identity)"]!)
        }
        return totalDelta / activeTouches.count
    }

    func computeDistance(_ activeTouches: Set<NSTouch>) -> Array<NSPoint> {
        var deltas: Array<NSPoint> = []
        for touch in activeTouches {
            deltas.append(touch.normalizedPosition - startPositions["\(touch.identity)"]!)
        }
        return deltas
    }

    func reset() {
        startPositions.removeAll(keepingCapacity: true)
    }

    func resetX(_ activeTouches: Set<NSTouch>) {
        for touch in activeTouches {
            startPositions["\(touch.identity)"]!.x = touch.normalizedPosition.x
        }
    }

    func resetY(_ activeTouches: Set<NSTouch>) {
        for touch in activeTouches {
            startPositions["\(touch.identity)"]!.y = touch.normalizedPosition.y
        }
    }
}

fileprivate func performHapticFeedback() {
    if Preferences.trackpadHapticFeedbackEnabled {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}
