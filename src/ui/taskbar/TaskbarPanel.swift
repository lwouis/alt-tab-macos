import Cocoa

class TaskbarPanel: NSPanel {
    var taskbarView: TaskbarView!
    var screenUuid: ScreenUuid

    init(screenUuid: ScreenUuid) {
        self.screenUuid = screenUuid
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Use dock window level (20) so taskbar stays above maximized windows
        // This is the same level macOS Dock uses
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        backgroundColor = .clear
        animationBehavior = .none
        // Accept mouse events even when not key window
        acceptsMouseMovedEvents = true

        taskbarView = TaskbarView()
        contentView = taskbarView

        // helps filter out this window from the thumbnails
        setAccessibilitySubrole(.unknown)
        setAccessibilityLabel("Taskbar")

        updateAppearance()
    }

    func updateAppearance() {
        hasShadow = true
        appearance = NSAppearance(named: Appearance.currentTheme == .dark ? .vibrantDark : .vibrantLight)
    }

    func positionAtScreenBottom(_ screen: NSScreen) {
        let screenFrame = screen.visibleFrame
        let panelHeight = Preferences.taskbarHeight
        let frame = NSRect(
            x: screenFrame.minX,
            y: screenFrame.minY,
            width: screenFrame.width,
            height: panelHeight
        )
        setFrame(frame, display: true)
    }

    func updateContents(_ windows: [Window]) {
        taskbarView.updateItems(windows)
    }

    // Allow the panel to receive mouse events without becoming key
    override var canBecomeKey: Bool { true }
}
