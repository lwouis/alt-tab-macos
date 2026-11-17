import Cocoa

class HyperlinkLabel: NSTextField {
    private var url: URL?

    convenience init(_ string: String, _ urlString: String) {
        self.init(labelWithString: string)
        let target = URL(string: urlString)!
        if target.isFileURL || target.scheme == "x-apple.systempreferences" {
            url = target
            applyLinkStyle(string)
        }
    }

    private func applyLinkStyle(_ string: String) {
        isSelectable = false
        attributedStringValue = NSAttributedString(string: string, attributes: [
            .foregroundColor: NSColor.linkColor,
            .font: NSFont.labelFont(ofSize: NSFont.systemFontSize),
        ])
    }

    override func resetCursorRects() {
        if url != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        if let url {
            NSWorkspace.shared.open(url)
        }
    }
}
