import Cocoa

// TODO: underlying content scrolls if both Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though.
class TrackpadEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!

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
        guard let nsEvent = GestureDetector.convertEvent(cgEvent) else { return false }
        let touches = nsEvent.allTouches()
        // sometimes the os sends events with no touches; we ignore these as they could break our gesture logic
        if touches.count == 0 { return false }
        let activeTouches = touches.filter { !$0.isResting && ($0.phase == .began || $0.phase == .moved || $0.phase == .stationary) }
        // Logger.error("---", "activeTouches:", activeTouches.count, "all:", touches.map { $0.phase.readable })
        let requiredFingers = Preferences.nextWindowGesture.isThreeFinger() ? 3 : 4
        // not enough fingers are down
        if (!App.app.appIsBeingUsed && activeTouches.count != requiredFingers) || (App.app.appIsBeingUsed && activeTouches.count < 2) {
            DispatchQueue.main.async { ScrollwheelEvents.toggle(false) }
            TriggerSwipeDetector.reset()
            NavigationSwipeDetector.reset()
            return GestureDetector.checkForFingersUp(activeTouches.count, requiredFingers)
        }
        // enough fingers are down
        if App.app.appIsBeingUsed {
            DispatchQueue.main.async { ScrollwheelEvents.toggle(true) }
            if !GestureDetector.updateStartPositions(activeTouches, &NavigationSwipeDetector.startPositions) {
                if let r = NavigationSwipeDetector.check(activeTouches) { return r }
            }
        } else {
            if !GestureDetector.updateStartPositions(activeTouches, &TriggerSwipeDetector.startPositions) {
                if let r = TriggerSwipeDetector.check(activeTouches) { return r }
            }
        }
        return false
    }
}

class GestureDetector {
    static func convertEvent(_ cgEvent: CGEvent) -> NSEvent? {
        var nsEvent: NSEvent?
        // conversion has to happen on the main-thread, or appkit will crash
        DispatchQueue.main.sync {
            nsEvent = NSEvent(cgEvent: cgEvent)
        }
        return nsEvent
    }

    static func checkForFingersUp(_ fingersDown: Int, _ requiredFingers: Int) -> Bool {
        if App.app.appIsBeingUsed && fingersDown < requiredFingers && App.app.shortcutIndex == Preferences.gestureIndex
               && !App.app.forceDoNothingOnRelease && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
            DispatchQueue.main.async { App.app.focusTarget() }
            return true
        }
        return false
    }

    static func updateStartPositions(_ activeTouches: Set<NSTouch>, _ startPositions: inout [String: NSPoint]) -> Bool {
        // if touches are new, record their startPositions
        if (activeTouches.contains { startPositions["\($0.identity)"] == nil }) {
            for touch in activeTouches {
                startPositions["\(touch.identity)"] = touch.normalizedPosition
            }
            return true
        }
        return false
    }

    static func computeAverageDistance(_ activeTouches: Set<NSTouch>, _ startPositions: [String: NSPoint]) -> NSPoint {
        var totalDelta = NSPoint(x: 0, y: 0)
        for touch in activeTouches {
            totalDelta = totalDelta + (touch.normalizedPosition - startPositions["\(touch.identity)"]!)
        }
        return totalDelta / activeTouches.count
    }
    
    static func computeDistance(_ activeTouches: Set<NSTouch>, _ startPositions: [String: NSPoint]) -> Array<NSPoint> {
        var deltas: Array<NSPoint> = []
        for touch in activeTouches {
            deltas.append(touch.normalizedPosition - startPositions["\(touch.identity)"]!)
        }
        return deltas
    }

    static func blockOngoingScrolling() {
        if #available(macOS 10.13, *) {
            // simulate mouseWheel-stopped to end potential existing scrolling started before AltTab was opened
            // this avoid the swipe to trigger a scroll on the active window and show AltTab, at the same time
            CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        }
    }
}

class TriggerSwipeDetector {
    // when the native using 3-finger swipe to shift Space, macOS will wait that a small distance is traveled before acting
    // We imitate this behavior
    static let MIN_SWIPE_DISTANCE: Double = 0.015 // % of trackpad surface traveled
    // when the native using 3-finger swipe to shift Space, macOS will prevent a swipe until the fingers are raised,
    // if the user moves too much in the vertical direction. We imitate this behavior
    static let MAX_SWIPE_DISTANCE_IN_WRONG_DIRECTION: Double = 0.1 // % of trackpad surface traveled

    static var startPositions: [String: NSPoint] = [:]
    static var swipeStillPossible = true

    static func check(_ activeTouches: Set<NSTouch>) -> Bool? {
        if !App.app.appIsBeingUsed && swipeStillPossible {
            let distances = GestureDetector.computeDistance(activeTouches, startPositions)
            for distance in distances {
                let (absX, absY) = (abs(distance.x), abs(distance.y))
                let horizontal = Preferences.nextWindowGesture.isHorizontal()
                if (!(updateSwipeStillPossible(horizontal ? absY : absX) && (horizontal ? absX : absY) >= MIN_SWIPE_DISTANCE )) {
                    return false
                }
            }
            reset()
            DispatchQueue.main.async {
                ScrollwheelEvents.toggle(true)
                performHapticFeedback()
                App.app.showUiOrCycleSelection(Preferences.gestureIndex, false)
            }
            return true
        }
        return nil
    }

    static func updateSwipeStillPossible(_ distanceInWrongDirection: Double) -> Bool {
        swipeStillPossible = distanceInWrongDirection < MAX_SWIPE_DISTANCE_IN_WRONG_DIRECTION
        return swipeStillPossible
    }

    static func reset() {
        startPositions.removeAll(keepingCapacity: true)
        swipeStillPossible = true
    }
}

class NavigationSwipeDetector {
    static let MIN_SWIPE_DISTANCE: Double = 0.03 // % of trackpad surface traveled

    static var startPositions: [String: NSPoint] = [:]

    static func check(_ activeTouches: Set<NSTouch>) -> Bool? {
        let averageDistance = GestureDetector.computeAverageDistance(activeTouches, startPositions)
        let (absX, absY) = (abs(averageDistance.x), abs(averageDistance.y))
        let maxIsX = absX >= absY
        if (maxIsX ? absX : absY) > MIN_SWIPE_DISTANCE {
            maxIsX ? resetX(activeTouches) : resetY(activeTouches)
            let direction: Direction = maxIsX ? (averageDistance.x < 0 ? .left : .right) : (averageDistance.y < 0 ? .down : .up)
            DispatchQueue.main.async {
                performHapticFeedback()
                App.app.cycleSelection(direction, allowWrap: false)
            }
            return true
        }
        return nil
    }

    static func reset() {
        startPositions.removeAll(keepingCapacity: true)
    }

    static func resetX(_ activeTouches: Set<NSTouch>) {
        for touch in activeTouches {
            startPositions["\(touch.identity)"]!.x = touch.normalizedPosition.x
        }
    }

    static func resetY(_ activeTouches: Set<NSTouch>) {
        for touch in activeTouches {
            startPositions["\(touch.identity)"]!.y = touch.normalizedPosition.y
        }
    }
}

func performHapticFeedback() {
    if Preferences.trackpadHapticFeedbackEnabled {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}
