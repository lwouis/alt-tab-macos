import Cocoa

class Day12HeadsUpPopover {
    // periphery:ignore - strong hold, so the popover outlives `show()`
    private static var popover: NSPopover?

    static func show() {
        let popover = ProPromptPopover.make()
        let width = CGFloat(300)
        let container = ProPromptPopover.makeContainer(width: width, [
            .init(view: ProPromptPopover.makeTitle(NSLocalizedString("Your Pro trial ends in 2 days", comment: "")),
                gapAbove: 0, width: .hugLeading),
            .init(view: ProPromptPopover.makeBody(ProConversionCopy.day12Subtitle(), width: width),
                gapAbove: 6, width: .full),
            .init(view: ProPromptPopover.makeButtonRow(closing: popover), gapAbove: 14, width: .hugTrailing),
        ])
        ProPromptPopover.present(popover, content: container)
        self.popover = popover
    }
}
