import Cocoa

class ThumbnailsPanel: NSPanel {
    var thumbnailsView = ThumbnailsView()

    convenience init() {
        self.init(contentRect: .zero, styleMask: .utilityWindow, backing: .buffered, defer: true)
        isFloatingPanel = true
        updateFadeOutAnimation()
        hidesOnDeactivate = false
        hasShadow = false
        titleVisibility = .hidden
        styleMask.remove(.titled)
        styleMask.update(with: .nonactivatingPanel)
        backgroundColor = .clear
        contentView!.addSubview(thumbnailsView)
        // 2nd highest level possible; this allows the app to go on top of context menus
        // highest level is .screenSaver but makes drag and drop on top the main window impossible
        level = .popUpMenu
        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
    }

    func updateFadeOutAnimation() {
        animationBehavior = Preferences.fadeOutAnimation ? .utilityWindow : .none
    }

    func show() {
        orderFrontRegardless()
        MouseEvents.enable()
        thumbnailsView.scrollView.flashScrollers()
    }

    static func widthMax(_ screen: NSScreen) -> CGFloat {
        return screen.frame.width * Preferences.maxScreenUsage - Preferences.windowPadding * 2
    }

    static func heightMax(_ screen: NSScreen) -> CGFloat {
        return screen.frame.height * Preferences.maxScreenUsage - Preferences.windowPadding * 2
    }
}
