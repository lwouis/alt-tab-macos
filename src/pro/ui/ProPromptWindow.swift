import Cocoa

/// Base class for non-modal Pro-transition windows ([A] Welcome, [C] Full Upgrade, [D] Proactive,
/// [G] Final). Centralises the window chrome that every Day X window needs: hidden titlebar,
/// hidden traffic-light buttons, no hide-on-deactivate, no release-on-close. Subclasses set
/// their own `contentView` after calling the designated init.
class ProPromptWindow: NSWindow {
    convenience init(size: NSSize, miniaturizable: Bool = true, movableByBackground: Bool = false) {
        var mask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if miniaturizable { mask.insert(.miniaturizable) }
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        title = NSLocalizedString("AltTab Pro", comment: "")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = movableByBackground
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
