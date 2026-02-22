import Cocoa

/// this is a lightweight CALayer which displays an image
/// it is an alternative to NSView-based image display, avoiding AppKit overhead (layout recursion, responder chain, drag-and-drop)
class LightImageLayer: CALayer {
    private var outlineLayer: CAShapeLayer!
    private var handRaisedLayer: CALayer!
    private let withTransparencyChecks: Bool

    init(withTransparencyChecks: Bool = false) {
        self.withTransparencyChecks = withTransparencyChecks
        super.init()
        contentsGravity = .resize
        magnificationFilter = .trilinear
        minificationFilter = .trilinear
        minificationFilterBias = 0.0
        shouldRasterize = false
        delegate = NoAnimationDelegate.shared
        setupOutlineLayer()
        setupHandRaisedLayer()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override init(layer: Any) {
        let other = layer as? LightImageLayer
        self.withTransparencyChecks = other?.withTransparencyChecks ?? false
        super.init(layer: layer)
    }

    private func setupOutlineLayer() {
        outlineLayer = CAShapeLayer()
        outlineLayer.name = "outline"
        outlineLayer.fillColor = nil
        outlineLayer.lineWidth = 1.0
        outlineLayer.lineDashPattern = [4, 3]
        outlineLayer.lineCap = .round
        outlineLayer.lineJoin = .round
        outlineLayer.isHidden = true
        addSublayer(outlineLayer)
    }

    private func setupHandRaisedLayer() {
        guard #available(macOS 11.0, *) else { return }
        handRaisedLayer = CALayer()
        handRaisedLayer.contentsGravity = .resizeAspect
        handRaisedLayer.isHidden = true
        addSublayer(handRaisedLayer)
    }

    private func updateOutlineLayer(_ fullyTransparent: Bool) {
        outlineLayer.isHidden = !fullyTransparent
        guard fullyTransparent else { return }
        let inset: CGFloat = 0.5
        let radius: CGFloat = 8.0
        outlineLayer.frame = bounds
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        outlineLayer.path = path
        outlineLayer.strokeColor = Appearance.fontColor.cgColor
    }

    private func updateHandRaisedLayer(_ fullyTransparent: Bool) {
        guard #available(macOS 11.0, *) else { return }
        handRaisedLayer.isHidden = !fullyTransparent
        guard fullyTransparent else { return }
        let minSize = min(Appearance.iconSize, bounds.width * 0.9, bounds.height * 0.9)
        let maxSize = Appearance.iconSize * 3
        let ratio = min(bounds.width / TileView.maxThumbnailWidth(), bounds.height / TileView.maxThumbnailHeight())
        let pointSize = max(minSize, maxSize * ratio)
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        handRaisedLayer.contents = image.tinted(Appearance.fontColor)
        handRaisedLayer.bounds = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
        handRaisedLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func updateContents(_ caLayerContents: CALayerContents, _ size: NSSize) {
        var fullyTransparent = false
        switch caLayerContents {
        case .cgImage(let image?):
            contents = image
            if withTransparencyChecks {
                fullyTransparent = image.isFullyTransparent()
            }
        case .pixelBuffer(let pixelBuffer?):
            contents = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        default: break
        }
        if frame.size != size {
            frame.size = size
        }
        if withTransparencyChecks {
            updateOutlineLayer(fullyTransparent)
            updateHandRaisedLayer(fullyTransparent)
        }
    }

    func releaseImage() {
        contents = nil
    }
}
