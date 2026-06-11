import Cocoa

class Day12HeadsUpPopover {
    private static var popover: NSPopover?

    static func show() {
        let popover = ProPromptPopover.make()

        let width: CGFloat = 300
        let padding: CGFloat = 16
        let innerWidth = width - 2 * padding

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: NSLocalizedString("Your Pro trial ends in 2 days", comment: ""))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.isSelectable = false

        let subtitle = NSTextField(wrappingLabelWithString: ProConversionCopy.day12Subtitle())
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.isSelectable = false
        subtitle.preferredMaxLayoutWidth = innerWidth

        let notNow = NotAdvisedButton(NSLocalizedString("Not now", comment: ""))
        notNow.onAction = { _ in popover.performClose(nil) }

        let getPro = NSButton(title: NSLocalizedString("Get Pro", comment: ""), target: nil, action: nil)
        getPro.translatesAutoresizingMaskIntoConstraints = false
        getPro.bezelStyle = .rounded
        getPro.controlSize = .small
        // no .keyEquivalent: this prompt steals focus, so a stray Return must not trigger checkout (#5738)
        getPro.onAction = { _ in
            popover.performClose(nil)
            ProTransitionManager.openCheckout()
        }

        let buttonStack = NSStackView(views: [notNow, getPro])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        container.addSubview(title)
        container.addSubview(subtitle)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),

            title.topAnchor.constraint(equalTo: container.topAnchor, constant: padding),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            title.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            subtitle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            buttonStack.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -padding),
        ])

        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }
}
