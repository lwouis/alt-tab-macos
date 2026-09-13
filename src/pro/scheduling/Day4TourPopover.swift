import Cocoa

class Day4TourPopover {
    // periphery:ignore - strong hold, so the popover outlives `show()`
    private static var popover: NSPopover?

    static func show() {
        let popover = ProPromptPopover.make()
        let width = CGFloat(280)
        let showSettingsButton = NSButton(title: NSLocalizedString("Try them in Settings", comment: ""), target: nil, action: nil)
        showSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        showSettingsButton.bezelStyle = .rounded
        showSettingsButton.controlSize = .small
        showSettingsButton.keyEquivalent = "\r"
        showSettingsButton.onAction = { _ in
            popover.performClose(nil)
            App.showSettingsWindow()
        }
        let container = ProPromptPopover.makeContainer(width: width, [
            .init(view: ProPromptPopover.makeTitle(NSLocalizedString("Your trial includes Pro features", comment: "")),
                gapAbove: 0, width: .hugLeading),
            .init(view: ProPromptPopover.makeBody(NSLocalizedString("You're on day 4 of 14 — try these before your trial ends:", comment: ""), width: width),
                gapAbove: 4, width: .full),
            .init(view: makeFeatureList(), gapAbove: 8, width: .hugLeading),
            .init(view: showSettingsButton, gapAbove: 14, width: .hugTrailing),
        ])
        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }

    private static func makeFeatureList() -> NSStackView {
        let features = [
            NSLocalizedString("App Icons / Titles styles", comment: ""),
            NSLocalizedString("Additional shortcuts", comment: ""),
            NSLocalizedString("Search", comment: ""),
        ]
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        for feature in features {
            let row = NSTextField(labelWithString: "• " + feature)
            row.font = .systemFont(ofSize: 11)
            row.isSelectable = false
            stack.addArrangedSubview(row)
        }
        return stack
    }
}
