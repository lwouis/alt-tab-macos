// Changes to next app (Shortcut1/default) without showing UI (used in applescripts (eg: cmd-w / cmd-m replacements using BTT --to close/minimize windows without cycling ala Windows™️))
import Foundation
import Cocoa

class TriggerScriptCommand: NSScriptCommand {
	override func performDefaultImplementation() -> Any? {
        App.app.showUi()
        App.app.focusTarget()
//        App.app.previousWindowShortcutWithRepeatingKey()
        return self
	}
}
