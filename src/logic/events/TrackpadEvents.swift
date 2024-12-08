import Cocoa

private var eventTap: CFMachPort!
private var shouldBeEnabled: Bool!

//TODO: Should we add a sensitivity setting instead of these magic numbers?
private let SHOW_UI_THRESHOLD: Float = 0.003
private let CYCLE_THRESHOLD: Float = 0.04

// gesture tracking state
private var prevTouchPositions: [String: NSPoint] = [:]
private var totalDisplacement = (x: Float(0), y: Float(0))
private var extendNextXThreshold = false

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
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: NSEvent.EventTypeMask.gesture.rawValue,
        callback: eventHandler,
        userInfo: nil)
    if let eventTap = eventTap {
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        //TODO: Is CFRunLoopGetCurrent OK or do we need yet another thread with runLoop in BackgroundWork?
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.commonModes)
    } else {
        App.app.restart()
    }
}

private func eventHandler(
    proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type.rawValue == NSEvent.EventType.gesture.rawValue, let nsEvent = NSEvent(cgEvent: cgEvent)
    {
        touchEventHandler(nsEvent)
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled
    {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return nil
}

private func touchEventHandler(_ nsEvent: NSEvent) {
    let requiredFingers = Preferences.gesture == .fourFingerSwipe ? 4 : 3
    let touches = nsEvent.allTouches()

    // Sometimes there are empty touch events that we have to skip. There are no empty touch events if Mission Control or App Expose use 3-finger swipes though.
    if touches.isEmpty { return }

    if touches.allSatisfy({ $0.phase == .ended }) || touches.count != requiredFingers {
        if App.app.appIsBeingUsed && touches.count < requiredFingers && App.app.shortcutIndex == 5
            && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease
        {
            DispatchQueue.main.async { App.app.focusTarget() }
        }
        clearState()
        return
    }

    guard let delta = calculateTouchDelta(touches) else { return }
    let displacement = (x: totalDisplacement.x + delta.x, y: totalDisplacement.y + delta.y)
    totalDisplacement = displacement

    // handle showing the app initially
    if !App.app.appIsBeingUsed {
        if abs(displacement.x) > SHOW_UI_THRESHOLD && abs(displacement.y) < SHOW_UI_THRESHOLD {
            DispatchQueue.main.async { App.app.showUiOrCycleSelection(5) }
            resetDisplacement(x: true, y: false)
            // the SHOW_UI_THRESHOLD is much less then the CYCLE_THRESHOLD
            // so for consistency when swiping, extend the threshold for the next horizontal swipe
            extendNextXThreshold = true
        }
        return
    }

    // handle swipes when the app is open
    if abs(displacement.x) > CYCLE_THRESHOLD {
        // if extendNextXThreshold is set, extend the threshold for a right swipe to account for the show ui swipe
        if !extendNextXThreshold || displacement.x < 0
            || displacement.x > 2 * CYCLE_THRESHOLD - SHOW_UI_THRESHOLD
        {
            let direction: Direction = displacement.x < 0 ? .left : .right
            DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
            resetDisplacement(x: true, y: false)
            extendNextXThreshold = false
        }
    }
    if abs(displacement.y) > CYCLE_THRESHOLD {
        let direction: Direction = displacement.y < 0 ? .down : .up
        DispatchQueue.main.async { App.app.cycleSelection(direction, allowWrap: false) }
        resetDisplacement(x: false, y: true)
    }
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
