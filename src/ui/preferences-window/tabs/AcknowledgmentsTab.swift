import Cocoa

class AcknowledgmentsTab {
    // going taller than this will crop the view on small screens or low scaling modes on retina displays
    static let maxTabHeight = CGFloat(450)

    static func initTab() -> NSView {
        let textViews: [NSTextView] = ["Contributors", "Acknowledgments"].map {
            let markdownFileUrl = Bundle.main.url(forResource: $0, withExtension: "md")!
            let content = try! String(contentsOf: markdownFileUrl, encoding: .utf8)
            let attributedString = Markdown.toAttributedString(content)
            let textView = NSTextView()
            textView.textContainer!.widthTracksTextView = true
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.drawsBackground = true
            textView.backgroundColor = .clear
            textView.isSelectable = true
            textView.isEditable = false
            textView.enabledTextCheckingTypes = 0
            textView.frame.size.width = 230
            textView.textStorage!.setAttributedString(attributedString)
            textView.layoutManager!.ensureLayout(for: textView.textContainer!)
            textView.frame = textView.layoutManager!.usedRect(for: textView.textContainer!)
            textView.fit(textView.frame.width, textView.frame.height)
            return textView
        }
        let subGrid = GridView([textViews])
        subGrid.column(at: 1).leadingPadding = 20
        subGrid.fit()

        let scrollView = ScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView!.translatesAutoresizingMaskIntoConstraints = false
        scrollView.scrollerKnobStyle = .default
        scrollView.documentView!.subviews = [subGrid]
        let totalWidth = subGrid.fittingSize.width
        scrollView.frame.size = NSSize(width: totalWidth, height: maxTabHeight)
        scrollView.contentView.frame.size = scrollView.frame.size
        scrollView.documentView!.frame.size = subGrid.fittingSize
        scrollView.fit(totalWidth, maxTabHeight)

        return scrollView
    }
}
