import Cocoa

/// `NSTextField` that recomputes its `textColor` from a closure on every draw pass. Lets the label
/// color track external state (selection, key-window, etc.) without needing to thread observer
/// callbacks through every code path that might change that state. The closure typically returns
/// dynamic system colors (e.g. `.controlTextColor`) so Light/Dark Mode adaptation is handled by
/// AppKit itself.
class DynamicColorTextField: NSTextField {
    var colorProvider: (() -> NSColor)?

    override func viewWillDraw() {
        super.viewWillDraw()
        if let newColor = colorProvider?(), textColor != newColor {
            textColor = newColor
        }
    }
}
