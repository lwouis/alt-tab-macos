import Cocoa

class HighInterpolationImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current!.imageInterpolation = Preferences.thumbnailQuality
        super.draw(dirtyRect)
    }
}
