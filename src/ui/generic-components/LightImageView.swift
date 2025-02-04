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
        layer!.contentsGravity = .resize
        layer!.magnificationFilter = .trilinear
        layer!.minificationFilter = .trilinear
        layer!.minificationFilterBias = 0.0
        layer!.shouldRasterize = false
    }

    func updateWithResizedCopy(_ image: CGImage?, _ size: NSSize, fixBitmapInfo: Bool = false) {
        let scaleFactor = NSScreen.preferred.backingScaleFactor
        if let image {
            CATransaction.begin()
            // disable implicit fade-in animation from CALayer
            CATransaction.setDisableActions(true)
            // alternatively, we could set layer!.contentsGravity to .center, and use the lines bellow to resize ourselves
            //     let scaledSize = NSSize(width: size.width * scaleFactor, height: size.height * scaleFactor)
            //     layer!.contents = image.resizedCopyWithCoreGraphics(scaledSize, fixBitmapInfo)
            // it would produce subjectively better quality, but the resizing would be done on the CPU so poor performance
            layer!.contents = image
            layer!.contentsScale = scaleFactor
            CATransaction.commit()
        }
        frame.size = size
    }
}
