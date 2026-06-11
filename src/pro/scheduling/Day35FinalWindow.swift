import Cocoa

class Day35FinalWindow: ProPromptWindow {
    static var shared: Day35FinalWindow?

    private var hero: UsageStatHeroView!

    static func show() {
        if shared == nil { shared = Day35FinalWindow() }
        // The singleton is reused across re-shows; refresh so the cumulative trigger /
        // Pro-use numbers track usage growth instead of staying frozen at first-render.
        shared!.hero.refresh()
        shared!.fitContentHeight()
        App.showSecondaryWindow(shared!)
    }

    convenience init() {
        self.init(size: NSSize(width: 380, height: 280))

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = ProPromptHeader(
            title: NSLocalizedString("Still interested in Pro?", comment: ""),
            size: .compact)

        let hero = UsageStatHeroView()
        self.hero = hero

        let purchaseButton = NSButton(title: NSLocalizedString("Get Pro", comment: ""), target: nil, action: nil)
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false
        purchaseButton.bezelStyle = .rounded
        if #available(macOS 11.0, *) { purchaseButton.controlSize = .large }
        // no .keyEquivalent: this prompt steals focus, so a stray Return must not trigger checkout (#5738)
        purchaseButton.onAction = { _ in ProTransitionManager.openCheckout() }

        let optOutLink = NotAdvisedButton(NSLocalizedString("No thanks — don't ask again", comment: ""))
        optOutLink.onAction = { [weak self] _ in
            ProTransitionManager.shared.userOptedOut = true
            self?.close()
        }

        container.addSubview(header)
        container.addSubview(hero)
        container.addSubview(purchaseButton)
        container.addSubview(optOutLink)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),

            hero.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            hero.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            hero.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            purchaseButton.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 18),
            purchaseButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            optOutLink.topAnchor.constraint(equalTo: purchaseButton.bottomAnchor, constant: 12),
            optOutLink.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            optOutLink.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])

        contentView = container

        fitContentHeight()
    }

    private func fitContentHeight() {
        guard let view = contentView else { return }
        view.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: view.frame.width, height: view.fittingSize.height))
    }
}
