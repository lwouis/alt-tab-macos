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

    static func addGlobalShortcutIfNeeded(_ controlId: String, _ shortcut: Shortcut, checkEnabled: Bool = true, checkAnyModifierSide: Bool = true) {
        if
            shortcut.keyCode != .none, eventHotKeyRefs[controlId] == nil,
            !checkEnabled || !App.app.globalShortcutsAreDisabled,
            !checkAnyModifierSide || Preferences.shortcutModifierSide[Preferences.nameToIndex(controlId)] == .any
        {
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

    static func removeGlobalShortcutIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none, eventHotKeyRefs[controlId] != nil {
            UnregisterEventHotKey(eventHotKeyRefs[controlId]!)
            eventHotKeyRefs[controlId] = nil
        }
    }

    static func toggleGlobalShortcuts(_ shouldDisable: Bool) {
        if shouldDisable != App.app.globalShortcutsAreDisabled {
            for shortcutId in globalShortcutsIds.keys {
                if let shortcut = ControlsTab.shortcuts[shortcutId]?.shortcut {
                    if shouldDisable {
                        removeGlobalShortcutIfNeeded(shortcutId, shortcut)
                    } else {
                        addGlobalShortcutIfNeeded(shortcutId, shortcut, checkEnabled: false)
                    }
                }
            }
            debugPrint("toggleGlobalShortcuts", shouldDisable)
            App.app.globalShortcutsAreDisabled = shouldDisable
        }
    }

    static func addEventHandlers() {
        addLocalMonitorForKeyDownAndKeyUp()
        addGlobalHandler()
        addCgEventTapForModifierFlags()
    }

    private static func addLocalMonitorForKeyDownAndKeyUp() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { (event: NSEvent) in
            let someShortcutTriggered = handleEvent(nil, nil, event.type == .keyDown ? UInt32(event.keyCode) : nil, cocoaToCarbonFlags(event.modifierFlags), event.type == .keyDown ? event.isARepeat : false, .local)
            return someShortcutTriggered ? nil : event
        }
    }
    
    private static func addGlobalHandler() {
        var hotKeyPressedEventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))]
        InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            handleEvent(id, .down, nil, nil, false, .global)
            return noErr
        }, hotKeyPressedEventTypes.count, &hotKeyPressedEventTypes, nil, &hotKeyPressedEventHandler)
        var hotKeyReleasedEventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))]
        InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            handleEvent(id, .up, nil, nil, false, .global)
            return noErr
        }, hotKeyReleasedEventTypes.count, &hotKeyReleasedEventTypes, nil, &hotKeyReleasedEventHandler)
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
}

fileprivate func handleShortcutModifierSide(_ modifiers: NSEvent.ModifierFlags) {
    let sideModifiers: [(any: NSEvent.ModifierFlags, left: NSEvent.ModifierFlags, right: NSEvent.ModifierFlags)] = [
        (.shift, .leftShift, .rightShift),
        (.control, .leftControl, .rightControl),
        (.option, .leftOption, .rightOption),
        (.command, .leftCommand, .rightCommand)
    ]
    var removeShortcuts = [(id: String, shortcut: Shortcut)]()
    var addShortcuts = [(id: String, shortcut: Shortcut)]()
    for shortcutIndex in 0...4 {
        let shortcutModifierSide = Preferences.shortcutModifierSide[shortcutIndex]
        guard shortcutModifierSide != .any else {
            continue
        }
        let holdShortcutId = Preferences.indexToName("holdShortcut", shortcutIndex)
        let nextWindowShortcutId = Preferences.indexToName("nextWindowShortcut", shortcutIndex)
        guard
            let holdShortcut = ControlsTab.shortcuts[holdShortcutId],
            let nextWindowShortcut = ControlsTab.shortcuts[nextWindowShortcutId]
        else {
            continue
        }
        if
            (sideModifiers.filter {
                holdShortcut.shortcut.modifierFlags.contains($0.any)
            }.allSatisfy {
                modifiers.contains(shortcutModifierSide == .left ? $0.left : $0.right) &&
                !modifiers.contains(shortcutModifierSide == .left ? $0.right : $0.left)
            })
        {
            addShortcuts.append((nextWindowShortcutId, nextWindowShortcut.shortcut))
        } else {
            if holdShortcut.shouldTrigger() {
                holdShortcut.executeAction(false)
            }
            removeShortcuts.append((nextWindowShortcutId, nextWindowShortcut.shortcut))
        }
    }
    removeShortcuts.forEach {
        KeyboardEvents.removeGlobalShortcutIfNeeded($0.id, $0.shortcut)
    }
    addShortcuts.forEach {
        KeyboardEvents.addGlobalShortcutIfNeeded($0.id, $0.shortcut, checkAnyModifierSide: false)
    }
}

@discardableResult
fileprivate func handleEvent(_ id: EventHotKeyID?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: UInt32?, _ isARepeat: Bool, _ shortcutScope: ShortcutScope) -> Bool {
    var someShortcutTriggered = false
    for shortcut in ControlsTab.shortcuts.values {
        if shortcut.matches(id, shortcutState, keyCode, modifiers, isARepeat, shortcutScope) && shortcut.shouldTrigger() {
            shortcut.executeAction(isARepeat)
            someShortcutTriggered = true
        }
    }
    return someShortcutTriggered
}

fileprivate func cgEventFlagsChangedHandler(proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .flagsChanged {
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
        handleShortcutModifierSide(modifiers)
        handleEvent(nil, nil, nil, cocoaToCarbonFlags(modifiers), false, .global)
    } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
}
