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
        "holdShortcut": 2,
        "holdShortcut2": 3,
    ]
    static var eventHotKeyRefs = [String: EventHotKeyRef?]()
    static var hotModifierEventHandler: EventHandlerRef?
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
            RegisterEventHotKey(key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
            eventHotKeyRefs[controlId] = shortcutsReference
        }
    }

    static func toggleGlobalShortcuts(_ shouldDisable: Bool) {
        if shouldDisable != App.app.globalShortcutsAreDisabled {
            let fn = shouldDisable ? unregisterHotKeyIfNeeded : registerHotKeyIfNeeded
            for shortcutId in globalShortcutsIds.keys {
                let shortcut = ControlsTab.shortcuts[shortcutId]!.shortcut
                fn(shortcutId, shortcut)
            }
            debugPrint("toggleGlobalShortcuts", shouldDisable)
            App.app.globalShortcutsAreDisabled = shouldDisable
        }
    }

    private static func toggleNativeCommandTabIfNeeded(_ shortcut: Shortcut, _ enabled: Bool) {
        if (shortcut.carbonModifierFlags == cmdKey || shortcut.carbonModifierFlags == (cmdKey | shiftKey)) && shortcut.carbonKeyCode == kVK_Tab {
            setNativeCommandTabEnabled(enabled)
        }
    }

    static func addLocalEventHandler() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            return handleEvent(nil, nil, event.type == .keyDown ? UInt32(event.keyCode) : nil, cocoaToCarbonFlags(event.modifierFlags), event.type == .keyDown ? event.isARepeat : false) ? nil : event
        }
    }

    private static func addGlobalHandlerIfNeeded(_ shortcut: Shortcut) {
        if shortcut.keyCode == .none && hotModifierEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventRawKeyModifiersChanged))]
            InstallEventHandler(GetEventMonitorTarget(), { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var modifiers = UInt32(0)
                GetEventParameter(event, EventParamName(kEventParamKeyModifiers), EventParamType(typeUInt32), nil, MemoryLayout<UInt32>.size, nil, &modifiers)
                handleEvent(nil, nil, nil, modifiers, false)
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotModifierEventHandler)
        }
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
        } else if let hotModifierEventHandler_ = hotModifierEventHandler, (globalShortcuts.allSatisfy { $0.shortcut.keyCode != .none }) {
            RemoveEventHandler(hotModifierEventHandler_)
            hotModifierEventHandler = nil
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
