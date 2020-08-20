import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

fileprivate var eventTap: CFMachPort?

class KeyboardEvents {
    static let signature = "altt".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    // GetEventMonitorTarget/GetApplicationEventTarget also work, but require Accessibility Permission
    static let shortcutEventTarget = GetEventDispatcherTarget()
    static let globalShortcuts = [
        "nextWindowShortcut": 0,
        "nextWindowShortcut2": 1,
        "holdShortcut": 2,
        "holdShortcut2": 3,
    ]
    static var holdShortcutWasDown = [2: false, 3: false]
    static var eventHotKeyRefs = [EventHotKeyRef?](repeating: nil, count: globalShortcuts.count)
    static var hotModifierEventHandler: EventHandlerRef?
    static var hotKeyEventHandler: EventHandlerRef?
    static var localMonitor: Any?

    static func observe() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // global .flagsChanged events are not send to the app when it's active, thus modifiers-only shortcuts should be matched in global and local handlers
            if handleHotModifier(cocoaToCarbonFlags(event.modifierFlags)) || handleLocalEvents(event) {
                return nil // don't propagate event
            }
            return event // propagate event
        }
    }

    static func addGlobalShortcut(_ shortcut: Shortcut, _ id: Int) {
        addHandlerIfNeeded(shortcut)
        registerHotKeyIfNeeded(id, shortcut)
        toggleNativeCommandTabIfNeeded(shortcut, false)
    }

    static func removeGlobalShortcut(_ id: Int, _ shortcut: Shortcut) {
        UnregisterEventHotKey(eventHotKeyRefs[id])
        eventHotKeyRefs[id] = nil
        removeHandlerIfNeeded()
        toggleNativeCommandTabIfNeeded(shortcut, true)
    }

    private static func registerHotKeyIfNeeded(_ id: Int, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            let hotkeyId = EventHotKeyID(signature: signature, id: UInt32(id))
            let key = UInt32(shortcut.carbonKeyCode)
            let mods = UInt32(shortcut.carbonModifierFlags)
            let options = UInt32(kEventHotKeyNoOptions)
            var shortcutsReference: EventHotKeyRef?
            RegisterEventHotKey(key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
            eventHotKeyRefs[id] = shortcutsReference
        }
    }

    private static func toggleNativeCommandTabIfNeeded(_ shortcut: Shortcut, _ enabled: Bool) {
        if (shortcut.carbonModifierFlags == cmdKey || shortcut.carbonModifierFlags == (cmdKey | shiftKey)) && shortcut.carbonKeyCode == kVK_Tab {
            setNativeCommandTabEnabled(enabled)
        }
    }

    private static func addHandlerIfNeeded(_ shortcut: Shortcut) {
        if shortcut.keyCode == .none && hotModifierEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventRawKeyModifiersChanged))]
            InstallEventHandler(GetEventMonitorTarget(), { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                if !App.app.shortcutsShouldBeDisabled {
                    var modifiers = UInt32(0)
                    GetEventParameter(event, EventParamName(kEventParamKeyModifiers), EventParamType(typeUInt32), nil, MemoryLayout<UInt32>.size, nil, &modifiers)
                    _ = handleHotModifier(modifiers)
                }
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotModifierEventHandler)
        }
        if shortcut.keyCode != .none && hotKeyEventHandler == nil {
            var eventTypes = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))]
            InstallEventHandler(shortcutEventTarget, { (_: EventHandlerCallRef?, event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                if !App.app.shortcutsShouldBeDisabled {
                    var id = EventHotKeyID()
                    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                    handleHotKey(id)
                }
                return noErr
            }, eventTypes.count, &eventTypes, nil, &hotKeyEventHandler)
        }
    }

    private static func removeHandlerIfNeeded() {
        if let hotKeyEventHandler_ = hotKeyEventHandler, (ControlsTab.globalShortcuts.values.allSatisfy { $0.keyCode == .none }) {
            RemoveEventHandler(hotKeyEventHandler_)
            hotKeyEventHandler = nil
        } else if let hotModifierEventHandler_ = hotModifierEventHandler, (ControlsTab.globalShortcuts.values.allSatisfy { $0.keyCode != .none }) {
            RemoveEventHandler(hotModifierEventHandler_)
            hotModifierEventHandler = nil
        }
    }
}

fileprivate func handleHotModifier(_ modifiers: UInt32) -> Bool {
    for (key, value) in ControlsTab.globalShortcuts {
        if value.keyCode != .none { continue }
        let shortcutIndex = KeyboardEvents.globalShortcuts[key]!
        // modifiers down
        if value.carbonModifierFlags == modifiers {
            if key.hasPrefix("holdShortcut") {
                KeyboardEvents.holdShortcutWasDown[shortcutIndex] = true
            } else {
                if handleHotAny(key, shortcutIndex) {
                    return true
                }
            }
        }
        // modifiers up
        else if key.hasPrefix("holdShortcut") && (modifiers & value.carbonModifierFlags == 0) && KeyboardEvents.holdShortcutWasDown[shortcutIndex]! {
            KeyboardEvents.holdShortcutWasDown[shortcutIndex] = false
            if Preferences.shortcutStyle == .focusOnRelease && handleHotAny(key, shortcutIndex) {
                return true
            }
        }
    }
    return false
}

fileprivate func handleHotKey(_ id: EventHotKeyID) {
    let shortcutIndex = Int(id.id)
    let key = Array(KeyboardEvents.globalShortcuts).first { $0.value == shortcutIndex }!.key
    _ = handleHotAny(key, shortcutIndex)
}

fileprivate func handleHotAny_(_ key: String, _ shortcutIndex: Int) -> Bool {
    if key.hasPrefix("nextWindowShortcut") {
        if (!App.app.appIsBeingUsed || App.app.shortcutIndex == (shortcutIndex % 2)) {
            App.app.appIsBeingUsed = true
            return true
        }
    } else {
        if App.app.appIsBeingUsed && App.app.shortcutIndex == (shortcutIndex % 2) {
            return true
        }
    }
    return false
}

fileprivate func localShortcutThatMatches(_ event: NSEvent) -> String? {
    for (shortcutId, shortcut) in ControlsTab.localShortcuts {
        if shortcutId.hasPrefix("holdShortcut") {
            let postfix = App.app.shortcutIndex == 0 ? "" : "2"
            if event.sr_keyEventType == .up && event.type == .flagsChanged && shortcut.keyCode == .none && event.modifierFlags.isDisjoint(with: shortcut.modifierFlags) &&
                   shortcutId == "holdShortcut" + postfix && App.app.appIsBeingUsed && Preferences.shortcutStyle == .focusOnRelease {
                return shortcutId
            }
        } else if event.sr_keyEventType == .down && (shortcut.keyCode == .none || event.keyCode == shortcut.carbonKeyCode) &&
                      event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(shortcut.modifierFlags) &&
                      App.app.appIsBeingUsed {
            return shortcutId
        }
    }
    return nil
}

fileprivate func handleHotAny(_ shortcutId: String, _ shortcutIndex: Int) -> Bool {
    return executeActionIfShould(handleHotAny_(shortcutId, shortcutIndex) ? shortcutId : nil)
}

fileprivate func handleLocalEvents(_ event: NSEvent) -> Bool {
    return executeActionIfShould(localShortcutThatMatches(event))
}

fileprivate func executeActionIfShould(_ shortcutId: String?) -> Bool {
    if let shortcutId = shortcutId {
        DispatchQueue.main.async { () -> () in ControlsTab.shortcutsActions[shortcutId]!() }
        return true
    }
    return false
}
