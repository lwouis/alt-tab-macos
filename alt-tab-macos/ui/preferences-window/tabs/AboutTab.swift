import Cocoa

class AboutTab: NSObject {
    static func make() -> NSTabViewItem {
        return TabViewItem.make(NSLocalizedString("About", comment: ""), NSImage.infoName, makeView())
    }

    static func makeView() -> NSGridView {
        let appIcon = NSImageView(image: App.shared.applicationIconImage)
        appIcon.fit(150, 150)
        let appText = NSStackView(views: [
            BoldLabel(App.name),
            NSTextField(wrappingLabelWithString: NSLocalizedString("Version ", comment: "") + App.version),
            NSTextField(wrappingLabelWithString: App.licence),
            HyperlinkLabel(NSLocalizedString("Source code repository", comment: ""), App.repository),
            HyperlinkLabel(NSLocalizedString("Latest releases", comment: ""), App.repository + "/releases"),
        ])
        appText.orientation = .vertical
        appText.alignment = .left
        appText.spacing = GridView.interPadding / 2
        let rowToSeparate = 3
        appText.views[rowToSeparate].topAnchor.constraint(equalTo: appText.views[rowToSeparate - 1].bottomAnchor, constant: GridView.interPadding).isActive = true
        let appInfo = NSStackView(views: [appIcon, appText])
        appInfo.spacing = GridView.interPadding
        let view = GridView.make([
            [appInfo],
            [NSButton(title: NSLocalizedString("Send feedback", comment: ""), target: self, action: #selector(feedbackCallback))],
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
