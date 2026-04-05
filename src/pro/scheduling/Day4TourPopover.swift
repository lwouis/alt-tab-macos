import Cocoa

class Day4TourPopover {
    private static var popover: NSPopover?

    static func show() {
        let popover = ProPromptPopover.make()

        let width: CGFloat = 280
        let padding: CGFloat = 16
        let innerWidth = width - 2 * padding

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: NSLocalizedString("Your trial includes Pro features", comment: ""))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.isSelectable = false

        let subtitle = NSTextField(wrappingLabelWithString: NSLocalizedString("You're on day 4 of 14 — try these before your trial ends:", comment: ""))
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.isSelectable = false
        subtitle.preferredMaxLayoutWidth = innerWidth

        let features = [
            NSLocalizedString("App Icons / Titles styles", comment: ""),
            NSLocalizedString("Additional shortcuts", comment: ""),
            NSLocalizedString("Search", comment: ""),
        ]
        let featureStack = NSStackView()
        featureStack.translatesAutoresizingMaskIntoConstraints = false
        featureStack.orientation = .vertical
        featureStack.alignment = .leading
        featureStack.spacing = 2
        for feature in features {
            let row = NSTextField(labelWithString: "• " + feature)
            row.font = .systemFont(ofSize: 11)
            row.isSelectable = false
            featureStack.addArrangedSubview(row)
        }

        let showSettingsButton = NSButton(title: NSLocalizedString("Try them in Settings", comment: ""), target: nil, action: nil)
        showSettingsButton.translatesAutoresizingMaskIntoConstraints = false
        showSettingsButton.bezelStyle = .rounded
        showSettingsButton.controlSize = .small
        showSettingsButton.keyEquivalent = "\r"
        showSettingsButton.onAction = { _ in
            popover.performClose(nil)
            App.showSettingsWindow()
        }

        container.addSubview(title)
        container.addSubview(subtitle)
        container.addSubview(featureStack)
        container.addSubview(showSettingsButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),

            title.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            subtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            featureStack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 8),
            featureStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            featureStack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding),

            showSettingsButton.topAnchor.constraint(equalTo: featureStack.bottomAnchor, constant: 14),
            showSettingsButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            showSettingsButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }
}
