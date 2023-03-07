import Cocoa

class PreviewPanel: NSPanel {
    private let previewView = NSImageView()
    private let borderView = BorderView()

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        contentView = previewView
        borderView.autoresizingMask = [.width, .height]
        previewView.addSubview(borderView)
        // triggering AltTab before or during Space transition animation brings the window on the Space post-transition
        collectionBehavior = .canJoinAllSpaces
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
    }

    func setPreview(_ preview: NSImage) {
        previewView.image = preview
    }
}

private class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(rect: bounds)
        path.append(NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 5, yRadius: 5).reversed)
        systemAccentColor().withAlphaComponent(0.5).setFill()
        path.fill()
    }
}

func systemAccentColor() -> NSColor {
    if #available(OSX 10.14, *) {
        // dynamically adapts to changes in System Default; no need to listen to notifications
        return NSColor.controlAccentColor
    }
    return NSColor(srgbRed: 0, green: 0.47843137254901963, blue: 1, alpha: 1)
}
