import Cocoa
import Foundation

class AboutTab {
    static func make() -> NSTabViewItem {
        return TabViewItem.make("About", NSImage.infoName, makeView())
    }

    private static func makeView() -> NSGridView {
        let appIcon = NSImageView(image: App.shared.applicationIconImage)
        appIcon.fit(80, 80)
        let appText = NSStackView(views: [BoldLabel(App.name), NSTextField(wrappingLabelWithString: "Version \(App.version)")])
        appText.orientation = .vertical
        appText.alignment = .left
        appText.spacing = GridView.interPadding / 2
        let appInfo = NSStackView(views: [appIcon, appText])
        appInfo.spacing = GridView.interPadding
        let view = GridView.make([
            [appInfo],
            [HyperlinkLabel("Source code repository", App.repository)],
            [HyperlinkLabel("Latest releases", App.repository + "/releases")],
        ])
        view.fit()
        return view
    }
}
