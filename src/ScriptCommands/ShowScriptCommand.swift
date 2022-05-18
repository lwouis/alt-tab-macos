//show the default UI (cmd+tab / normally Shortcut1), but with 1st window highlighted
import Foundation
import Cocoa

class ShowScriptCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
//        App.app.showUi()
        App.app.appIsBeingUsed = true
        App.app.showUiOrCycleSelection(0)
        App.app.previousWindowShortcutWithRepeatingKey()
        return self
    }
}
