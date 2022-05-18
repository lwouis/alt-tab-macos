// call hideUI()
import Foundation
import Cocoa

class HideScriptCommand: NSScriptCommand {
	override func performDefaultImplementation() -> Any? {
        App.app.hideUi()
        return self
	}
}

