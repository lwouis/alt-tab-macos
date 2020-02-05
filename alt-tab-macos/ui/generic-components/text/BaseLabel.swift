import Cocoa

class BaseLabel: NSTextView {
    convenience init(_ text: String) {
        self.init(frame: .zero)
        textContainer!.size.width = 1000
        string = text
        setup()
    }

    convenience init(_ frame: NSRect, _ container: NSTextContainer?) {
        self.init(frame: frame, textContainer: container)
        setup()
    }

    private func setup() {
        drawsBackground = true
        backgroundColor = NSColor.blue
        isSelectable = false
        isEditable = false
        enabledTextCheckingTypes = 0
        layoutManager!.ensureLayout(for: textContainer!)
        frame = layoutManager!.usedRect(for: textContainer!)
        fit(frame.size.width, frame.size.height)
    }
}
