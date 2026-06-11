import Cocoa

class Day15ProactiveWindow: ProPromptWindow {
    static var shared: Day15ProactiveWindow?

    private var hero: UsageStatHeroView!

    static func show() {
        if shared == nil { shared = Day15ProactiveWindow() }
        // The singleton is reused across re-shows; refresh so the cumulative trigger /
        // Pro-use numbers track usage growth instead of staying frozen at first-render.
        // The supportingLine branch is also based on current `UsageStats`, so recompute it
        // here too.
        shared!.hero.supportingLine = supportingLine()
        shared!.hero.refresh()
        shared!.fitContentHeight()
        App.showSecondaryWindow(shared!)
    }

    private static func supportingLine() -> String {
        UsageStats.usedProFeaturesSessionCount == 0
            ? NSLocalizedString(
                "AltTab Pro adds 4 features beyond the free switcher.", comment: "")
            : NSLocalizedString(
                "Some Pro features have reverted to free defaults.", comment: "")
    }

    convenience init() {
        self.init(size: NSSize(width: 380, height: 280))

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = ProPromptHeader(
            title: NSLocalizedString("Your 14-day Pro trial just ended", comment: ""),
            size: .compact)

        let hero = UsageStatHeroView(supportingLine: Self.supportingLine())
        self.hero = hero

        let purchaseButton = NSButton(title: NSLocalizedString("Get Pro", comment: ""), target: nil, action: nil)
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false
        purchaseButton.bezelStyle = .rounded
        if #available(macOS 11.0, *) { purchaseButton.controlSize = .large }
        // no .keyEquivalent: this prompt steals focus, so a stray Return must not trigger checkout (#5738)
        purchaseButton.onAction = { _ in ProTransitionManager.openCheckout() }

        let continueLink = NotAdvisedButton(NSLocalizedString("Maybe later", comment: ""))
        continueLink.onAction = { [weak self] _ in self?.close() }

        container.addSubview(header)
        container.addSubview(hero)
        container.addSubview(purchaseButton)
        container.addSubview(continueLink)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),

            hero.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            hero.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            hero.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),

            purchaseButton.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 18),
            purchaseButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            continueLink.topAnchor.constraint(equalTo: purchaseButton.bottomAnchor, constant: 10),
            continueLink.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            continueLink.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
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
