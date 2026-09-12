import Cocoa

class HyperlinkLabel: NSTextField {
    private var url: URL?

    convenience init(_ string: String, _ urlString: String) {
        self.init(labelWithString: string)
        url = URL(string: urlString)!
        applyLinkStyle(string)
    }

    private func applyLinkStyle(_ string: String) {
        isSelectable = false
        attributedStringValue = NSAttributedString(string: string, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.labelFont(ofSize: NSFont.systemFontSize),
        ])
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
