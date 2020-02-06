import Cocoa

class AboutTab: NSObject {
    static func make() -> NSTabViewItem {
        return TabViewItem.make("About", NSImage.infoName, makeView())
    }

    static func makeView() -> NSGridView {
        let appIcon = NSImageView(image: App.shared.applicationIconImage)
        appIcon.fit(128, 128)
        let appText = NSStackView(views: [
            BoldLabel(App.name),
            NSTextField(wrappingLabelWithString: "Version \(App.version)"),
            HyperlinkLabel("Source code repository", App.repository),
            HyperlinkLabel("Latest releases", App.repository + "/releases"),
        ])
        appText.orientation = .vertical
        appText.alignment = .left
        appText.spacing = GridView.interPadding / 2
        appText.views[2].topAnchor.constraint(equalTo: appText.views[1].bottomAnchor, constant: GridView.interPadding).isActive = true
        let appInfo = NSStackView(views: [appIcon, appText])
        appInfo.spacing = GridView.interPadding
        let view = GridView.make([
            [appInfo],
            [NSButton(title: "Send feedback", target: self, action: #selector(feedbackCallback))],
        ])
        view.row(at: 1).topPadding = GridView.interPadding * 2
        view.cell(atColumnIndex: 0, rowIndex: 1).xPlacement = .center
        view.fit()
        return view
    }

    @objc
    static func feedbackCallback(senderControl: NSControl) {
        (App.shared as! App).showFeedbackPanel()
    }
}
