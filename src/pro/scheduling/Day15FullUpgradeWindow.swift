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
        let header = ProPromptHeader(title: ResolvedReason.nonEngaged.unlockHeader, size: .large)
        self.header = header
        let hero = UsageStatHeroView(supportingLine: Self.supportingLine(for: nil))
        self.hero = hero
        let continueLink = NotAdvisedButton(NSLocalizedString("Continue with Free", comment: ""))
        continueLink.onAction = { [weak self] _ in self?.close() }
        setHeroContentView(
            header: header,
            hero: hero,
            purchase: ProPromptButtons.makeGetPro(large: true) { ProTransitionManager.openCheckout() },
            dismiss: continueLink,
            sidePadding: 30, gap: 24, dismissGap: 12)
    }
}
