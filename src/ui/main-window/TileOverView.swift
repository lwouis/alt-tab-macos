import Cocoa

class TileOverView: FlippedView {
    var quitButton = TrafficLightButton(.quit, NSLocalizedString("Quit app", comment: ""))
    var closeButton = TrafficLightButton(.close, NSLocalizedString("Close window", comment: ""))
    var minimizeButton = TrafficLightButton(.miniaturize, NSLocalizedString("Minimize/Deminimize window", comment: ""))
    var maximizeButton = TrafficLightButton(.fullscreen, NSLocalizedString("Fullscreen/Defullscreen window", comment: ""))
    var isShowingWindowControls = false
    weak var scrollView: ScrollView?
    var previousTarget: TileView?
    private var previousHoveredButton: TrafficLightButton?

    var windowControlButtons: [TrafficLightButton] { [quitButton, closeButton, minimizeButton, maximizeButton] }

    convenience init() {
        self.init(frame: .zero)
        wantsLayer = true
        layer!.masksToBounds = false
        for button in windowControlButtons {
            addSubview(button)
            button.isHidden = true
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for button in windowControlButtons {
            guard !button.isHidden else { continue }
            let buttonPoint = button.convert(point, from: self)
            if button.bounds.contains(buttonPoint) {
                return button.hitTest(button.convert(point, from: self))
            }
        }
        return nil
    }

    // MARK: - Mouse hover management

    func updateHover() {
        guard let scrollView, !scrollView.isCurrentlyScrolling else { return }
        let location = convert(App.app.tilesPanel.mouseLocationOutsideOfEventStream, from: nil)
        updateButtonHover(location)
        let newTarget = findTarget(location)
        if let target = newTarget ?? previousTarget {
            let statusFrame = target.convert(target.statusIcons.frame, to: superview)
            if statusFrame.contains(location) {
                target.statusIcons.ensureTooltipsInstalled()
            }
        }
        guard newTarget !== previousTarget else { return }
        caTransaction {
            if let newTarget {
                hideWindowControls()
                newTarget.mouseMoved()
                showWindowControls(for: newTarget)
            } else {
                resetHoveredWindow()
            }
            previousTarget = newTarget
        }
    }

    /// Find the TrafficLightButton at the given point (in TileOverView's coordinate space)
    func findButton(_ location: NSPoint) -> TrafficLightButton? {
        guard isShowingWindowControls else { return nil }
        for button in windowControlButtons where !button.isHidden {
            let buttonPoint = button.convert(location, from: self)
            if button.bounds.contains(buttonPoint) {
                return button
            }
        }
        return nil
    }

    private func updateButtonHover(_ location: NSPoint) {
        var newHoveredButton: TrafficLightButton?
        if isShowingWindowControls {
            for button in windowControlButtons where !button.isHidden {
                let buttonPoint = button.convert(location, from: self)
                if button.bounds.contains(buttonPoint) {
                    newHoveredButton = button
                    break
                }
            }
        }
        guard newHoveredButton !== previousHoveredButton else { return }
        if let old = previousHoveredButton {
            old.isMouseOver = false
            old.setNeedsDisplay()
        }
        if let new = newHoveredButton {
            new.isMouseOver = true
            new.setNeedsDisplay()
        }
        previousHoveredButton = newHoveredButton
    }

    func findTarget(_ location: NSPoint) -> TileView? {
        guard let documentView = superview else { return nil }
        for case let view as TileView in documentView.subviews {
            let frame = view.frame
            let expandedFrame = CGRect(x: frame.minX - (App.shared.userInterfaceLayoutDirection == .leftToRight ? 0 : 1), y: frame.minY, width: frame.width + 1, height: frame.height + 1)
            if expandedFrame.contains(location) {
                return view
            }
        }
        return nil
    }

    func resetHoveredWindow() {
        previousTarget = nil
        if let oldIndex = Windows.hoveredWindowIndex {
            Windows.hoveredWindowIndex = nil
            TilesView.highlight(oldIndex)
        }
        hideWindowControls()
    }

    // MARK: - Window controls

    func showWindowControls(for view: TileView) {
        guard Preferences.appearanceStyle == .thumbnails else { hideWindowControls(); return }
        let shouldShow = !Preferences.hideColoredCircles && !Appearance.hideThumbnails
        guard shouldShow, let window = view.window_ else { hideWindowControls(); return }
        isShowingWindowControls = true
        for button in windowControlButtons { button.window_ = window }
        let thumbnailOrigin = NSPoint(
            x: view.frame.origin.x + view.thumbnail.frame.origin.x,
            y: view.frame.origin.y + view.thumbnail.frame.origin.y
        )
        let thumbnailWidth = view.thumbnail.frame.width
        var xOffset = CGFloat(3)
        var yOffset = CGFloat(2)
        for button in windowControlButtons {
            let shouldHide =
                (button.type == .quit && !window.application.canBeQuit()) ||
                (button.type == .close && !window.canBeClosed()) ||
                ((button.type == .miniaturize || button.type == .fullscreen) && !window.canBeMinDeminOrFullscreened())
            if button.isHidden != shouldHide {
                button.isHidden = shouldHide
                button.needsDisplay = true
            }
            assignIfDifferent(&button.frame.origin, NSPoint(x: thumbnailOrigin.x + xOffset, y: thumbnailOrigin.y + yOffset))
            xOffset += TrafficLightButton.size + TrafficLightButton.spacing
            if xOffset + TrafficLightButton.size > thumbnailWidth {
                xOffset = 3
                yOffset += TrafficLightButton.size + TrafficLightButton.spacing
            }
        }
    }

    func hideWindowControls() {
        guard isShowingWindowControls else { return }
        isShowingWindowControls = false
        if let old = previousHoveredButton {
            old.isMouseOver = false
            previousHoveredButton = nil
        }
        for button in windowControlButtons {
            button.isHidden = true
        }
    }
}
