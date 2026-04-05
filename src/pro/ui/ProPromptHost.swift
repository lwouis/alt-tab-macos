import Cocoa

/// UI-side receiver of `ProPromptAction`s emitted by `ProTransitionManager`. Owns the mapping
/// from abstract prompt-action → concrete Day-X window / popover class. Subscribing here is what
/// keeps the coordinator (in `logic/licensing/`) free of AppKit references.
///
/// Wired at app launch: `ProTransitionManager.shared.onAction = { ProPromptHost.shared.dispatch($0) }`.
class ProPromptHost {
    static let shared = ProPromptHost()

    func dispatch(_ action: ProPromptAction) {
        switch action {
        case .showWelcome:
            Day1WelcomeLetterWindow.show()
        case .showDay4Tour:
            Day4TourPopover.show()
        case .showDay12HeadsUp:
            Day12HeadsUpPopover.show()
            Menubar.menubarIconCallback(nil)
        case .showDay15Proactive:
            Day15ProactiveWindow.show()
        case .showDay15FullUpgrade(let reason):
            Day15FullUpgradeWindow.show(for: reason)
        case .showDay15HardGatePopover(let reason):
            Day15HardGatePopover.show(for: reason)
        case .showDay21Reminder:
            Day21ReminderPopover.show()
        case .showDay35Final:
            Day35FinalWindow.show()
        case .dismissAllProWindows:
            Day1WelcomeLetterWindow.shared?.close()
            Day15FullUpgradeWindow.shared?.close()
            Day15ProactiveWindow.shared?.close()
            Day35FinalWindow.shared?.close()
        case .refreshBadge:
            Menubar.menubarIconCallback(nil)
        }
    }
}
