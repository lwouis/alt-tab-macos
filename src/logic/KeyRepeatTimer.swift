import Cocoa
import ShortcutRecorder

class KeyRepeatTimer {
    static var timer = DispatchSource.makeTimerSource(queue: BackgroundWork.repeatingKeyQueue.strongUnderlyingQueue)
    static var timerIsSuspended = true
    static var currentTimerShortcutName: String?

    static func startRepeatingKeyPreviousWindow() {
        if let shortcut = ControlsTab.shortcuts["previousWindowShortcut"],
           // events already repeat when using a shortcut with a keycode; no need for artificial repeat
           shortcut.shortcut.keyCode == .none {
            startTimerForRepeatingKey(shortcut) {
                App.app.previousWindowShortcutWithRepeatingKey()
            }
        }
    }

    static func startRepeatingKeyNextWindow() {
        if let shortcut = ControlsTab.shortcuts[Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex)] {
            startTimerForRepeatingKey(shortcut) {
                ControlsTab.executeAction(Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex))
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
        guard timerIsSuspended && atShortcut.state != .up else { return }
        currentTimerShortcutName = atShortcut.id
        // reading these user defaults every time guarantees we have the latest value, if the user has updated those
        let repeatRate = ticksToSeconds(CachedUserDefaults.globalString("KeyRepeat") ?? "6")
        let initialDelay = ticksToSeconds(CachedUserDefaults.globalString("InitialKeyRepeat") ?? "25")
        Logger.debug { "\(currentTimerShortcutName) repeatRate:\(repeatRate)s initialDelay:\(initialDelay)s" }
        timer.schedule(deadline: .now() + initialDelay, repeating: repeatRate, leeway: .milliseconds(Int(repeatRate * 1000 / 10)))
        timer.setEventHandler { handleEvent(atShortcut, block) }
        timer.resume()
        timerIsSuspended = false
    }

    private static func handleEvent(_ atShortcut: ATShortcut, _ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            if atShortcut.state == .up {
                stopTimerForRepeatingKey(atShortcut.id)
            } else {
                block()
            }
        }
    }

    // NSEvent.keyRepeatInterval exists, but it doesn't seem to update when System Settings are updated, or when the user runs `defaults write -g KeyRepeat X`
    // On the other side, defaults.string(forKey: "KeyRepeat") always reflects the current value correctly
    private static func ticksToSeconds(_ appleNumber: String) -> Double {
        // These numbers are "ticks". Apple has hardcoded that 60 ticks == 1s
        // It has stayed like this on recent macOS releases, and is the same on high refresh-rate monitors (e.g. 120 FPS)
        return Double(appleNumber)! / 60
    }
}
