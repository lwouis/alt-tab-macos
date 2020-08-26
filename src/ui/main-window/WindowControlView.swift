import Cocoa

class WindowControlView: NSImageView {
    var originalImage: NSImage!
    var hoveredImage: NSImage!
    var size: NSSize!

    convenience init(_ imageName: String, _ size_: Int) {
        self.init()
        translatesAutoresizingMaskIntoConstraints = false
        size = NSSize(width: size_, height: size_)
        let image = NSImage.initCopy(imageName)
        image.size = size
        originalImage = image
        hoveredImage = image.tinted(.init(white: 0, alpha: 0.25))
        hovered(false)
    }

    func hovered(_ isHovered: Bool) {
        image = isHovered ? hoveredImage : originalImage
        image!.size = size
        frame.size = size
    }
}
