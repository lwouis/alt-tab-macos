import Cocoa

class TileUnderLayer: CALayer {
    let focusedLayer = noAnimation { CALayer() }
    let hoveredLayer = noAnimation { CALayer() }
    let dividerLayer = noAnimation { CALayer() }

    override init() {
        super.init()
        delegate = NoAnimationDelegate.shared
        for highlightLayer in [focusedLayer, hoveredLayer] {
            highlightLayer.isHidden = true
            addSublayer(highlightLayer)
        }
        dividerLayer.isHidden = true
        addSublayer(dividerLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateHighlight(focusedView: TileView?, hoveredView: TileView?) {
        updateLayer(focusedLayer, for: focusedView, isFocused: true)
        updateLayer(hoveredLayer, for: hoveredView, isFocused: false)
    }

    /// The line between the screen showing AltTab's group and the other screens' group; nil hides it.
    func updateDivider(_ frame: CGRect?) {
        guard let frame else {
            dividerLayer.isHidden = true
            return
        }
        dividerLayer.frame = frame
        dividerLayer.cornerRadius = frame.width / 2
        dividerLayer.backgroundColor = Appearance.fontColor.withAlphaComponent(0.3).cgColor
        dividerLayer.isHidden = false
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
        highlightLayer.backgroundColor = (isFocused
            ? Appearance.highlightFocusedBackgroundColor
            : Appearance.highlightHoveredBackgroundColor).cgColor
        highlightLayer.borderColor = (isFocused
            ? Appearance.highlightFocusedBorderColor
            : Appearance.highlightHoveredBorderColor).cgColor
        highlightLayer.borderWidth = Appearance.highlightBorderWidth
        highlightLayer.isHidden = false
    }
}
