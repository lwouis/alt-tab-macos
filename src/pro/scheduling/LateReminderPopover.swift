import Cocoa

final class LateReminderPopover {
    static let shared = LateReminderPopover()
    private var popover: AnchoredPopover?
    private let experiment: LateReminderExperiment
    private let context: () -> LateReminderExperiment.Context
    private let presentation: ProPromptPresentation
    private let canPresent: (AnchoredPopover?) -> Bool
    private let makePopover: () -> AnchoredPopover
    private let loadUsage: (Int, Date, @escaping (LateReminderExperiment.Usage) -> Void) -> Void
    private let openCheckout: (CheckoutOrigin) -> Void
    private let optOut: () -> Void

    init(experiment: LateReminderExperiment = ProTransitionManager.shared.lateReminder,
         context: @escaping () -> LateReminderExperiment.Context = ProTransitionManager.shared.lateReminderContext,
         presentation: ProPromptPresentation = ProPromptHost.windowPresentation,
         canPresent: @escaping (AnchoredPopover?) -> Bool = { ProPromptHost.canPresent(userInitiated: false, excluding: $0) },
         makePopover: @escaping () -> AnchoredPopover = { ProPromptPopover.make() },
         loadUsage: @escaping (Int, Date, @escaping (LateReminderExperiment.Usage) -> Void) -> Void = UsageStats.loadLateReminderUsage,
         openCheckout: @escaping (CheckoutOrigin) -> Void = ProTransitionManager.openCheckout,
         optOut: @escaping () -> Void = { ProTransitionManager.shared.userOptedOut = true }) {
        self.experiment = experiment
        self.context = context
        self.presentation = presentation
        self.canPresent = canPresent
        self.makePopover = makePopover
        self.loadUsage = loadUsage
        self.openCheckout = openCheckout
        self.optOut = optOut
    }

    func show() {
        guard popover?.isShown != true, let start = context().trialStart else { return }
        let now = context().now
        let months = LateReminderExperiment.Usage.months(since: start, now: now)
        typealias Loaded = (LateReminderExperiment.Arm?, LateReminderExperiment.Usage)
        presentation.load(using: { [self] (complete: @escaping (Loaded) -> Void) in
            experiment.loadArm { [loadUsage] arm in
                loadUsage(months, now) { complete((arm, $0)) }
            }
        }, fallback: (nil, .init(months: months, count: nil)), canPresent: { [self] in
            canPresent(nil) && experiment.canOffer(context())
        }, show: { [self] arm, usage in
            guard let arm else { return }
            if arm == .control {
                experiment.consume(at: context().now)
                return
            }
            showTreatment(usage)
        })
    }

    private func showTreatment(_ usage: LateReminderExperiment.Usage) {
        let popover = makePopover()
        self.popover = popover
        popover.takesKeyboardFocus = false
        popover.dismissesOnEscapeAndOutsideClick = true
        ProPromptPopover.present(popover, content: makeContent(usage, closing: popover), canPresent: { [self] popover in
            canPresent(popover) && experiment.canOffer(context())
        }, onShown: { [self] in
            experiment.consume(at: context().now)
        })
    }

    private func makeContent(_ usage: LateReminderExperiment.Usage, closing popover: AnchoredPopover) -> NSView {
        let later = NotAdvisedButton(NSLocalizedString("Not now", comment: "Dismiss the one-time late Pro reminder"))
        later.onAction = { [weak popover] _ in
            popover?.acknowledgePresentation()
            popover?.close()
        }
        let getPro = ProPromptButtons.makeGetPro { [weak popover, openCheckout] in
            popover?.acknowledgePresentation()
            popover?.close()
            openCheckout(.lateReminder)
        }
        let buttons = NSStackView(views: [later, getPro])
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.spacing = 12
        let refusal = NotAdvisedButton(NSLocalizedString("Don't mention again", comment: "Stops reminders about Pro"))
        refusal.onAction = { [weak popover, optOut] _ in
            popover?.acknowledgePresentation()
            optOut()
            popover?.close()
        }
        return ProPromptPopover.makeContainer(width: 320, [
            .init(view: ProPromptPopover.makeTitle(NSLocalizedString("AltTab Pro is still here", comment: "")),
                gapAbove: 0, width: .full),
            .init(view: ProPromptPopover.makeBody(Self.body(usage), width: 320), gapAbove: 10, width: .full),
            .init(view: buttons, gapAbove: 14, width: .hugTrailing),
            .init(view: refusal, gapAbove: 10, width: .hugLeading),
        ])
    }

    static func body(_ usage: LateReminderExperiment.Usage) -> String {
        let offer = NSLocalizedString("Search, extra shortcuts and App Icons are a one-time purchase away.", comment: "")
        guard let count = usage.count else { return offer }
        let history = String(format: NSLocalizedString("You've used AltTab %@ times over the last %d months.",
            comment: "Usage count, then rounded number of 30-day months (2 to 12). Counts shortcut uses, not completed switches."),
            UsageStatsTestable.formatCount(count), usage.months)
        return history + "\n\n" + offer
    }
}
