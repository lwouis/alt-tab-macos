import Cocoa

class AcknowledgmentsTab {
    // going taller than this will crop the view on small screens or low scaling modes on retina displays
    static let maxTabHeight = CGFloat(450)

    static func initTab() -> NSView {
        makeScrollableView(makeContentView(), maxTabHeight)
    }

    static func makeContentView(columnWidth: CGFloat = 240, shouldFit: Bool = true, verticallyStacked: Bool = false) -> NSView {
        let sectionNames = ["Contributors", "Acknowledgments"]
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

    private static func makeScrollableView(_ content: NSView, _ maxHeight: CGFloat) -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.documentView = FlippedView(frame: .zero)
        scrollView.documentView!.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView!.subviews = [content]
        let totalWidth = content.fittingSize.width
        scrollView.frame.size = NSSize(width: totalWidth, height: maxHeight)
        scrollView.contentView.frame.size = scrollView.frame.size
        scrollView.documentView!.frame.size = content.fittingSize
        scrollView.fit(totalWidth, maxHeight)
        return scrollView
    }
}
