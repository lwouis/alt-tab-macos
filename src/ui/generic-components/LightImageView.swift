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

    func updateWithResizedCopy(_ image: CGImage?, _ size: NSSize) {
        let scaleFactor = NSScreen.preferred.backingScaleFactor
        if let image {
            // alternatively, we could set layer!.contentsGravity to .center, and use the lines bellow to resize ourselves
            //     let scaledSize = NSSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
            //     layer!.contents = image.resizedCopyWithCoreGraphics(scaledSize, fixBitmapInfo)
            // it would produce subjectively better quality, but the resizing would be done on the CPU so poor performance
            layer!.contents = image
            layer!.contentsScale = scaleFactor
        }
        if frame.size != size {
            frame.size = size
        }
    }

    /// this schedules the image update for the next cycle
    /// The Panel will show with previous pictures, then they each will get updated quickly. It's a trade-off of getting AltTab interactive faster at the price of wrong data being shown
    /// I feel the UX is better without it. I may reconsider
    func updateWithResizedCopyAsync(_ image: CGImage?, _ size: NSSize) {
        layer!.contentsScale = NSScreen.preferred.backingScaleFactor
        frame.size = size
        if let image {
            // set image on another cycle so it doesn't block initial rendering
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layer!.contents = image
            }
        }
    }

    func releaseImage() {
        layer!.contents = nil
    }
}
