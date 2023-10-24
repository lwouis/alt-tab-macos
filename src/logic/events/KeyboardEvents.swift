import Cocoa
import ShortcutRecorder

fileprivate var eventTap: CFMachPort?

class KeyboardEvents {
    static let signature = "altt".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    // GetEventMonitorTarget/GetApplicationEventTarget also work, but require Accessibility Permission
    static let shortcutEventTarget = GetEventDispatcherTarget()
    static let globalShortcutsIds = [
        "nextWindowShortcut": 0,
        "nextWindowShortcut2": 1,
        "nextWindowShortcut3": 2,
        "nextWindowShortcut4": 3,
        "nextWindowShortcut5": 4,
        "holdShortcut": 5,
        "holdShortcut2": 6,
        "holdShortcut3": 7,
        "holdShortcut4": 8,
        "holdShortcut5": 9,
    ]
    static var eventHotKeyRefs = [String: EventHotKeyRef?]()
    static var hotKeyPressedEventHandler: EventHandlerRef?
    static var hotKeyReleasedEventHandler: EventHandlerRef?
    static var localMonitor: Any!

    static func addGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        addGlobalHandlerIfNeeded(shortcut)
        registerHotKeyIfNeeded(controlId, shortcut)
    }

    static func removeGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        unregisterHotKeyIfNeeded(controlId, shortcut)
        removeHandlerIfNeeded()
    }

    private static func unregisterHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            UnregisterEventHotKey(eventHotKeyRefs[controlId]!)
            eventHotKeyRefs[controlId] = nil
        }
    }

    static func registerHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            let id = globalShortcutsIds[controlId]!
            let hotkeyId = EventHotKeyID(signature: signature, id: UInt32(id))
            let key = shortcut.carbonKeyCode
            let mods = shortcut.carbonModifierFlags
            let options = UInt32(kEventHotKeyNoOptions)
            var shortcutsReference: EventHotKeyRef?
            RegisterEventHotKey(key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
            eventHotKeyRefs[controlId] = shortcutsReference
        }
    }

    static func toggleGlobalShortcuts(_ shouldDisable: Bool) {
        if shouldDisable != App.app.globalShortcutsAreDisabled {
            let fn = shouldDisable ? unregisterHotKeyIfNeeded : registerHotKeyIfNeeded
            for shortcutId in globalShortcutsIds.keys {
                if let shortcut = ControlsTab.shortcuts[shortcutId]?.shortcut {
                    fn(shortcutId, shortcut)
                }
            }
            debugPrint("toggleGlobalShortcuts", shouldDisable)
            App.app.globalShortcutsAreDisabled = shouldDisable
        }
    }

    static func addEventHandlers() {
        addLocalMonitorForKeyDownAndKeyUp()
        addCgEventTapForModifierFlags()
    }

    private static func addLocalMonitorForKeyDownAndKeyUp() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { (event: NSEvent) in
            let someShortcutTriggered = handleEvent(nil, nil, event.type == .keyDown ? UInt32(event.keyCode) : nil, cocoaToCarbonFlags(event.modifierFlags), event.type == .keyDown ? event.isARepeat : false)
            return someShortcutTriggered ? nil : event
        }
    }

    private static func addCgEventTapForModifierFlags() {
        let eventMask = [CGEventType.flagsChanged].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        // CGEvent.tapCreate is unaffected by SecureInput for .flagsChanged
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: cgEventFlagsChangedHandler,
            userInfo: nil)
        if let eventTap = eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        } else {
            App.app.restart()
        }
    }

    private static func addGlobalHandlerIfNeeded(_ shortcut: Shortcut) {
        if shortcut.keyCode != .none && hotKeyPressedEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))]
            InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                handleEvent(id, .down, nil, nil, false)
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotKeyPressedEventHandler)
        }
        if shortcut.keyCode != .none && hotKeyReleasedEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))]
            InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                handleEvent(id, .up, nil, nil, false)
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotKeyReleasedEventHandler)
        }
    }

    private static func removeHandlerIfNeeded() {
        let globalShortcuts = ControlsTab.shortcuts.values.filter { $0.scope == .global }
        if let hotKeyPressedEventHandler_ = hotKeyPressedEventHandler, let hotKeyReleasedEventHandler_ = hotKeyReleasedEventHandler,
           (globalShortcuts.allSatisfy { $0.shortcut.keyCode == .none }) {
            RemoveEventHandler(hotKeyPressedEventHandler_)
            hotKeyPressedEventHandler = nil
            RemoveEventHandler(hotKeyReleasedEventHandler_)
            hotKeyReleasedEventHandler = nil
        }
    }
}

@discardableResult
fileprivate func handleEvent(_ id: EventHotKeyID?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: UInt32?, _ isARepeat: Bool) -> Bool {
    var someShortcutTriggered = false
    for shortcut in ControlsTab.shortcuts.values {
        if shortcut.matches(id, shortcutState, keyCode, modifiers, isARepeat) && shortcut.shouldTrigger() {
            shortcut.executeAction(isARepeat)
            someShortcutTriggered = true
        }
    }
    return someShortcutTriggered
}

fileprivate func cgEventFlagsChangedHandler(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .flagsChanged {
        let modifiers = cocoaToCarbonFlags(NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue)))
        handleEvent(nil, nil, nil, modifiers, false)
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
}
