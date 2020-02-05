import Cocoa
import Foundation

class AboutTab {
    static func make() -> NSTabViewItem {
        return TabViewItem.make("About", NSImage.infoName, makeView())
    }

    private static func makeView() -> NSGridView {
        let appIcon = NSImageView(image: App.shared.applicationIconImage)
        appIcon.fit(64, 64)
        let appText = NSStackView(views: [BoldLabel(App.name), NSTextField(wrappingLabelWithString: "Version \(App.version)")])
        appText.orientation = .vertical
        appText.alignment = .left
        appText.spacing = GridView.interPadding / 2
        let appInfo = NSStackView(views: [appIcon, appText])
        appInfo.spacing = GridView.interPadding
        let view = GridView.make([
            [appInfo],
            [HyperlinkLabel("Source code repository", "https://github.com/lwouis/alt-tab-macos")],
            [HyperlinkLabel("Latest releases", "https://github.com/lwouis/alt-tab-macos/releases")],
        ])
        view.fit()
        return view
    }
}
