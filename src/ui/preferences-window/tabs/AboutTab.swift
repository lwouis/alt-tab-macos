import Cocoa

class AboutTab {
    static func initTab() -> NSView {
        let appIcon = LightImageView()
        appIcon.updateContents(.cgImage(App.appIcon), NSSize(width: 256, height: 256))
        appIcon.fit(256, 256)
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
        let appInfo = NSStackView(views: [appIcon, appText])
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appInfo.spacing = GridView.interPadding
        appInfo.alignment = .centerY
        let sendFeedback = makeButtonWithIcon(NSLocalizedString("Send feedback…", comment: ""), #selector(App.app.showFeedbackPanel), "text.bubble")
        let supportProject = makeButtonWithIcon(NSLocalizedString("Support this project", comment: ""), #selector(App.app.supportProject), "heart.fill", .red)
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

    private static func makeButtonWithIcon(_ title: String, _ selector: Selector, _ symbolName: String?, _ color: NSColor? = nil) -> NSButton {
        let button = NSButton(title: title, target: nil, action: selector)
        if #available(macOS 26.0, *), let symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            button.imagePosition = .imageLeading
            if let color {
                button.image = button.image?.withSymbolConfiguration(.init(paletteColors: [color]))
            }
        }
        return button
    }
}
