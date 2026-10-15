import Cocoa

/// Presents coordinator actions and cancels stale requests when the workspace changes.
class ProPromptHost {
    static let shared = ProPromptHost()
    static let windowPresentation = ProPromptPresentation()

    private let context: (AnchoredPopover?) -> ProPromptPresentation.Context
    private let makeHardGatePopover: () -> AnchoredPopover
    private let openCheckout: (CheckoutOrigin) -> Void
    private var observers = [NSObjectProtocol]()

    init(context: @escaping (AnchoredPopover?) -> ProPromptPresentation.Context = ProPromptHost.presentationContext,
         makeHardGatePopover: @escaping () -> AnchoredPopover = { ProPromptPopover.make() },
         openCheckout: @escaping (CheckoutOrigin) -> Void = ProTransitionManager.openCheckout,
         observeWorkspace: Bool = true) {
        self.openCheckout = openCheckout
        self.context = context
        self.makeHardGatePopover = makeHardGatePopover
        guard observeWorkspace else { return }
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.screensDidSleepNotification] {
            observe(name) { Self.cancelTransientPrompts() }
        }
        observe(NSWorkspace.activeSpaceDidChangeNotification) {
            Self.windowPresentation.cancel()
            ProPromptPopover.closeAll()
            SearchDiscoveryHint.shared.cancel()
            ProTransitionManager.shared.activeSpaceDidChange()
        }
    }

    deinit {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }

    private func observe(_ name: Notification.Name, _ action: @escaping () -> Void) {
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
            action()
        })
    }

    static func cancelTransientPrompts() {
        ProTransitionManager.shared.cancelPendingPrompts()
        ProPromptPopover.closeAll()
        SearchDiscoveryHint.shared.cancel()
    }

    static var sessionIsAvailable: Bool {
        guard !ScreenLockEvents.isScreenLocked,
              let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session[kCGSessionOnConsoleKey as String] as? Bool == true
    }

    static var canPresentProactively: Bool {
        presentationContext().canPresentProactively
    }

    static func canPresent(userInitiated: Bool, excluding popover: AnchoredPopover? = nil) -> Bool {
        shared.context(popover).allows(userInitiated: userInitiated)
    }

    static func presentationContext(excluding popover: AnchoredPopover? = nil) -> ProPromptPresentation.Context {
        let state = ProTransitionManager.shared.state
        return ProPromptPresentation.Context(
            sessionAvailable: sessionIsAvailable,
            isPro: LicenseManager.shared.state == .pro,
            switcherActive: SwitcherSession.isActive,
            onboarding: state.onboardingInProgress || LicenseManager.shared.state == .trialNotStarted,
            competingUI: ContextMenuEvents.isMenuOpen || ProPromptPopover.isShowing(excluding: popover) ||
                NSApp.modalWindow != nil || NSApp.windows.contains {
                    $0.isVisible && ($0 is ProPromptWindow || $0 is PermissionsWindow ||
                        $0 is SettingsWindow || $0 is FeedbackWindow)
                },
            fullscreen: Windows.list.contains { $0.application.pid == Applications.frontmostPid && $0.isFullscreen },
            optedOut: state.userOptedOut,
            messageToday: state.messageShownToday(LicenseManager.shared.clock.now)
        )
    }

    func dispatch(_ action: ProPromptAction) {
        switch action {
        case .refreshBadge, .dismissAllProWindows: break
        default: SearchDiscoveryHint.shared.cancel()
        }
        switch action {
        case .showWelcome:
            Day1WelcomeLetterPopover.show()
        case .showDay4Tour:
            Day4TourPopover.show()
        case let .showDay15FullUpgrade(reason):
            Day15FullUpgradeWindow.show(for: reason)
        case let .showDay15HardGatePopover(reason):
            Day15HardGatePopover.show(for: reason, makePopover: makeHardGatePopover, openCheckout: openCheckout) { [context] popover in
                context(popover).allows(userInitiated: true, blockedFeaturePopover: true)
            }
        case .showDay35Final:
            Day35FinalWindow.show()
        case .dismissAllProWindows:
            Self.windowPresentation.cancel()
            SearchDiscoveryHint.shared.cancel()
            ProPromptPopover.closeAll()
            Day1WelcomeLetterPopover.close()
            Day15FullUpgradeWindow.shared?.close()
            Day35FinalWindow.shared?.close()
        case .refreshBadge:
            Menubar.menubarIconCallback(nil)
        }
    }
}
