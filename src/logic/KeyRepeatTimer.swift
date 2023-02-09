import Cocoa
import ShortcutRecorder

class KeyRepeatTimer {
    static var timer: Timer?
    static var isARepeat = false

    static func toggleRepeatingKeyPreviousWindow(_ shortcutIndex: Int) {
        if let shortcut = ControlsTab.shortcuts[Preferences.indexToName("previousWindowShortcut", shortcutIndex)],
           // events already repeat when using a shortcut with a keycode; no need for artificial repeat
           shortcut.shortcut.keyCode == .none {
            toggleRepeatingKey(shortcut) {
                ControlsTab.shortcutsActions[Preferences.indexToName("previousWindowShortcut", shortcutIndex)]!()
            }
        }
    }

    static func toggleRepeatingKeyNextWindow() {
        if let shortcut = ControlsTab.shortcuts[Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex)] {
            toggleRepeatingKey(shortcut) {
                ControlsTab.shortcutsActions[Preferences.indexToName("nextWindowShortcut", App.app.shortcutIndex)]!()
            }
        }
    }

    private static func toggleRepeatingKey(_ atShortcut: ATShortcut, _ block: @escaping () -> Void) {
        if ((timer == nil || !timer!.isValid) && atShortcut.state != .up) {
            let repeatRate = ticksToSeconds(defaults.string(forKey: "KeyRepeat") ?? "6")
            let initialDelay = ticksToSeconds(defaults.string(forKey: "InitialKeyRepeat") ?? "25")
            timer = Timer(fire: Date(timeIntervalSinceNow: initialDelay), interval: repeatRate, repeats: true, block: { _ in
                if atShortcut.state == .up {
                    timer?.invalidate()
                } else {
                    DispatchQueue.main.async {
                        block()
                    }
                }
            })
            CFRunLoopAddTimer(BackgroundWork.repeatingKeyThread.runLoop, timer!, .defaultMode)
        }
    }

    private static func ticksToSeconds(_ appleNumber: String) -> Double {
        return Double(appleNumber)! / 60 // Apple probably hard-coupled key repeat-rate with 60hz monitors
    }
}
