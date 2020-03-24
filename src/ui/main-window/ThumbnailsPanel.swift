import Cocoa

class ThumbnailsPanel: NSPanel {
    var thumbnailsView = ThumbnailsView()
    var currentScreen: NSScreen?
    static let cellId = NSUserInterfaceItemIdentifier("Cell")

    convenience init(_ app: App) {
        self.init(contentRect: .zero, styleMask: .utilityWindow, backing: .buffered, defer: true)
        isFloatingPanel = true
        animationBehavior = .none
        hidesOnDeactivate = false
        hasShadow = false
        titleVisibility = .hidden
        styleMask.remove(.titled)
        backgroundColor = .clear
        contentView!.addSubview(thumbnailsView)
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
    }

    func show() {
        makeKeyAndOrderFront(nil)
    }

    static func highlightCell(_ previousView: NSView, _ newView: NSView) {
        previousView.layer!.backgroundColor = .clear
        previousView.layer!.borderColor = .clear
        newView.layer!.backgroundColor = Preferences.highlightBackgroundColor.cgColor
        newView.layer!.borderColor = Preferences.highlightBorderColor.cgColor
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return screen.frame.width * Preferences.maxScreenUsage - Preferences.windowPadding * 2
    }

    static func heightMax(_ screen: NSScreen) -> CGFloat {
        return screen.frame.height * Preferences.maxScreenUsage - Preferences.windowPadding * 2
    }
}
