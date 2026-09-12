import Cocoa

class AcknowledgmentsTab {
    static func makeContentView(columnWidth: CGFloat = 240, shouldFit: Bool = true, verticallyStacked: Bool = false) -> NSView {
        let sectionNames = ["acknowledgments"]
        let textViews: [NSTextView] = sectionNames.map { makeTextView($0, columnWidth) }
        let content: NSView
        if verticallyStacked {
            let stack = NSStackView(views: textViews)
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = GridView.interPadding
            stack.translatesAutoresizingMaskIntoConstraints = false
            content = stack
        } else {
            content = GridView([textViews])
        }
        if shouldFit {
            content.fit()
        }
        return content
    }

    private static func makeTextView(_ sectionName: String, _ columnWidth: CGFloat) -> NSTextView {
        let markdownFileUrl = Bundle.main.url(forResource: sectionName, withExtension: "md")!
        var content = try! String(contentsOf: markdownFileUrl, encoding: .utf8)
        if content.last == "\n" {
            content.removeLast()
        }
        let attributedString = Markdown.toAttributedString(content)
        let textView = NSTextView()
        textView.textContainer!.widthTracksTextView = true
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.drawsBackground = false
        textView.isSelectable = true
        textView.isEditable = false
        textView.enabledTextCheckingTypes = 0
        textView.frame.size.width = columnWidth
        textView.textStorage!.setAttributedString(attributedString)
        textView.layoutManager!.ensureLayout(for: textView.textContainer!)
        textView.frame = textView.layoutManager!.usedRect(for: textView.textContainer!)
        textView.fit(textView.frame.width, textView.frame.height)
        return textView
    }
}
