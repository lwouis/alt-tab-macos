import Cocoa
import ShortcutRecorder

class KeyRepeatTimer {
    static var timer: Timer?
    static var isARepeat = false

    static func toggleRepeatingKeyPreviousWindow() {
        if let shortcut = ControlsTab.shortcuts["previousWindowShortcut"],
           // events already repeat when using a shortcut with a keycode; no need for artificial repeat
           shortcut.shortcut.keyCode == .none {
            toggleRepeatingKey(shortcut) {
                App.app.previousWindowShortcutWithRepeatingKey()
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
            timer = Timer(fire: Date(timeIntervalSinceNow: initialDelay), interval: repeatRate, repeats: true) { _ in
                handleEvent(atShortcut, block)
            }
            timer!.tolerance = repeatRate * 0.1
            CFRunLoopAddTimer(BackgroundWork.repeatingKeyThread.runLoop, timer!, .commonModes)
        }
    }

    private static func handleEvent(_ atShortcut: ATShortcut, _ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            if atShortcut.state == .up {
                timer?.invalidate()
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
