import Cocoa

// A custom view that represents a group of traffic light buttons similar to those in a window's title bar
class TrafficLightButtonGroupView: NSView {
    // Views for the traffic light icons
    private let quitIconView: NSView
    private let closeIconView: NSView
    private let minimizeIconView: NSView
    private let maximizeIconView: NSView

    // Traffic light buttons for quit, close, minimize, and maximize actions
    let quitIcon: TrafficLightButton
    let closeIcon: TrafficLightButton
    let minimizeIcon: TrafficLightButton
    let maximizeIcon: TrafficLightButton

    init(window: Window?, controlSize: CGFloat, controlSpacing: CGFloat) {
        let size = controlSize
        let backgroundSize = size * 0.95  // Adjust the background size to be slightly smaller

        // Initialize traffic light buttons with their respective actions and titles
        quitIcon = TrafficLightButton(.quit, NSLocalizedString("Quit app", comment: ""), size)
        closeIcon = TrafficLightButton(.close, NSLocalizedString("Close window", comment: ""), size)
        minimizeIcon = TrafficLightButton(.miniaturize, NSLocalizedString("Minimize/Deminimize window", comment: ""), size)
        maximizeIcon = TrafficLightButton(.fullscreen, NSLocalizedString("Fullscreen window", comment: ""), size)

        // Create views to hold the traffic light icons
        quitIconView = NSView(frame: NSRect(x: 0, y: 0, width: backgroundSize, height: backgroundSize))
        closeIconView = NSView(frame: NSRect(x: 0, y: 0, width: backgroundSize, height: backgroundSize))
        minimizeIconView = NSView(frame: NSRect(x: 0, y: 0, width: backgroundSize, height: backgroundSize))
        maximizeIconView = NSView(frame: NSRect(x: 0, y: 0, width: backgroundSize, height: backgroundSize))

        super.init(frame: .zero)

        // Set the background color and corner radius for each icon view
        [quitIconView, closeIconView, minimizeIconView, maximizeIconView].forEach { view in
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            view.layer?.cornerRadius = backgroundSize / 2
        }

        // Add traffic light buttons to their respective views
        quitIconView.addSubview(quitIcon)
        closeIconView.addSubview(closeIcon)
        minimizeIconView.addSubview(minimizeIcon)
        maximizeIconView.addSubview(maximizeIcon)

        // Center the traffic light buttons inside their background views
        [quitIcon, closeIcon, minimizeIcon, maximizeIcon].forEach { button in
            button.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                button.centerXAnchor.constraint(equalTo: button.superview!.centerXAnchor),
                button.centerYAnchor.constraint(equalTo: button.superview!.centerYAnchor)
            ])
        }

        // Add icon views to the main view
        addSubview(quitIconView)
        addSubview(closeIconView)
        addSubview(minimizeIconView)
        addSubview(maximizeIconView)

        // Set the window property for each button
        setWindow(window: window)

        // Arrange the buttons with the specified control spacing
        arrangeButtons(controlSpacing: controlSpacing)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Arrange the traffic light buttons with the specified control spacing
    private func arrangeButtons(controlSpacing: CGFloat) {
        var xOffset: CGFloat = 3
        let yOffset: CGFloat = 2

        [quitIconView, closeIconView, minimizeIconView, maximizeIconView].forEach { view in
            view.frame.origin = NSPoint(x: xOffset, y: yOffset)
            xOffset += view.frame.width + controlSpacing
        }
    }

    // Set the window property for each traffic light button
    func setWindow(window: Window?) {
        [quitIcon, closeIcon, minimizeIcon, maximizeIcon].forEach {
            $0.window_ = window
        }
    }

    // Show or hide window controls and set frame size and position
    func updateWindowControlsVisibility(window: Window?, shouldShow: Bool, target: NSView) {
        var xOffset = CGFloat(3)
        var yOffset = CGFloat(2 + ThumbnailView.windowsControlSize)

        let iconsAndViews = [
            (icon: quitIcon, view: quitIconView),
            (icon: closeIcon, view: closeIconView),
            (icon: minimizeIcon, view: minimizeIconView),
            (icon: maximizeIcon, view: maximizeIconView)
        ]

        iconsAndViews.forEach { icon, view in
            let shouldHideIcon = !shouldShow ||
                    (icon.type == .quit && !(window?.application.canBeQuit() ?? true)) ||
                    (icon.type == .close && !(window?.canBeClosed() ?? true)) ||
                    ((icon.type == .miniaturize || icon.type == .fullscreen) && !(window?.canBeMinDeminOrFullscreened() ?? true))
            icon.isHidden = shouldHideIcon
            view.isHidden = shouldHideIcon
        }

        self.isHidden = !shouldShow
        if shouldShow {
            self.frame.size = NSSize(
                    width: 4 * ThumbnailView.windowsControlSize + 3 * ThumbnailView.windowsControlSpacing + 6,
                    height: ThumbnailView.windowsControlSize + 4
            )
            self.frame.origin = NSPoint(x: 3, y: target.frame.height - ThumbnailView.windowsControlSize - 6)
        }
    }
}