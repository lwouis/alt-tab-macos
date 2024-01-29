import Cocoa

class AboutTab {
    static func initTab() -> NSView {
        let appIcon = NSImageView(image: NSImage.initResizedCopy("app", 256, 256))
        appIcon.imageScaling = .scaleNone
        let appText = StackView([
            BoldLabel(App.name),
            NSTextField(wrappingLabelWithString: NSLocalizedString("Version", comment: "") + " " + App.version),
            NSTextField(wrappingLabelWithString: App.licence),
            HyperlinkLabel(NSLocalizedString("Source code repository", comment: ""), App.repository),
            HyperlinkLabel(NSLocalizedString("Latest releases", comment: ""), App.repository + "/releases"),
        ], .vertical)
        appText.spacing = GridView.interPadding / 2
        let rowToSeparate = 3
        appText.views[rowToSeparate].topAnchor.constraint(equalTo: appText.views[rowToSeparate - 1].bottomAnchor, constant: GridView.interPadding).isActive = true
        let appInfo = StackView([appIcon, appText])
        appInfo.spacing = GridView.interPadding
        appInfo.alignment = .centerY
        let sendFeedback = NSButton(title: NSLocalizedString("Send feedback…", comment: ""), target: nil, action: #selector(App.app.showFeedbackPanel))
        let supportProject = NSButton(title: NSLocalizedString("Support this project ❤️", comment: ""), target: nil, action: #selector(App.app.supportProject))
        let grid = GridView([
            [appInfo],
            [sendFeedback],
            [supportProject],
        ])
        let sendFeedbackCell = grid.cell(atColumnIndex: 0, rowIndex: 1)
        sendFeedbackCell.xPlacement = .center
        sendFeedbackCell.row!.topPadding = GridView.interPadding
        let supportProjectCell = grid.cell(atColumnIndex: 0, rowIndex: 2)
        supportProjectCell.xPlacement = .center
        grid.fit()

        return grid
    }
}
