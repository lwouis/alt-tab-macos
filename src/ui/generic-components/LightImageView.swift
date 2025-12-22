import Cocoa

/// this is a lightweight view which displays an image using its CALayer
/// it is an alternative to NSImageView, which doesn't have internal complexities and performance costs
class LightImageView: NSView {
    var image: CGImage? { get { layer!.contents as! CGImage? } }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        // configure the layer for efficient GPU-scaling
        layer!.contentsGravity = .center
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
    }

    func updateWithResizedCopy(_ image: CGImage?, _ size: NSSize) {
        let scaleFactor = NSScreen.preferred.backingScaleFactor
        if let image {
            // Only compress icons when NOT in App Icons appearance mode
            // App Icons mode requires high-resolution for best visual quality
            if Preferences.appearanceStyle == .appIcons {
                // Keep high-resolution for App Icons mode (GPU scaling)
                layer!.contentsGravity = .resize
                layer!.contents = image
            } else {
                // Compress to optimal size for other modes (CPU resizing, memory savings)
                // Calculate optimal size based on all connected monitors
                let optimalSize = IconSizeCalculator.optimalIconSize(for: size, scaleFactor: scaleFactor)
                layer!.contents = image.resizedCopyWithCoreGraphics(optimalSize, true)
            }
            layer!.contentsScale = scaleFactor
        }
        frame.size = size
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
