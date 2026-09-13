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
        let hero = UsageStatHeroView()
        self.hero = hero
        let optOutLink = NotAdvisedButton(NSLocalizedString("No thanks — don't ask again", comment: ""))
        optOutLink.onAction = { [weak self] _ in
            ProTransitionManager.shared.userOptedOut = true
            self?.close()
        }
        setHeroContentView(
            header: ProPromptHeader(title: NSLocalizedString("Still interested in Pro?", comment: ""), size: .compact),
            hero: hero,
            purchase: ProPromptButtons.makeGetPro(large: true) { ProTransitionManager.openCheckout() },
            dismiss: optOutLink,
            sidePadding: 20, gap: 18, dismissGap: 12)
    }
}
