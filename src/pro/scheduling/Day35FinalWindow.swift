import Cocoa

class Day35FinalWindow: ProPromptWindow {
    static var shared: Day35FinalWindow?

    /// Opens on the feature of the recent attempt that made the user eligible.
    static func show() {
        guard shared?.isVisible != true else { return }
        showWithTrialEvidence { evidence in
            guard shared?.isVisible != true,
                  ProTransitionManagerTestable.evaluateSwitcherOpen(ProTransitionManager.shared.currentState()) == .showDay35Final else { return }
            let window = Day35FinalWindow(evidence: evidence, preferred: ProTransitionManager.shared.state.lastIntent)
            shared = window
            App.showSecondaryWindow(window)
            guard window.isVisible else { return }
            let state = ProTransitionManager.shared.state
            state.hasSeenDay35 = true
            state.recordMessage()
        }
    }

    convenience init(evidence: ProJourneyEvidence, preferred: ProJourneyFeature?) {
        self.init(size: NSSize(width: 600, height: 460))
        setJourneyContent(origin: .day35Final, finalReminder: true, evidence: evidence, preferred: preferred)
    }
}
