import Cocoa

class Day15HardGatePopover {
    // periphery:ignore - strong hold, so the popover outlives `show()`
    private static var popover: NSPopover?

    static func show(for reason: HardGateReason? = nil) {
        let popover = ProPromptPopover.make()
        let container = ProPromptPopover.makeContainer(width: 280, [
            .init(view: ProPromptPopover.makeTitle((reason?.resolved ?? .nonEngaged).unlockHeader),
                gapAbove: 0, width: .hugLeading),
            .init(view: ProPromptPopover.makeButtonRow(closing: popover), gapAbove: 14, width: .hugTrailing),
        ])
        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }
}
