import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class KeyboardEvents {
    private static let signature = "altt".utf16.reduce(0) { ($0 << 8) + OSType($1) }
    // GetEventMonitorTarget/GetApplicationEventTarget also work, but require Accessibility Permission
    private static let shortcutEventTarget = GetEventDispatcherTarget()
    private static var eventHotKeyRefs = [String: EventHotKeyRef?]()
    private static var hotKeyPressedEventHandler: EventHandlerRef?
    private static var hotKeyReleasedEventHandler: EventHandlerRef?
    private static var globalShortcutsAreDisabled = false
    /// Permanent `.flagsChanged`-only tap on `cgSessionEventTap` + `.listenOnly` (the pre-11.0 config).
    /// Drives hold-shortcut triggering; never touches `.keyDown`, so it stays clear of input methods.
    private static var eventTap: CFMachPort?
    /// `.keyDown` tap on `cghidEventTap` + `.defaultTap`, used only to absorb Esc ahead of macOS 26
    /// Game Overlay (#5585). Created DISABLED; enabled only while a switcher session is open and a
    /// shortcut binds Esc (`updateEscapeAbsorptionTap`). Keeping this active HID keyDown tap out of
    /// normal typing is the #5766 fix (it was breaking third-party IMEs like Vietnamese EVKey).
    private static var escapeEventTap: CFMachPort?
    private static var localEventMonitor: Any?

    /// Set by `ControlsTab` when the configured shortcuts change. When true and `SwitcherSession.isActive`,
    /// our `escapeEventTap` absorbs Esc keyDowns and routes them through the matcher. Issue #5585:
    /// this is the only path that beats macOS 26 Game Overlay's hook on `⌘⎋`. Also gates whether
    /// `escapeEventTap` is enabled at all (see `updateEscapeAbsorptionTap`).
    static var anyShortcutUsesEscape = false

    private static let cgEventHandler: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
        case .flagsChanged:
            // TODO: it would be great to shortcut matching and trigger on the background thread
            // it would enable us to set App.shared.isBeingUsed here, and could stop tasks on main when they check the flag
            DispatchQueue.main.async {
                let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
                // TODO: ideally, we want to absorb all modifier keys except holdShortcut
                // it was pressed down before AltTab was triggered, so we should let the up event through
                handleKeyboardEvent(nil, nil, nil, modifiers, false)
            }
            return Unmanaged.passUnretained(cgEvent)
        case .keyDown:
            // Issue #5585. Esc only — absorb when AltTab is using it and a shortcut binds it. cghid is
            // the earliest tap point; absorbing here preempts macOS 26 Game Overlay's hook on `⌘⎋`.
            if cgEvent.getIntegerValueField(.keyboardEventKeycode) != Int64(kVK_Escape) ||
                !anyShortcutUsesEscape || !SwitcherSession.isActive {
                return Unmanaged.passUnretained(cgEvent)
            }
            let modifiers = NSEvent.ModifierFlags(rawValue: UInt(cgEvent.flags.rawValue))
            let isARepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat) != 0
            DispatchQueue.main.async {
                handleKeyboardEvent(nil, nil, UInt32(kVK_Escape), modifiers, isARepeat, nil)
            }
            return nil
        case .tapDisabledByUserInput, .tapDisabledByTimeout:
            reEnableTapIfNeeded()
            return Unmanaged.passUnretained(cgEvent)
        default:
            return Unmanaged.passUnretained(cgEvent)
        }
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

    static func reEnableTapIfNeeded() {
        if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            Logger.warning { "" }
        }
        updateEscapeAbsorptionTap()
    }

    /// Enables `escapeEventTap` only while it can do something useful: a switcher session is open AND
    /// a shortcut binds Esc. Outside that window it stays disabled, so the active HID `.keyDown` tap is
    /// never in the path during normal typing (#5766). Idempotent; safe from any thread; a no-op before
    /// the tap exists (e.g. unit tests that set `SwitcherSession.current` directly).
    static func updateEscapeAbsorptionTap() {
        guard let escapeEventTap else { return }
        let shouldEnable = anyShortcutUsesEscape && SwitcherSession.isActive
        if CGEvent.tapIsEnabled(tap: escapeEventTap) != shouldEnable {
            CGEvent.tapEnable(tap: escapeEventTap, enable: shouldEnable)
        }
    }

    static func addEventHandlers() {
        addLocalMonitorForKeyDownAndKeyUp()
        addCgEventTap()
    }

    private static func unregisterHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            let key = shortcut.carbonKeyCode
            let mods = shortcut.carbonModifierFlags
            if let ref = eventHotKeyRefs[controlId] {
                let status = UnregisterEventHotKey(ref)
                if status == noErr {
                    Logger.debug { "unregistered \(controlId) keyCode:\(key) modifiers:\(mods)" }
                } else {
                    Logger.error { "UnregisterEventHotKey failed for \(controlId) keyCode:\(key) modifiers:\(mods) status:\(status)" }
                }
                eventHotKeyRefs[controlId] = nil
            }
        }
    }

    private static func registerHotKeyIfNeeded(_ controlId: String, _ shortcut: Shortcut) {
        if shortcut.keyCode != .none {
            guard let id = KeyboardEventsTestable.globalShortcutsIds[controlId] else { return }
            let hotkeyId = EventHotKeyID(signature: signature, id: UInt32(id))
            let key = shortcut.carbonKeyCode
            let mods = shortcut.carbonModifierFlags
            let options = UInt32(kEventHotKeyNoOptions)
            var shortcutsReference: EventHotKeyRef?
            let status = RegisterEventHotKey(key, mods, hotkeyId, shortcutEventTarget, options, &shortcutsReference)
            if status == noErr {
                Logger.debug { "registered \(controlId) keyCode:\(key) modifiers:\(mods)" }
            } else {
                Logger.error { "RegisterEventHotKey failed for \(controlId) keyCode:\(key) modifiers:\(mods) status:\(status)" }
            }
            eventHotKeyRefs[controlId] = shortcutsReference
        }
    }

    // TODO: handle this on a background thread?
    private static func addLocalMonitorForKeyDownAndKeyUp() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { (event: NSEvent) in
            let keyCode = event.type == .keyDown ? UInt32(event.keyCode) : nil
            let isARepeat = event.type == .keyDown ? event.isARepeat : false
            let shouldAbsorbEvent = handleKeyboardEvent(nil, nil, keyCode, event.modifierFlags, isARepeat, event)
            return shouldAbsorbEvent ? nil : event
        }
    }

    private static func addCgEventTap() {
        // CGEvent.tapCreate returns null if ensureAccessibilityCheckboxIsChecked() didn't pass.
        // SecureInput does not block `.flagsChanged` on either cgSession or cghid taps; `.keyDown` is
        // filtered out at the system level for both.
        //
        // Two taps. The flags tap is the pre-11.0 config (cgSession + listenOnly): always on, drives
        // hold-shortcut triggering, never in the keyDown path. The Esc tap is cghid + defaultTap (the
        // only way to swallow Esc ahead of macOS 26 Game Overlay, #5585); it is created disabled and
        // only enabled while the switcher is open (updateEscapeAbsorptionTap), so it stays out of
        // normal typing and can't disturb third-party input methods (#5766).
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: cgEventHandler,
            userInfo: nil)
        guard let eventTap else { App.restart(); return }
        addToKeyboardRunLoop(eventTap)
        escapeEventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: cgEventHandler,
            userInfo: nil)
        guard let escapeEventTap else { App.restart(); return }
        CGEvent.tapEnable(tap: escapeEventTap, enable: false)
        addToKeyboardRunLoop(escapeEventTap)
        updateEscapeAbsorptionTap()
    }

    private static func addToKeyboardRunLoop(_ tap: CFMachPort) {
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(BackgroundWork.keyboardAndMouseAndTrackpadEventsThread.runLoop, runLoopSource, .commonModes)
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
