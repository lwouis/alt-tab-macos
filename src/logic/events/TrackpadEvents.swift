import Cocoa

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!

//TODO: Should we add a sensitivity setting instead of these magic numbers?
fileprivate let SHOW_UI_THRESHOLD: Float = 0.003
fileprivate let CYCLE_THRESHOLD: Float = 0.04

// gesture tracking state
fileprivate var prevTouchPositions: [String: NSPoint] = [:]
fileprivate var totalDisplacement = (x: Float(0), y: Float(0))
fileprivate var extendNextXThreshold = false

//TODO: underlying content scrolls if both Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though.
class TrackpadEvents {
    static func observe() {
        observe_()
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
        options: .listenOnly,
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
            return nil
        }
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent)
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
        if App.app.appIsBeingUsed && touches.count < requiredFingers && App.app.shortcutIndex == 5
            && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
            DispatchQueue.main.async { App.app.focusTarget() }
            return true
        }
        return false
    }

    guard let delta = calculateTouchDelta(touches) else { return false }
    let displacement = (x: totalDisplacement.x + delta.x, y: totalDisplacement.y + delta.y)
    totalDisplacement = displacement

    // handle showing the app initially
    if !App.app.appIsBeingUsed {
        if abs(displacement.x) > SHOW_UI_THRESHOLD && abs(displacement.y) < SHOW_UI_THRESHOLD {
            resetDisplacement(x: true, y: false)
            // the SHOW_UI_THRESHOLD is much less then the CYCLE_THRESHOLD
            // so for consistency when swiping, extend the threshold for the next horizontal swipe
            extendNextXThreshold = true
            DispatchQueue.main.async { App.app.showUiOrCycleSelection(5) }
            return true
        }
        return false
    }

    // handle swipes when the app is open
    if abs(displacement.x) > CYCLE_THRESHOLD {
        // if extendNextXThreshold is set, extend the threshold for a right swipe to account for the show ui swipe
        if !extendNextXThreshold || displacement.x < 0
            || displacement.x > 2 * CYCLE_THRESHOLD - SHOW_UI_THRESHOLD
        {
            let direction: Direction = displacement.x < 0 ? .left : .right
            resetDisplacement(x: true, y: false)
            extendNextXThreshold = false
            DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
            return true
        }
    }
    if abs(displacement.y) > CYCLE_THRESHOLD {
        let direction: Direction = displacement.y < 0 ? .down : .up
        resetDisplacement(x: false, y: true)
        DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
        return true
    }
    return false
}

private func calculateTouchDelta(_ touches: Set<NSTouch>) -> (x: Float, y: Float)? {
    var allRight = true
    var allLeft = true
    var allUp = true
    var allDown = true
    var sumDelta = (x: Float(0), y: Float(0))
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

        let delta = (
            x: Float(position.x - prevPosition!.x), y: Float(position.y - prevPosition!.y)
        )

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
    return (x: sumDelta.x / Float(count), y: sumDelta.y / Float(count))
}

private func clearState() {
    prevTouchPositions.removeAll()
    resetDisplacement()
    extendNextXThreshold = false
}

private func resetDisplacement(x: Bool = true, y: Bool = true) {
    if x && y {
        totalDisplacement = (0, 0)
    } else if x {
        totalDisplacement.x = 0
    } else if y {
        totalDisplacement.y = 0
    }
}
