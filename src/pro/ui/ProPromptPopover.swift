import Cocoa

/// Shared plumbing for the Pro-transition menubar-anchored popovers ([B] Day 12 Heads-Up,
/// [E] Day 15 Hard Gate, [F] Day 21 Reminder, [H] Day 4 Tour). Centralises construction
/// (transient behavior, optional fixed content size), presentation (activate app, anchor
/// below the menubar icon, make the popover window key), and the content layout the four
/// share: a fixed-width column of rows inset by `padding`, ending in a button row.
enum ProPromptPopover {
    static let padding = CGFloat(16)
    private static let popovers = NSHashTable<NSPopover>.weakObjects()
    static var isShowing: Bool { popovers.allObjects.contains { $0.isShown } }

    /// How a row sits in the column: hugging its own width at the leading edge, stretched to the
    /// full column (what a wrapping label needs), or hugging its own width at the trailing edge.
    enum RowWidth {
        case hugLeading
        case full
        case hugTrailing
    }

    struct Row {
        let view: NSView
        /// Vertical gap above this row. The first row's gap is on top of `padding`, so pass 0 there.
        let gapAbove: CGFloat
        let width: RowWidth
    }

    /// Build a transient popover ready for the caller to fill with content. A fixed content
    /// size is optional — omit for views that are auto-sized via constraints.
    static func make(contentSize: NSSize? = nil) -> NSPopover {
        let popover = NSPopover()
        popovers.add(popover)
        popover.behavior = .transient
        if let contentSize { popover.contentSize = contentSize }
        return popover
    }

    /// Anchor the popover below the menubar icon and make its content window key.
    static func present(_ popover: NSPopover, content: NSView) {
        let vc = NSViewController()
        vc.view = content
        popover.contentViewController = vc
        App.shared.activate(ignoringOtherApps: true)
        Menubar.showPopoverFromMenubar(popover)
        popover.contentViewController?.view.window?.makeKey()
    }

    static func makeContainer(width: CGFloat, _ rows: [Row]) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        var constraints = [container.widthAnchor.constraint(equalToConstant: width)]
        var previousBottom = container.topAnchor
        var topInset = padding
        for row in rows {
            container.addSubview(row.view)
            constraints.append(row.view.topAnchor.constraint(equalTo: previousBottom, constant: topInset + row.gapAbove))
            switch row.width {
                case .hugLeading:
                    constraints.append(row.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding))
                    constraints.append(row.view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding))
                case .full:
                    constraints.append(row.view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding))
                    constraints.append(row.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding))
                case .hugTrailing:
                    constraints.append(row.view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding))
            }
            previousBottom = row.view.bottomAnchor
            topInset = 0
        }
        constraints.append(previousBottom.constraint(equalTo: container.bottomAnchor, constant: -padding))
        NSLayoutConstraint.activate(constraints)
        return container
    }

    static func makeTitle(_ text: String) -> NSTextField {
        let title = NSTextField(labelWithString: text)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.isSelectable = false
        return title
    }

    static func makeBody(_ text: String, width: CGFloat) -> NSTextField {
        let body = NSTextField(wrappingLabelWithString: text)
        body.font = .systemFont(ofSize: 11)
        body.textColor = .secondaryLabelColor
        body.translatesAutoresizingMaskIntoConstraints = false
        body.isSelectable = false
        body.preferredMaxLayoutWidth = width - 2 * padding
        body.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return body
    }

    /// The [Not now] [Get Pro] pair every popover but Day 4 ends with. Both dismiss the popover;
    /// `Get Pro` also opens checkout.
    static func makeButtonRow(closing popover: NSPopover) -> NSStackView {
        let notNow = NotAdvisedButton(NSLocalizedString("Not now", comment: ""))
        notNow.onAction = { _ in popover.performClose(nil) }
        let getPro = ProPromptButtons.makeGetPro(large: false) {
            popover.performClose(nil)
            ProTransitionManager.openCheckout()
        }
        let row = NSStackView(views: [notNow, getPro])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }
}
