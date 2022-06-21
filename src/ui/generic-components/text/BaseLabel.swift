import Cocoa

class BaseLabel: NSTextView {
    convenience init(_ text: String) {
        self.init(frame: .zero)
        string = text
        setup()
    }

    convenience init(_ frame: NSRect, _ container: NSTextContainer?) {
        self.init(frame: frame, textContainer: container)
        setup()
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        drawsBackground = true
        backgroundColor = .clear
        isSelectable = false
        isEditable = false
        enabledTextCheckingTypes = 0
        layoutManager!.ensureLayout(for: textContainer!)
        frame = layoutManager!.usedRect(for: textContainer!)
    }

    override func mouseMoved(with event: NSEvent) {
        // no-op here prevents tooltips from disappearing on mouseMoved
    }
}
