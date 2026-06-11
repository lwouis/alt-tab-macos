import Cocoa

class Day15FullUpgradeWindow: ProPromptWindow {
    static var shared: Day15FullUpgradeWindow?

    private var header: ProPromptHeader!
    private var hero: UsageStatHeroView!

    static func show(for reason: HardGateReason? = nil) {
        if shared == nil { shared = Day15FullUpgradeWindow() }
        shared!.header.title = (reason?.resolved ?? .nonEngaged).unlockHeader
        shared!.hero.supportingLine = supportingLine(for: reason)
        // The singleton is reused across re-shows; refresh so the cumulative trigger /
        // Pro-use numbers track usage growth instead of staying frozen at first-render.
        shared!.hero.refresh()
        shared!.fitContentHeight()
        App.showSecondaryWindow(shared!)
    }

    private static func supportingLine(for reason: HardGateReason?) -> String {
        let resolved = reason?.resolved ?? .nonEngaged
        if resolved == .nonEngaged || UsageStats.usedProFeaturesSessionCount == 0 {
            return NSLocalizedString(
                "AltTab Pro adds 4 features beyond the free switcher.",
                comment: "")
        }
        let revertSentence = NSLocalizedString(
            "Some Pro features have reverted to free defaults.", comment: "")
        switch resolved {
        case .extraShortcut:
            return revertSentence + "\n" + NSLocalizedString(
                "Extra shortcuts are a Pro feature.", comment: "")
        case .search:
            return revertSentence + "\n" + NSLocalizedString(
                "Search is a Pro feature.", comment: "")
        case .appIconsStyle:
            return revertSentence + "\n" + NSLocalizedString(
                "The App Icons style is a Pro feature.", comment: "")
        case .titlesStyle:
            return revertSentence + "\n" + NSLocalizedString(
                "The Titles style is a Pro feature.", comment: "")
        case .nonEngaged:
            return ""
        }
    }

    convenience init() {
        self.init(size: NSSize(width: 440, height: 340))

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let header = ProPromptHeader(title: ResolvedReason.nonEngaged.unlockHeader, size: .large)
        self.header = header

        let hero = UsageStatHeroView(supportingLine: Self.supportingLine(for: nil))
        self.hero = hero

        let purchaseButton = NSButton(title: NSLocalizedString("Get Pro", comment: ""), target: nil, action: nil)
        purchaseButton.translatesAutoresizingMaskIntoConstraints = false
        purchaseButton.bezelStyle = .rounded
        if #available(macOS 11.0, *) { purchaseButton.controlSize = .large }
        // no .keyEquivalent: this prompt steals focus, so a stray Return must not trigger checkout (#5738)
        purchaseButton.onAction = { _ in ProTransitionManager.openCheckout() }

        let continueLink = NotAdvisedButton(NSLocalizedString("Continue with Free", comment: ""))
        continueLink.onAction = { [weak self] _ in self?.close() }

        container.addSubview(header)
        container.addSubview(hero)
        container.addSubview(purchaseButton)
        container.addSubview(continueLink)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 30),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -30),

            hero.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            hero.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            hero.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),

            purchaseButton.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 24),
            purchaseButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            continueLink.topAnchor.constraint(equalTo: purchaseButton.bottomAnchor, constant: 12),
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
