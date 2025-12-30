import Cocoa
import ShortcutRecorder

class KeyboardEvents {
    private static let signature = "altt".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    // GetEventMonitorTarget/GetApplicationEventTarget also work, but require Accessibility Permission
    private static let shortcutEventTarget = GetEventDispatcherTarget()
    private static var eventHotKeyRefs = [String: EventHotKeyRef?]()
    private static var hotKeyPressedEventHandler: EventHandlerRef?
    private static var hotKeyReleasedEventHandler: EventHandlerRef?
    private static var globalShortcutsAreDisabled = false
    private static var eventTap: CFMachPort?

    private static let cgEventFlagsChangedHandler: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type == .flagsChanged {
            // TODO: it would be great to shortcut matching and trigger on the background thread
            // it would enable us to set App.app.isBeingUsed here, and could stop tasks on main when they check the flag
            DispatchQueue.main.async {
                let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
                // TODO: ideally, we want to absorb all modifier keys except holdShortcut
                // it was pressed down before AltTab was triggered, so we should let the up event through
                handleKeyboardEvent(nil, nil, nil, modifiers, false)
            }
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        // we always return this because we want to let these event pass through to the currently focused app
        return Unmanaged.passUnretained(cgEvent)
    }

    static func addGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        addGlobalHandlerIfNeeded(shortcut)
        registerHotKeyIfNeeded(controlId, shortcut)
    }

    static func removeGlobalShortcut(_ controlId: String, _ shortcut: Shortcut) {
        unregisterHotKeyIfNeeded(controlId, shortcut)
        removeHandlerIfNeeded()
    }

    static func toggleGlobalShortcuts(_ shouldDisable: Bool) {
        if shouldDisable != globalShortcutsAreDisabled {
            let fn = shouldDisable ? unregisterHotKeyIfNeeded : registerHotKeyIfNeeded
            for shortcutId in KeyboardEventsTestable.globalShortcutsIds.keys {
                if let shortcut = ControlsTab.shortcuts[shortcutId]?.shortcut {
                    fn(shortcutId, shortcut)
                }
            }
            Logger.info { "disabled:\(shouldDisable)" }
            globalShortcutsAreDisabled = shouldDisable
        }
    }

    static func addEventHandlers() {
        addLocalMonitorForKeyDownAndKeyUp()
        addCgEventTapForModifierFlags()
    }

    private static func unregisterHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            UnregisterEventHotKey(eventHotKeyRefs[controlId]!)
            eventHotKeyRefs[controlId] = nil
        }
    }

    private static func registerHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            let id = KeyboardEventsTestable.globalShortcutsIds[controlId]!
            let hotkeyId = EventHotKeyID(signature: signature, id: UInt32(id))
            let key = shortcut.carbonKeyCode
            let mods = shortcut.carbonModifierFlags
            let options = UInt32(kEventHotKeyNoOptions)
            var shortcutsReference: EventHotKeyRef?
            RegisterEventHotKey(key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
            eventHotKeyRefs[controlId] = shortcutsReference
        }
    }

    // TODO: handle this on a background thread?
    private static func addLocalMonitorForKeyDownAndKeyUp() {
        NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { (event: NSEvent) in
            let someShortcutTriggered = handleKeyboardEvent(nil, nil, event.type == .keyDown ? UInt32(event.keyCode) : nil, event.modifierFlags, event.type == .keyDown ? event.isARepeat : false)
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
        if let eventTap {
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
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
                handleKeyboardEvent(Int(id.id), .down, nil, nil, false)
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotKeyPressedEventHandler)
        }
        if shortcut.keyCode != .none && hotKeyReleasedEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyReleased))]
            InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                handleKeyboardEvent(Int(id.id), .up, nil, nil, false)
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
