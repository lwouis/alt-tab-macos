import Cocoa

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!

// TODO: underlying content scrolls if both Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though.
class TrackpadEvents {
    static func observe() {
        observe_()
        TrackpadEvents.toggle(Preferences.nextWindowGesture != .disabled)
    }

    static func toggle(_ enabled: Bool) {
        shouldBeEnabled = enabled
        if let eventTap = eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }
}

private func observe_() {
    // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
    eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap, // we need raw data
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
        callback: handleEvent,
        userInfo: nil)
    if let eventTap = eventTap {
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(BackgroundWork.keyboardEventsThread.runLoop, runLoopSource, .commonModes)
    } else {
        App.app.restart()
    }
}

private let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
    if type.rawValue == NSEvent.EventType.gesture.rawValue {
        if touchEventHandler(cgEvent) {
            return nil // focused app won't receive the event
        }
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
}

private func touchEventHandler(_ cgEvent: CGEvent) -> Bool {
    guard let nsEvent = GestureDetector.convertEvent(cgEvent) else { return false }
    // if the finger count doesn't match, we reset tracking data, and may trigger fingersUp
    let touches = nsEvent.allTouches()
    if touches.count == 0 { return false } // sometimes the os sends events with no touches
    let activeTouches = touches.filter { !$0.isResting && ($0.phase == .began || $0.phase == .moved || $0.phase == .stationary) }
    let requiredFingers = Preferences.nextWindowGesture.isThreeFinger() ? 3 : 4
    if touches.count != requiredFingers {
        TriggerSwipeDetector.reset()
        NavigationSwipeDetector.reset()
        return GestureDetector.checkForFingersUp(activeTouches, requiredFingers)
    }
    // when the native using 3-finger swipe to shift Space, macOS will block scrolling in the background
    // We imitate this behavior by sending a synthetic scrollWheel event
    GestureDetector.blockOngoingScrolling()
    // trigger actions if conditions are met
    if App.app.appIsBeingUsed {
        if !GestureDetector.updateStartPositions(touches, &NavigationSwipeDetector.startPositions) {
            if let r = NavigationSwipeDetector.check(touches) { return r }
        }
    } else {
        if !GestureDetector.updateStartPositions(touches, &TriggerSwipeDetector.startPositions) {
            if let r = TriggerSwipeDetector.check(touches) { return r }
        }
    }
    return false
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

    static func checkForFingersUp(_ touches: Set<NSTouch>, _ requiredFingers: Int) -> Bool {
        if App.app.appIsBeingUsed && touches.count < requiredFingers && App.app.shortcutIndex == Preferences.gestureIndex
               && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
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
            let averageDistance = GestureDetector.computeAverageDistance(activeTouches, startPositions)
            let (absX, absY) = (abs(averageDistance.x), abs(averageDistance.y))
            let horizontal = Preferences.nextWindowGesture.isHorizontal()
            if (updateSwipeStillPossible(horizontal ? absY : absX) && (horizontal ? absX : absY) >= MIN_SWIPE_DISTANCE) {
                reset()
                DispatchQueue.main.async { App.app.showUiOrCycleSelection(Preferences.gestureIndex) }
                return true
            }
            return false
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
    // TODO: replace this approach with a "virtual cursor" approach
    //  Instead of detecting swipes, we would track coordinate, and check which thumbnail is under that cursor
    static let MIN_SWIPE_DISTANCE: Double = 0.045 // % of trackpad surface traveled

    static var startPositions: [String: NSPoint] = [:]

    static func check(_ touches: Set<NSTouch>) -> Bool? {
        let averageDistance = GestureDetector.computeAverageDistance(touches, startPositions)
        let (absX, absY) = (abs(averageDistance.x), abs(averageDistance.y))
        let maxIsX = absX >= absY
        if (maxIsX ? absX : absY) > MIN_SWIPE_DISTANCE {
            maxIsX ? resetX(touches) : resetY(touches)
            let direction: Direction = maxIsX ? (averageDistance.x < 0 ? .left : .right) : (averageDistance.y < 0 ? .down : .up)
            DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
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
