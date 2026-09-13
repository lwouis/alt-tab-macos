import Cocoa

class Day21ReminderPopover {
    // periphery:ignore - strong hold, so the popover outlives `show()`
    private static var popover: NSPopover?

    static func show() {
        let popover = ProPromptPopover.make()
        let width = CGFloat(300)
        let container = ProPromptPopover.makeContainer(width: width, [
            .init(view: ProPromptPopover.makeTitle(NSLocalizedString("AltTab Pro is still available", comment: "")),
                gapAbove: 0, width: .full),
            .init(view: ProPromptPopover.makeBody(ProConversionCopy.day21Body(), width: width),
                gapAbove: 8, width: .full),
            .init(view: ProPromptPopover.makeButtonRow(closing: popover), gapAbove: 12, width: .hugTrailing),
        ])
        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }
}
