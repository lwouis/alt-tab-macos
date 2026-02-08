import Cocoa

class HighlightOverlayView: FlippedView {
    let focusedLayer = noAnimation { CALayer() }
    let hoveredLayer = noAnimation { CALayer() }
    var quitButton = TrafficLightButton(.quit, NSLocalizedString("Quit app", comment: ""))
    var closeButton = TrafficLightButton(.close, NSLocalizedString("Close window", comment: ""))
    var minimizeButton = TrafficLightButton(.miniaturize, NSLocalizedString("Minimize/Deminimize window", comment: ""))
    var maximizeButton = TrafficLightButton(.fullscreen, NSLocalizedString("Fullscreen/Defullscreen window", comment: ""))
    var isShowingWindowControls = false

    var windowControlButtons: [TrafficLightButton] { [quitButton, closeButton, minimizeButton, maximizeButton] }

    convenience init() {
        self.init(frame: .zero)
        wantsLayer = true
        layer!.masksToBounds = false
        for highlightLayer in [focusedLayer, hoveredLayer] {
            highlightLayer.isHidden = true
            layer!.addSublayer(highlightLayer)
        }
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

    func updateHighlight(focusedView: ThumbnailView?, hoveredView: ThumbnailView?) {
        updateLayer(focusedLayer, for: focusedView, isFocused: true)
        updateLayer(hoveredLayer, for: hoveredView, isFocused: false)
    }

    private func updateLayer(_ highlightLayer: CALayer, for view: ThumbnailView?, isFocused: Bool) {
        guard let view, view.frame != .zero else {
            highlightLayer.isHidden = true
            return
        }
        let vStackFrame = view.vStackView.frame
        let rect = CGRect(
            x: view.frame.origin.x + vStackFrame.origin.x,
            y: view.frame.origin.y + vStackFrame.origin.y,
            width: vStackFrame.width,
            height: vStackFrame.height
        )
        highlightLayer.frame = rect
        highlightLayer.cornerRadius = Appearance.cellCornerRadius
        highlightLayer.backgroundColor = (isFocused
            ? Appearance.highlightFocusedBackgroundColor
            : Appearance.highlightHoveredBackgroundColor).cgColor
        highlightLayer.borderColor = (isFocused
            ? Appearance.highlightFocusedBorderColor
            : Appearance.highlightHoveredBorderColor).cgColor
        highlightLayer.borderWidth = Appearance.highlightBorderWidth
        highlightLayer.isHidden = false
    }

    func showWindowControls(for view: ThumbnailView) {
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
        for button in windowControlButtons {
            button.isHidden = true
        }
    }
}
