class InterpolatedImageView: NSImageView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current!.imageInterpolation = NSImageInterpolation.high
        super.draw(dirtyRect)
    }
}
