import Cocoa

func listenToGlobalKeyboardEvents(_ delegate: Application) {
    let eventMask = [CGEventType.keyDown, CGEventType.keyUp, CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
    let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (_, _, event, delegate_) -> Unmanaged<CGEvent>? in
                let d = Unmanaged<Application>.fromOpaque(delegate_!).takeUnretainedValue()
                return keyboardHandler(event, d)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(delegate).toOpaque()))
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap!, enable: true)
    CFRunLoopRun()
}

func keyboardHandler(_ cgEvent: CGEvent, _ delegate: Application) -> Unmanaged<CGEvent>? {
    let event = NSEvent(cgEvent: cgEvent)!
    let keyDown = event.type == .keyDown
    let optionKeyEvent = event.keyCode == metaKey
    let tabKeyEvent = event.keyCode == tabKey
    if optionKeyEvent && event.modifiersDown([metaModifierFlag]) {
        delegate.keyDownMeta()
    } else if tabKeyEvent && event.modifiersDown([metaModifierFlag]) && keyDown {
        delegate.keyDownMetaTab()
        // focused app will not receive the event (will not press tab key in that app)
        return nil
    } else if tabKeyEvent && event.modifiersDown([metaModifierFlag, .shift]) && keyDown {
        delegate.keyDownMetaShiftTab()
        // focused app will not receive the event (will not press tab key in that app)
        return nil
    } else if optionKeyEvent && !keyDown {
        delegate.keyUpMeta()
    }
    // focused app will receive the event
    return Unmanaged.passRetained(cgEvent)
}

extension NSEvent {
    func modifiersDown(_ modifiers: NSEvent.ModifierFlags) -> Bool {
        return self.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }
}
