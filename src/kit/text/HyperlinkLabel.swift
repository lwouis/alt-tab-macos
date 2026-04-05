import Cocoa

class HyperlinkLabel: NSTextField {
    private var url: URL?
    var onClick: (() -> Void)?

    convenience init(_ string: String, _ urlString: String) {
        self.init(labelWithString: string)
        url = URL(string: urlString)!
        applyLinkStyle(string)
    }

    convenience init(_ string: String, onClick: @escaping () -> Void) {
        self.init(labelWithString: string)
        self.onClick = onClick
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
        if let onClick {
            onClick()
        } else if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
