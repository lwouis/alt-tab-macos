import Cocoa

class Day15FullUpgradeWindow: ProPromptWindow {
    static var shared: Day15FullUpgradeWindow?

    /// Opens on the feature the user just tried, else on the one the trial's history favors.
    static func show(for reason: HardGateReason? = nil) {
        guard shared?.isVisible != true else { return }
        ProPromptPopover.closeAll()
        let userInitiated: Bool
        if case .feature = reason { userInitiated = true } else { userInitiated = false }
        showWithTrialEvidence(userInitiated: userInitiated) { evidence in
            guard shared?.isVisible != true else { return }
            let window = Day15FullUpgradeWindow(evidence: evidence, preferred: reason?.attemptedFeature)
            shared = window
            App.showSecondaryWindow(window)
            let state = ProTransitionManager.shared.state
            state.hasSeenFullUpgrade = true
            state.hasSeenProactiveDay15 = true
            state.recordMessage()
        }
    }

    convenience init(evidence: ProJourneyEvidence, preferred: ProJourneyFeature?) {
        self.init(size: NSSize(width: 600, height: 450))
        setJourneyContent(origin: .fullUpgrade, finalReminder: false, evidence: evidence, preferred: preferred)
    }
}

extension ProPromptWindow {
    /// The history is read before the window exists, so it opens on its final tab and height instead of
    /// switching both during its appearance.
    static func showWithTrialEvidence(userInitiated: Bool = false, _ show: @escaping (ProJourneyEvidence) -> Void) {
        ProPromptHost.windowPresentation.load(using: UsageStats.loadTrialEvidence,
            fallback: ProJourneyEvidence(),
            canPresent: { ProPromptHost.canPresent(userInitiated: userInitiated) }, show: show)
    }

    func setJourneyContent(origin: CheckoutOrigin, finalReminder: Bool, evidence: ProJourneyEvidence,
                           preferred: ProJourneyFeature?) {
        let width: CGFloat = 544
        let introduction = ProJourneyView.makeIntroduction(width: width)
        if finalReminder && LicenseManager.shared.state == .trialExpired {
            introduction.update(title: NSLocalizedString("You reached for AltTab Pro this week", comment: ""),
                message: NSLocalizedString("It's still here whenever you need it", comment: ""))
        }
        let journey = ProJourneyView(width: width, preferred: preferred, evidence: evidence)
        let later = NotAdvisedButton(NSLocalizedString("Maybe later", comment: ""))
        later.onAction = { [weak self] _ in self?.close() }
        let getPro = ProPromptButtons.makeGetPro { ProTransitionManager.openCheckout(from: origin) }
        var optOut: NotAdvisedButton?
        if finalReminder {
            optOut = NotAdvisedButton(NSLocalizedString("Don't mention again", comment: "Stops reminders about Pro"))
            optOut?.onAction = { [weak self] _ in
                ProTransitionManager.shared.userOptedOut = true
                self?.close()
            }
        }
        let footer = journey.makePromptFooter(optOut: optOut, dismiss: later, getPro: getPro)
        let stack = NSStackView(views: [introduction, journey, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 28, bottom: 24, right: 28)
        contentView = stack
        fitContentHeight()
    }
}
