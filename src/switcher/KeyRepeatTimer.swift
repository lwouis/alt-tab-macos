import Cocoa
import Carbon.HIToolbox.Events
import ShortcutRecorder

class KeyRepeatTimer {
    static var timer = DispatchSource.makeTimerSource(queue: BackgroundWork.repeatingKeyQueue.strongUnderlyingQueue)
    static var timerIsSuspended = true
    static var currentTimerShortcutName: String?
    /// `systemUptime` when the current timer was armed, and its initial-delay — captured so `handleEvent` can
    /// gate each artificial repeat on how long the panel has actually been VISIBLE
    /// (`KeyRepeatTimerTestable.shouldApplyArtificialRepeat`), rather than blindly firing at the timer's
    /// arm-relative schedule.
    static var armedAt: TimeInterval = 0
    static var currentInitialDelay: TimeInterval = 0
    /// True only for the duration of a synthesized repeat tick. `CycleWrapResolver` gates wrap-around on
    /// this rather than on `timerIsSuspended`: a modifier-only shortcut keeps its timer armed for the whole
    /// time the key is held, so armed-ness cannot tell a repeat apart from a real press landing mid-hold.
    static var isFiringArtificialRepeat = false

    static func startRepeatingKeyPreviousWindow() {
        if let shortcut = ControlsTab.shortcuts["previousWindowShortcut"],
           // events already repeat when using a shortcut with a keycode; no need for artificial repeat
           shortcut.shortcut.keyCode == .none {
            startTimerForRepeatingKey(shortcut) {
                App.previousWindowShortcutWithRepeatingKey()
            }
        }
    }

    static func startRepeatingKeyNextWindow() {
        let nextWindowShortcutName = Preferences.indexToName("nextWindowShortcut", SwitcherSession.current?.shortcutIndex ?? 0)
        if let shortcut = ControlsTab.shortcuts[nextWindowShortcutName],
           // Esc is delivered via the cghid event tap (#5585), which emits real OS key-repeats; an artificial
           // timer would never stop, because the absorbed keyDown gives Carbon no release event to pair with,
           // so it cycles selection to the very end (#5742). Same rationale as startRepeatingKeyPreviousWindow().
           shortcut.shortcut.carbonKeyCode != kVK_Escape {
            startTimerForRepeatingKey(shortcut) {
                ShortcutActions.execute(Preferences.indexToName("nextWindowShortcut", SwitcherSession.current?.shortcutIndex ?? 0))
            }
        }
    }

    static func stopTimerForRepeatingKey(_ shortcutName: String) {
        if shortcutName == currentTimerShortcutName {
            Logger.debug { shortcutName }
            currentTimerShortcutName = nil
            timer.suspend()
            timerIsSuspended = true
        }
    }

    private static func startTimerForRepeatingKey(_ atShortcut: ATShortcut, _ block: @escaping () -> Void) {
        guard timerIsSuspended && atShortcut.state != .up && (atShortcut.scope == .local || !holdModifierIsReleased()) else { return }
        currentTimerShortcutName = atShortcut.id
        // reading these user defaults every time guarantees we have the latest value, if the user has updated those
        let repeatRate = ticksToSeconds(CachedUserDefaults.globalString("KeyRepeat") ?? "6")
        let initialDelay = ticksToSeconds(CachedUserDefaults.globalString("InitialKeyRepeat") ?? "25")
        armedAt = ProcessInfo.processInfo.systemUptime
        currentInitialDelay = initialDelay
        Logger.debug { "\(currentTimerShortcutName) repeatRate:\(repeatRate)s initialDelay:\(initialDelay)s" }
        timer.schedule(deadline: .now() + initialDelay, repeating: repeatRate, leeway: .milliseconds(Int(repeatRate * 1000 / 10)))
        timer.setEventHandler { handleEvent(atShortcut, block) }
        timer.resume()
        timerIsSuspended = false
    }

    private static func handleEvent(_ atShortcut: ATShortcut, _ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            if atShortcut.state == .up || (atShortcut.scope == .global && holdModifierIsReleased()) {
                stopTimerForRepeatingKey(atShortcut.id)
            } else if KeyRepeatTimerTestable.shouldApplyArtificialRepeat(now: ProcessInfo.processInfo.systemUptime,
                armedAt: armedAt, panelBecameVisibleAt: SwitcherSession.current?.panelBecameVisibleAt,
                panelShownAt: SwitcherSession.current?.panelShownAt, initialDelay: currentInitialDelay) {
                isFiringArtificialRepeat = true
                defer { isFiringArtificialRepeat = false }
                block()
            }
            // else: the panel hasn't been VISIBLE for the initial-delay grace yet (a slow show swallowed it);
            // skip this tick but keep the timer running so a later tick re-checks once the grace truly elapses.
        }
    }

    /// Poll hardware modifier state to detect key release even when the event-based state update is delayed
    /// (e.g. when main thread is busy under CPU stress). Mirrors ATShortcut.redundantSafetyMeasures()
    private static func holdModifierIsReleased() -> Bool {
        guard let session = SwitcherSession.current,
              let holdShortcut = ControlsTab.shortcuts[Preferences.indexToName("holdShortcut", session.shortcutIndex)] else {
            return true
        }
        let currentModifiers = cocoaToCarbonFlags(ModifierFlags.current).cleaned()
        let holdModifiers = holdShortcut.shortcut.carbonModifierFlags.cleaned()
        return currentModifiers & holdModifiers != holdModifiers
    }

    // NSEvent.keyRepeatInterval exists, but it doesn't seem to update when System Settings are updated, or when the user runs `defaults write -g KeyRepeat X`
    // On the other side, defaults.string(forKey: "KeyRepeat") always reflects the current value correctly
    private static func ticksToSeconds(_ appleNumber: String) -> Double {
        // These numbers are "ticks". Apple has hardcoded that 60 ticks == 1s
        // It has stayed like this on recent macOS releases, and is the same on high refresh-rate monitors (e.g. 120 FPS)
        return Double(appleNumber)! / 60
    }
}
