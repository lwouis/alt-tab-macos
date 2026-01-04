import Cocoa

/// this is a lightweight view which displays an image using its CALayer
/// it is an alternative to NSImageView, which doesn't have internal complexities and performance costs
class LightImageView: NSView {
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
    }

    func updateWithResizedCopy(_ caLayerContents: CALayerContents, _ size: NSSize) {
        let scaleFactor = NSScreen.preferred.backingScaleFactor
        // alternatively, we could set layer!.contentsGravity to .center, and use the lines bellow to resize ourselves
        //     let scaledSize = NSSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
        //     layer!.contents = image.resizedCopyWithCoreGraphics(scaledSize, fixBitmapInfo)
        // it would produce subjectively better quality, but the resizing would be done on the CPU so poor performance
        switch caLayerContents {
        case .cgImage(let image?):
            layer!.contents = image
        case .pixelBuffer(let pixelBuffer?):
            layer!.contents = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        default: break
        }
        layer!.contentsScale = scaleFactor
        if frame.size != size {
            frame.size = size
        }
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
