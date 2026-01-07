import Cocoa

/// this is a lightweight view which displays an image using its CALayer
/// it is an alternative to NSImageView, which doesn't have internal complexities and performance costs
class LightImageView: NSView {
    private var outlineLayer: CAShapeLayer!
    private var handRaisedLayer: CALayer!

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // configure the layer for efficient GPU-scaling
        layer!.contentsGravity = .resize
        layer!.magnificationFilter = .trilinear
        layer!.minificationFilter = .trilinear
        layer!.minificationFilterBias = 0.0
        layer!.shouldRasterize = false
        // disable implicit animations
        layer!.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "contentsScale": NSNull()
        ]
        layerContentsRedrawPolicy = .never
        setupOutlineLayer()
        setupHandRaisedLayer()
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
        layer!.addSublayer(outlineLayer)
    }

    private func setupHandRaisedLayer() {
        guard #available(macOS 11.0, *) else { return }
        handRaisedLayer = CALayer()
        handRaisedLayer.contentsGravity = .resizeAspect
        handRaisedLayer.isHidden = true
        layer!.addSublayer(handRaisedLayer)
    }


    private func updateOutlineLayer(_ fullyTransparent: Bool) {
        outlineLayer.isHidden = !fullyTransparent
        guard fullyTransparent else { return }
        let inset: CGFloat = 0.5
        let radius: CGFloat = 8.0
        let bounds = outlineLayer.superlayer!.bounds
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
        // we want the icon to be large but not too large, and readable at small sizes
        let minSize = min(Appearance.iconSize, bounds.width * 0.9, bounds.height * 0.9)
        let maxSize = Appearance.iconSize * 3
        let ratio = min(bounds.width / ThumbnailView.maxThumbnailWidth(), bounds.height / ThumbnailView.maxThumbnailHeight())
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
            layer!.contents = image
            fullyTransparent = image.iFullyTransparent()
        case .pixelBuffer(let pixelBuffer?):
            layer!.contents = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        default: break
        }
        if frame.size != size {
            frame.size = size
        }
        updateOutlineLayer(fullyTransparent)
        updateHandRaisedLayer(fullyTransparent)
    }

    func releaseImage() {
        layer!.contents = nil
    }
}

enum CALayerContents {
    case cgImage(CGImage?)
    case pixelBuffer(CVPixelBuffer?)

    func size() -> NSSize? {
        switch self {
        case .cgImage(let image):
            return image?.size()
        case .pixelBuffer(let pixelBuffer):
            return pixelBuffer?.size()
        }
    }
}
