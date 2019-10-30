import Cocoa
import ShortcutRecorder

class Keyboard {
    static func listenToGlobalEvents(_ delegate: Application) {
        addShortcut("⌥⇥", { delegate.showUiOrSelectNext() }, .down)
        addShortcut("⌥⇧⇥", { delegate.showUiOrSelectPrevious() }, .down)
        addShortcut("⌥→", { delegate.cycleSelection(1) }, .down)
        addShortcut("⌥←", { delegate.cycleSelection(-1) }, .down)
        addShortcut("⌥⎋", { delegate.hideUi() }, .down)
        addShortcut("⌥⇥", { delegate.focusTarget() }, .up)
    }

    private static func addShortcut(_ shortcut: String, _ fn: @escaping () -> Void, _ type: KeyEventType) {
        GlobalShortcutMonitor.shared.addAction(ShortcutAction(shortcut: Shortcut.init(keyEquivalent: shortcut)!) { _ in
            fn()
            return true
        }, forKeyEvent: type)
    }
}

//                    if isTab && event.modifierFlags.contains(.shift) {
//
//                        return nil // previously focused app should not receive keys
//                    } else if isTab {
//
//                        return nil // previously focused app should not receive keys
//                    } else if isRightArrow && delegate.appIsBeingUsed {
//
//                        return nil // previously focused app should not receive keys
//                    } else if isLeftArrow && delegate.appIsBeingUsed {
//
//                        return nil // previously focused app should not receive keys
//                    } else if keyDown && isEscape {
//
//                        return nil // previously focused app should not receive keys
//                    }
//                }
//            } else if isMeta && !keyDown {
//
//                return nil // previously focused app should not receive keys
//            }
