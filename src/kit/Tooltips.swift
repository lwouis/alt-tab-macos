import Cocoa

enum Tooltips {
    /// Some tooltips may not be hidden when the main window is hidden; we force it through a private API.
    static func hideAll() {
        let selector = NSSelectorFromString("abortAllToolTips")
        if NSApp.responds(to: selector) {
            NSApp.perform(selector)
        }
    }
}
