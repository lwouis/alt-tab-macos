import Cocoa
import ShortcutRecorder

private var eventTap: CFMachPort?

class KeyboardEvents {
    static let signature = "altt".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    // GetEventMonitorTarget/GetApplicationEventTarget also work, but require Accessibility Permission
    static let shortcutEventTarget = GetEventDispatcherTarget()
    static let globalShortcutsIds = [
        "nextWindowShortcut": 0,
        "nextWindowShortcut2": 1,
        "holdShortcut": 2,
        "holdShortcut2": 3,
    ]
    static var eventHotKeyRefs = [String: EventHotKeyRef?]()
    static var hotKeyPressedEventHandler: EventHandlerRef?
    static var hotKeyReleasedEventHandler: EventHandlerRef?
    static var localMonitor: Any!

    static func addGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        addGlobalHandlerIfNeeded(shortcut)
        registerHotKeyIfNeeded(controlId, shortcut)
        toggleNativeCommandTabIfNeeded(shortcut, false)
    }

    static func removeGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        unregisterHotKeyIfNeeded(controlId, shortcut)
        removeHandlerIfNeeded()
        toggleNativeCommandTabIfNeeded(shortcut, true)
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
            let key = UInt32(shortcut.carbonKeyCode)
            let mods = UInt32(shortcut.carbonModifierFlags)
            let options = UInt32(kEventHotKeyNoOptions)
            var shortcutsReference: EventHotKeyRef?
            RegisterEventHotKey(
                key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
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

    private static func toggleNativeCommandTabIfNeeded(_ shortcut: Shortcut, _ enabled: Bool) {
        if (shortcut.carbonModifierFlags == cmdKey
            || shortcut.carbonModifierFlags == (cmdKey | shiftKey))
            && shortcut.carbonKeyCode == kVK_Tab
        {
            setNativeCommandTabEnabled(enabled)
        }
    }

    static func addEventHandlers() {
        addLocalMonitorForKeyDownAndKeyUp()
        addCgEventTapForModifierFlags()
    }

    private static func addLocalMonitorForKeyDownAndKeyUp() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            return handleEvent(
                nil, nil, event.type == .keyDown ? UInt32(event.keyCode) : nil,
                cocoaToCarbonFlags(event.modifierFlags),
                event.type == .keyDown ? event.isARepeat : false) ? nil : event
        }
    }

    private static func addCgEventTapForModifierFlags() {
        let eventMask = [CGEventType.flagsChanged].reduce(
            CGEventMask(0), { $0 | (1 << $1.rawValue) })
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass
        // CGEvent.tapCreate is unaffected by SecureInput for .flagsChanged
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: cgEventFlagsChangedHandler,
            userInfo: nil)
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    private static func addGlobalHandlerIfNeeded(_ shortcut: Shortcut) {
        if shortcut.keyCode != .none && hotKeyPressedEventHandler == nil {
            var eventTypes = [
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            ]
            InstallEventHandler(
                shortcutEventTarget,
                {
                    (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?)
                        -> OSStatus in
                    var id = EventHotKeyID()
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                        nil, &id)
                    handleEvent(id, .down, nil, nil, false)
                    return noErr
                }, eventTypes.count, &eventTypes, nil, &hotKeyPressedEventHandler)
        }
        if shortcut.keyCode != .none && hotKeyReleasedEventHandler == nil {
            var eventTypes = [
                EventTypeSpec(
                    eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased)
                )
            ]
            InstallEventHandler(
                shortcutEventTarget,
                {
                    (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?)
                        -> OSStatus in
                    var id = EventHotKeyID()
                    GetEventParameter(
                        event, EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size,
                        nil, &id)
                    handleEvent(id, .up, nil, nil, false)
                    return noErr
                }, eventTypes.count, &eventTypes, nil, &hotKeyReleasedEventHandler)
        }
    }

    private static func removeHandlerIfNeeded() {
        let globalShortcuts = ControlsTab.shortcuts.values.filter { $0.scope == .global }
        if let hotKeyPressedEventHandler_ = hotKeyPressedEventHandler,
            let hotKeyReleasedEventHandler_ = hotKeyReleasedEventHandler,
            (globalShortcuts.allSatisfy { $0.shortcut.keyCode == .none })
        {
            RemoveEventHandler(hotKeyPressedEventHandler_)
            hotKeyPressedEventHandler = nil
            RemoveEventHandler(hotKeyReleasedEventHandler_)
            hotKeyReleasedEventHandler = nil
        }
    }
}

@discardableResult
private func handleEvent(
    _ id: EventHotKeyID?, _ shortcutState: ShortcutState?, _ keyCode: UInt32?, _ modifiers: UInt32?,
    _ isARepeat: Bool
) -> Bool {
    var someShortcutTriggered = false
    for shortcut in ControlsTab.shortcuts.values {
        if shortcut.matches(id, shortcutState, keyCode, modifiers, isARepeat)
            && shortcut.shouldTrigger()
        {
            shortcut.executeAction(isARepeat)
            someShortcutTriggered = true
        }
    }
    return someShortcutTriggered
}

private func cgEventFlagsChangedHandler(
    proxy: CGEventTapProxy, type: CGEventType, cgEvent: CGEvent, userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .flagsChanged {
        let modifiers = cocoaToCarbonFlags(
            NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue)))
        if handleEvent(nil, nil, nil, modifiers, false) {
            return nil  // focused app won't receive the event
        }
    } else if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        CGEvent.tapEnable(tap: eventTap!, enable: true)
    }
    return Unmanaged.passUnretained(cgEvent)  // focused app will receive the event
}
