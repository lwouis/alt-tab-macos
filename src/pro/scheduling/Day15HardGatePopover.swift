import Cocoa

class Day15HardGatePopover {
    private static var popover: NSPopover?

    static func show(for reason: HardGateReason? = nil) {
        let popover = ProPromptPopover.make()

        let width: CGFloat = 280

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: (reason?.resolved ?? .nonEngaged).unlockHeader)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let purchaseButton = NSButton(title: NSLocalizedString("Get Pro", comment: ""), target: nil, action: nil)
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false
        purchaseButton.controlSize = .small
        purchaseButton.bezelStyle = .rounded
        // no .keyEquivalent: this prompt steals focus, so a stray Return must not trigger checkout (#5738)
        purchaseButton.onAction = { _ in
            popover.performClose(nil)
            ProTransitionManager.openCheckout()
        }

        let notNow = NotAdvisedButton(NSLocalizedString("Not now", comment: ""))
        notNow.onAction = { _ in popover.performClose(nil) }

        let buttonStack = NSStackView(views: [notNow, purchaseButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12

        container.addSubview(title)
        container.addSubview(buttonStack)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: width),

            title.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            title.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            title.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),

            buttonStack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            buttonStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            buttonStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
        ])

        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }
}
