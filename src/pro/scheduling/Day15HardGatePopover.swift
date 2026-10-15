import Cocoa

class Day15HardGatePopover {
    // periphery:ignore - strong hold, so the popover outlives `show()`
    private static var popover: AnchoredPopover?

    static func dismissOnEscape() {
        guard popover?.isShown == true else { return }
        popover?.close()
    }

    static func show(for reason: HardGateReason? = nil,
                     makePopover: () -> AnchoredPopover = { ProPromptPopover.make() },
                     openCheckout: @escaping (CheckoutOrigin) -> Void = ProTransitionManager.openCheckout,
                     canPresent: @escaping (AnchoredPopover?) -> Bool = {
                         ProPromptHost.presentationContext(excluding: $0).allows(userInitiated: true, blockedFeaturePopover: true)
                     }) {
        if Day15FullUpgradeWindow.shared?.isVisible == true ||
            Day35FinalWindow.shared?.isVisible == true {
            return
        }
        // An open gate closes too: its title names the feature tried before this attempt.
        ProPromptPopover.closeAll()
        let popover = makePopover()
        // Window switching changes key windows and activates other apps. Keep the purchase affordance
        // until dismissal input, replacement, or workspace/session cancellation closes it.
        popover.behavior = .applicationDefined
        popover.dismissesOnEscapeAndOutsideClick = true
        // Anchor layout may finish after modifier release has focused the selected app.
        popover.takesKeyboardFocus = false
        let container = ProPromptPopover.makeContainer(width: 280, [
            .init(view: ProPromptPopover.makeTitle((reason?.resolved ?? .nonEngaged).unlockHeader),
                gapAbove: 0, width: .hugLeading),
            .init(view: ProPromptPopover.makeBody(ProFeatureCopy.purchaseTerms, width: 280),
                gapAbove: 10, width: .full),
            .init(
                view: ProPromptPopover.makeButtonRow(closing: popover, origin: .hardGate, openCheckout: openCheckout), gapAbove: 14, width: .hugTrailing),
        ])
        ProPromptPopover.present(popover, content: container, userInitiated: true, canPresent: canPresent)
        self.popover = popover
    }
}
