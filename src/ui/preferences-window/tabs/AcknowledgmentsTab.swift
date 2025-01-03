import Cocoa

class AcknowledgmentsTab {
    // going taller than this will crop the view on small screens or low scaling modes on retina displays
    static let maxTabHeight = CGFloat(450)

    static func initTab() -> NSView {
        let textViews: [NSTextView] = ["Contributors", "Acknowledgments"].map {
            let markdownFileUrl = Bundle.main.url(forResource: $0, withExtension: "md")!
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
            textView.frame.size.width = 240
            textView.textStorage!.setAttributedString(attributedString)
            textView.layoutManager!.ensureLayout(for: textView.textContainer!)
            textView.frame = textView.layoutManager!.usedRect(for: textView.textContainer!)
            textView.fit(textView.frame.width, textView.frame.height)
            return textView
        }
        let subGrid = GridView([textViews])
        subGrid.fit()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = FlippedView(frame: .zero)
        scrollView.documentView!.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView!.subviews = [subGrid]
        let totalWidth = subGrid.fittingSize.width
        scrollView.frame.size = NSSize(width: totalWidth, height: maxTabHeight)
        scrollView.contentView.frame.size = scrollView.frame.size
        scrollView.documentView!.frame.size = subGrid.fittingSize
        scrollView.fit(totalWidth, maxTabHeight)
        return scrollView
    }
}
