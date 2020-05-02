import Cocoa
import SwiftyMarkdown
import Preferences

class AcknowledgmentsTab: NSViewController, PreferencePane {
    // going taller than this will crop the view on small screens or low scaling modes on retina displays
    static let maxTabHeight = CGFloat(450)
    let preferencePaneIdentifier = PreferencePane.Identifier("Acknowledgments")
    let preferencePaneTitle = NSLocalizedString("Acknowledgments", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.userAccountsName)!

    override func loadView() {
        let markdownFileUrl = Bundle.main.url(forResource: "ACKNOWLEDGMENTS", withExtension: "md")!
        let md = SwiftyMarkdown(url: markdownFileUrl)!
        md.h2.fontSize = 20
        let textView = TextField(md.attributedString())

        let scrollView = ScrollView()
        scrollView.scrollerKnobStyle = .default
        scrollView.documentView!.subviews = [textView]
        let height = min(textView.fittingSize.width, AcknowledgmentsTab.maxTabHeight)
        scrollView.frame.size = NSSize(width: textView.fittingSize.width, height: height)
        scrollView.contentView.frame.size = textView.fittingSize
        scrollView.documentView!.frame.size = textView.fittingSize
        scrollView.fit(textView.fittingSize.width, height)

        let grid = GridView([[scrollView]])
        grid.fit()
        view = grid
    }
}
