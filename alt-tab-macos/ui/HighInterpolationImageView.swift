import Cocoa

class HighInterpolationImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current!.imageInterpolation = .high
        super.draw(dirtyRect)
    }
}
