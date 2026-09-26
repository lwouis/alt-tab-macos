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
    static var currentRepeatRate: TimeInterval = 0

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
        // The fallbacks are macOS's own defaults, for a machine that has never had these set. They are NOT
        // what a user with custom key-repeat settings should get: `CachedUserDefaults.globalString` used to
        // return nil on its first read, so every launch's first hold-cycle ran at these instead.
        // Read per arm, but served from the cache after the first time, so a change made in System Settings
        // mid-session isn't picked up until relaunch.
        let repeatRate = ticksToSeconds(CachedUserDefaults.globalString("KeyRepeat") ?? "6")
        let initialDelay = ticksToSeconds(CachedUserDefaults.globalString("InitialKeyRepeat") ?? "25")
        armedAt = ProcessInfo.processInfo.systemUptime
        currentInitialDelay = initialDelay
        currentRepeatRate = repeatRate
        Logger.debug { "\(currentTimerShortcutName) repeatRate:\(repeatRate)s initialDelay:\(initialDelay)s" }
        scheduleTick(initialDelay)
        timer.setEventHandler { handleEvent(atShortcut, block) }
        timer.resume()
        timerIsSuspended = false
    }

    /// **One tick in flight at a time: the timer re-arms itself once the main thread has HANDLED a tick,
    /// rather than firing on a fixed repeating schedule.** The handler hops to main, and a repeating source
    /// keeps firing on its background queue while main is busy — so a stall piles up one queued block per
    /// missed interval, and the run loop then runs all of them before it reads the key-up that would have
    /// stopped them (#5977). Re-arming from the handler means a stall simply delays the next tick.
    ///
    /// The cost is that the interval is measured handler-to-handler rather than fire-to-fire, so it drifts by
    /// however long a cycle takes. That is sub-millisecond work against a 33-500ms `KeyRepeat`.
    private static func scheduleTick(_ delay: TimeInterval) {
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(Int(currentRepeatRate * 1000 / 10)))
    }

    private static func handleEvent(_ atShortcut: ATShortcut, _ block: @escaping () -> Void) {
        let firedAt = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async {
            if KeyRepeatTimerTestable.shouldStop(shortcutIsUp: atShortcut.state == .up,
                keyIsPhysicallyDown: keyIsPhysicallyDown(atShortcut),
                holdModifierIsReleased: atShortcut.scope == .global && holdModifierIsReleased()) {
                stopTimerForRepeatingKey(atShortcut.id)
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            if KeyRepeatTimerTestable.shouldApplyArtificialRepeat(now: now, firedAt: firedAt,
                armedAt: armedAt, panelBecameVisibleAt: SwitcherSession.current?.panelBecameVisibleAt,
                panelShownAt: SwitcherSession.current?.panelShownAt, initialDelay: currentInitialDelay,
                repeatRate: currentRepeatRate) {
                block()
            } else {
                // Either the panel hasn't been VISIBLE for the initial-delay grace yet (a slow show swallowed
                // it), or this tick reached main too late to stand for a key still held. Logged because the
                // symptom of applying it anyway is a selection that walked several tiles on its own, and
                // nothing in a capture said the app had been unable to answer in between.
                Logger.debug { "skipped repeat late:\(String(format: "%.3f", now - firedAt))s" }
            }
            scheduleNextTick(atShortcut.id)
        }
    }

    /// Re-arm for the next repeat, unless the tick we just handled ended the timer (`block()` can hide the
    /// switcher, and `stopTimerForRepeatingKey` runs on this same thread).
    private static func scheduleNextTick(_ shortcutName: String) {
        guard !timerIsSuspended, currentTimerShortcutName == shortcutName else { return }
        scheduleTick(currentRepeatRate)
    }

    /// nil for a modifier-only shortcut, which has no key of its own to read.
    private static func keyIsPhysicallyDown(_ atShortcut: ATShortcut) -> Bool? {
        guard atShortcut.shortcut.keyCode != .none else { return nil }
        return CGEventSource.keyState(.hidSystemState, key: CGKeyCode(atShortcut.shortcut.carbonKeyCode))
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
