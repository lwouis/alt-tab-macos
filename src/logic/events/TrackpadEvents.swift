import AppKit

fileprivate var eventTap: CFMachPort!
fileprivate var shouldBeEnabled: Bool!

//TODO: Should we add a sensetivity setting instead of these magic numbers?
fileprivate let accVelXThreshold: Float = 0.05
fileprivate let accVelYThreshold: Float = 0.075
fileprivate var accVelX: Float = 0
fileprivate var accVelY: Float = 0
//TODO: Don't use string as key. Maybe we should use other data-sructure.
fileprivate var prevTouchPositions: [String: NSPoint] = [:]

//TODO: underlying content scrolls if Mission Control and App Expose use 4-finger swipes or are off in Trackpad settings. It doesn't scroll if any of them use 3-finger swipe though. See https://github.com/ris58h/Touch-Tab/issues/1
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
    let eventMask = CGEventMask(1 << NSEvent.EventType.gesture.rawValue)
    // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
    eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: eventMask,
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

private func eventHandler(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type.rawValue == NSEvent.EventType.gesture.rawValue, let nsEvent = NSEvent(cgEvent: cgEvent) {
        touchEventHandler(nsEvent)
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return nil
}

private func touchEventHandler(_ nsEvent: NSEvent) {
    let touches = nsEvent.allTouches()

    // Sometimes there are empty touch events that we have to skip. There are no empty touch events if Mission Control or App Expose use 3-finger swipes though.
    if touches.isEmpty {
        return
    }

    // We don't care about non-3-fingers swipes.
    if touches.count != 3 || touches.allSatisfy({ $0.phase == .ended }) {
        // Except when we already started a gesture, so we need to end it.
        if App.app.appIsBeingUsed && App.app.shortcutIndex == 5 && Preferences.shortcutStyle[App.app.shortcutIndex] == .focusOnRelease {
            DispatchQueue.main.async {
                App.app.focusTarget()
            }
        }
        clearState()
        return
    }

    let velocity = swipeVelocity(touches)
    // We don't care about gestures other than horizontal or vertical swipes.
    if velocity == nil {
        return
    }

    accVelX += velocity!.x
    accVelY += velocity!.y
    // Not enough swiping.
    if abs(accVelX) < accVelXThreshold && abs(accVelY) < accVelYThreshold {
        return
    }

    let isHorizontal = abs(velocity!.x) > abs(velocity!.y)
    if App.app.appIsBeingUsed {
        let direction: Direction = isHorizontal
            ? accVelX < 0 ? .left : .right
            : accVelY < 0 ? .down : .up
        DispatchQueue.main.async { App.app.cycleSelection(direction) }
    } else {
        if isHorizontal {
            DispatchQueue.main.async {
                App.app.appIsBeingUsed = true
                App.app.showUiOrCycleSelection(5)
            }
        }
    }
    clearState()
}

private func clearState() {
    accVelX = 0
    accVelY = 0
    prevTouchPositions.removeAll()
}

private func swipeVelocity(_ touches: Set<NSTouch>) -> (x: Float, y: Float)? {
    var allRight = true
    var allLeft = true
    var allUp = true
    var allDown = true
    var sumVelX = Float(0)
    var sumVelY = Float(0)
    for touch in touches {
        let (velX, velY) = touchVelocity(touch)
        allRight = allRight && velX >= 0
        allLeft = allLeft && velX <= 0
        allUp = allUp && velY >= 0
        allDown = allDown && velY <= 0
        sumVelX += velX
        sumVelY += velY
        
        if touch.phase == .ended {
            prevTouchPositions.removeValue(forKey: "\(touch.identity)")
        } else {
            prevTouchPositions["\(touch.identity)"] = touch.normalizedPosition
        }
    }
    // All fingers should move in the same direction.
    if !allRight && !allLeft && !allUp && !allDown {
        return nil
    }

    let velX = sumVelX / Float(touches.count)
    let velY = sumVelY / Float(touches.count)
    return (velX, velY)
}

private func touchVelocity(_ touch: NSTouch) -> (Float, Float) {
    guard let prevPosition = prevTouchPositions["\(touch.identity)"] else {
        return (0, 0)
    }
    let position = touch.normalizedPosition
    return (Float(position.x - prevPosition.x), Float(position.y - prevPosition.y))
}
