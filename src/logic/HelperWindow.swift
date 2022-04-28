import Cocoa
/**
 * we use this window to help us switch to another space
 */
class HelperWindow: NSWindow {
    var canBecomeKey_ = true
    override var canBecomeKey: Bool { canBecomeKey_ }
    convenience init() {
        self.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        setupWindow()
    }

    private func setupWindow() {
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        title = "Helper Window"
    }
}
