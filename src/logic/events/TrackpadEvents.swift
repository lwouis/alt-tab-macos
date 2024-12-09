import Cocoa

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!

//TODO: Should we add a sensitivity setting instead of these magic numbers?
fileprivate let SHOW_UI_THRESHOLD: Float = 0.003
fileprivate let CYCLE_THRESHOLD: Float = 0.04

// gesture tracking state
fileprivate var prevTouchPositions: [String: NSPoint] = [:]
fileprivate var totalDisplacement = Distance(x: 0, y: 0)
fileprivate var extendNextXThreshold = false

//TODO: underlying content scrolls if both Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though.
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
    var nsEvent: NSEvent?
    DispatchQueue.main.sync {
        nsEvent = NSEvent(cgEvent: cgEvent)
    }
    guard let nsEvent = nsEvent else { return false }
    let touches = nsEvent.allTouches()
    // Sometimes there are empty touch events that we have to skip. There are no empty touch events if Mission Control or App Expose use 3-finger swipes though.
    if touches.isEmpty { return false }
    let requiredFingers = Preferences.nextWindowGesture == .fourFingerSwipe ? 4 : 3
    if touches.allSatisfy({ $0.phase == .ended }) || touches.count != requiredFingers {
        clearState()
        return checkForFingersUp(touches, requiredFingers)
    }
    if #available(macOS 10.13, *) {
        // simulate mouseWheel-stopped to end potential existing scrolling started before AltTab was opened
        // this avoid the swipe to trigger a scroll on the active window and show AltTab, at the same time
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
    }
    guard let delta = calculateTouchDelta(touches) else { return false }
    let displacement = Distance(x: totalDisplacement.x + delta.x, y: totalDisplacement.y + delta.y)
    totalDisplacement = displacement
    if let r = checkForSwipeTrigger(displacement) { return r }
    if let r = checkForSwipeHorizontalCycling(displacement) { return r }
    if let r = checkForSwipeVerticalCycling(displacement) { return r }
    return false
}

private func checkForFingersUp(_ touches: Set<NSTouch>, _ requiredFingers: Int) -> Bool {
    if App.app.appIsBeingUsed && touches.count < requiredFingers && App.app.shortcutIndex == Preferences.gestureIndex
               && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
        DispatchQueue.main.async { App.app.focusTarget() }
        return true
    }
    return false
}

private func checkForSwipeTrigger(_ displacement: Distance) -> Bool? {
    if !App.app.appIsBeingUsed {
        if abs(displacement.x) > SHOW_UI_THRESHOLD && abs(displacement.y) < SHOW_UI_THRESHOLD {
            totalDisplacement.x = 0
            // the SHOW_UI_THRESHOLD is much less then the CYCLE_THRESHOLD
            // so for consistency when swiping, extend the threshold for the next horizontal swipe
            extendNextXThreshold = true
            DispatchQueue.main.async { App.app.showUiOrCycleSelection(Preferences.gestureIndex) }
            return true
        }
        return false
    }
    return nil
}

private func checkForSwipeHorizontalCycling(_ displacement: Distance) -> Bool? {
    if abs(displacement.x) > CYCLE_THRESHOLD {
        // if extendNextXThreshold is set, extend the threshold for a right swipe to account for the show ui swipe
        if !extendNextXThreshold || displacement.x < 0 || displacement.x > 2 * CYCLE_THRESHOLD - SHOW_UI_THRESHOLD {
            totalDisplacement.x = 0
            extendNextXThreshold = false
            DispatchQueue.main.async { App.app.cycleSelection(displacement.x < 0 ? .left : .right, allowWrap: false) }
            return true
        }
    }
    return nil
}

private func checkForSwipeVerticalCycling(_ displacement: Distance) -> Bool? {
    if abs(displacement.y) > CYCLE_THRESHOLD {
        totalDisplacement.y = 0
        DispatchQueue.main.async { App.app.cycleSelection(displacement.y < 0 ? .down : .up, allowWrap: false) }
        return true
    }
    return nil
}

private func calculateTouchDelta(_ touches: Set<NSTouch>) -> Distance? {
    var allRight = true
    var allLeft = true
    var allUp = true
    var allDown = true
    var sumDelta = Distance(x: 0, y: 0)
    var count = 0

    for touch in touches {
        let prevPosition = prevTouchPositions["\(touch.identity)"]
        let position = touch.normalizedPosition
        if touch.phase == .ended {
            prevTouchPositions.removeValue(forKey: "\(touch.identity)")
        } else {
            prevTouchPositions["\(touch.identity)"] = position
        }
        if prevPosition == nil { continue }

        let delta = Distance(x: Float(position.x - prevPosition!.x), y: Float(position.y - prevPosition!.y))

        allRight = allRight && delta.x > 0
        allLeft = allLeft && delta.x < 0
        allUp = allUp && delta.y > 0
        allDown = allDown && delta.y < 0

        sumDelta.x += delta.x
        sumDelta.y += delta.y
        count += 1
    }

    // All fingers should move in the same direction.
    if count == 0 || (!allRight && !allLeft && !allUp && !allDown) { return nil }
    return Distance(x: sumDelta.x / Float(count), y: sumDelta.y / Float(count))
}

private func clearState() {
    prevTouchPositions.removeAll(keepingCapacity: true)
    totalDisplacement.x = 0
    totalDisplacement.y = 0
    extendNextXThreshold = false
}

struct Distance {
    var x: Float
    var y: Float
}
