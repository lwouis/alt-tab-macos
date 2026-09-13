import Cocoa

class TileUnderLayer: CALayer {
    let focusedLayer = noAnimation { CALayer() }
    let hoveredLayer = noAnimation { CALayer() }

    override init() {
        super.init()
        delegate = NoAnimationDelegate.shared
        for highlightLayer in [focusedLayer, hoveredLayer] {
            highlightLayer.isHidden = true
            addSublayer(highlightLayer)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateHighlight(focusedView: TileView?, hoveredView: TileView?) {
        updateLayer(focusedLayer, for: focusedView, isFocused: true)
        updateLayer(hoveredLayer, for: hoveredView, isFocused: false)
    }

    private func updateLayer(_ highlightLayer: CALayer, for view: TileView?, isFocused: Bool) {
        guard let view, view.frame != .zero else {
            highlightLayer.isHidden = true
            return
        }
        let hf = view.highlightFrame
        let rect = CGRect(
            x: view.frame.origin.x + hf.origin.x,
            y: view.frame.origin.y + hf.origin.y,
            width: hf.width,
            height: hf.height
        )
        highlightLayer.frame = rect
        highlightLayer.cornerRadius = Appearance.cellCornerRadius
        let titlesStyle = Preferences.effectiveAppearanceStyle(SwitcherSession.activeShortcutIndex) == .titles
        let solidSelection = isFocused && titlesStyle
        let hoverBackground = titlesStyle
            ? NSColor.controlAccentColor.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.34 : 0.26)
            : Appearance.highlightHoveredBackgroundColor
        highlightLayer.cornerCurve = .continuous
        highlightLayer.backgroundColor = (isFocused
            ? (solidSelection ? NSColor.selectedContentBackgroundColor : Appearance.highlightFocusedBackgroundColor)
            : hoverBackground).cgColor
        highlightLayer.borderColor = (isFocused
            ? Appearance.highlightFocusedBorderColor
            : Appearance.highlightHoveredBorderColor).cgColor
        highlightLayer.borderWidth = titlesStyle ? 0 : Appearance.highlightBorderWidth
        highlightLayer.isHidden = false
    }
}
