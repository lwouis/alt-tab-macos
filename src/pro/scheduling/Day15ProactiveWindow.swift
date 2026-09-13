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
        let hero = UsageStatHeroView(supportingLine: Self.supportingLine())
        self.hero = hero
        let continueLink = NotAdvisedButton(NSLocalizedString("Maybe later", comment: ""))
        continueLink.onAction = { [weak self] _ in self?.close() }
        setHeroContentView(
            header: ProPromptHeader(title: NSLocalizedString("Your 14-day Pro trial just ended", comment: ""), size: .compact),
            hero: hero,
            purchase: ProPromptButtons.makeGetPro(large: true) { ProTransitionManager.openCheckout() },
            dismiss: continueLink,
            sidePadding: 24, gap: 18, dismissGap: 10)
    }
}
