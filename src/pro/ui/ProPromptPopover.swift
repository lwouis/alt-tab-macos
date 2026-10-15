import Cocoa

/// Shared plumbing for the Pro-transition menubar-anchored popovers ([A] Day 1 Welcome,
/// [E] Day 15 Hard Gate, [H] Day 4 Tour). Centralises construction (optional fixed content size),
/// presentation below the menubar icon, and the
/// content layout both share: a fixed-width column of rows inset by `padding`, ending in a button row.
enum ProPromptPopover {
    static let padding = CGFloat(16)
    private static let popovers = NSHashTable<AnchoredPopover>.weakObjects()
    static var isShowing: Bool { isShowing(excluding: nil) }

    static func isShowing(excluding popover: AnchoredPopover?) -> Bool {
        popovers.allObjects.contains { $0 !== popover && ($0.isShown || $0.isWaitingForAnchor) }
    }

    static func closeAll() {
        popovers.allObjects.forEach { $0.close() }
    }

    static func cancelPendingPresentations() {
        popovers.allObjects.filter { $0.isWaitingForAnchor }.forEach { $0.cancelPresentation() }
    }

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

    /// Defaults to transient dismissal; the independent blocked-feature gate overrides it. A fixed content
    /// size is optional — omit for views that are auto-sized via constraints.
    static func make(contentSize: NSSize? = nil, popover: AnchoredPopover = AnchoredPopover()) -> AnchoredPopover {
        popovers.add(popover)
        popover.behavior = .transient
        if let contentSize { popover.contentSize = contentSize }
        return popover
    }

    /// Recheck eligibility after anchor layout, excluding this request from the occupied prompt slot.
    static func present(_ popover: AnchoredPopover, content: NSView, userInitiated: Bool = false,
                        canPresent: ((AnchoredPopover?) -> Bool)? = nil, onShown: (() -> Void)? = nil) {
        popover.present(content, from: Menubar.statusItem, canPresent: { [weak popover] in
            canPresent?(popover) ?? ProPromptHost.canPresent(userInitiated: userInitiated, excluding: popover)
        }) {
            ProTransitionManager.shared.state.recordMessage()
            onShown?()
        }
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
        let title = NSTextField(wrappingLabelWithString: text)
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

    /// The [Maybe later] [Get Pro] pair for blocked features. Both dismiss the popover;
    /// `Get Pro` also opens checkout.
    static func makeButtonRow(closing popover: AnchoredPopover, origin: CheckoutOrigin,
                              openCheckout: @escaping (CheckoutOrigin) -> Void = ProTransitionManager.openCheckout) -> NSStackView {
        let later = NotAdvisedButton(NSLocalizedString("Maybe later", comment: ""))
        later.onAction = { [weak popover] _ in
            popover?.acknowledgePresentation()
            popover?.close()
        }
        let getPro = ProPromptButtons.makeGetPro { [weak popover] in
            popover?.acknowledgePresentation()
            popover?.close()
            openCheckout(origin)
        }
        let row = NSStackView(views: [later, getPro])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.spacing = 12
        return row
    }
}
