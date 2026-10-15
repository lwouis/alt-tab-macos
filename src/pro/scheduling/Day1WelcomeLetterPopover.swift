import Cocoa

enum Day1WelcomeLetterPopover {
    private static var popover: AnchoredPopover?
    private static let padding = CGFloat(30)
    private static let comparisonWidth = CGFloat(500)

    static func owns(_ object: Any?) -> Bool {
        guard let popover else { return false }
        return (object as AnyObject?) === popover
    }

    /// Not rechecked against the prompt rules at anchor time: the scheduler already did, and marked the
    /// letter as seen before asking for it.
    static func show(forceFreshInstall: Bool? = nil) {
        LicenseManager.shared.refreshState()
        guard case .trial = LicenseManager.shared.state else { return }
        close()
        let popover = ProPromptPopover.make()
        self.popover = popover
        popover.present(makeContent(isFresh: forceFreshInstall ?? ProTransitionState.isFreshInstall, closing: popover),
            from: Menubar.statusItem)
    }

    static func close() {
        popover?.close()
    }

    private static func makeContent(isFresh: Bool, closing popover: AnchoredPopover) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleFormat = isFresh
            ? NSLocalizedString("Welcome to %@", comment: "")
            : NSLocalizedString("%@ now has a Pro tier", comment: "")
        let header = ProPromptHeader(title: String(format: titleFormat, App.name), size: .large)

        let messageText = [LicenseManager.shared.trialEndDate.map(ProFeatureCopy.includedUntil)
            ?? ProFeatureCopy.trialSetup, ProFeatureCopy.trialPromise].joined(separator: "\n\n")
        let message = NSTextField(wrappingLabelWithString: messageText)
        message.font = .systemFont(ofSize: 14)
        message.isSelectable = false
        message.translatesAutoresizingMaskIntoConstraints = false
        message.preferredMaxLayoutWidth = comparisonWidth
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let comparisonView = makeComparisonView()
        comparisonView.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: NSLocalizedString("Continue", comment: ""), target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.controlSize = .large
        button.onAction = { [weak popover] _ in popover?.close() }

        container.addSubview(header)
        container.addSubview(message)
        container.addSubview(comparisonView)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: comparisonWidth + 2 * padding),

            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: padding),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -padding),

            message.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            message.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            message.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            comparisonView.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 20),
            comparisonView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: padding),
            comparisonView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -padding),

            button.topAnchor.constraint(equalTo: comparisonView.bottomAnchor, constant: 28),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])
        return container
    }

    private static func makeComparisonView() -> NSView {
        let data: [(String, Bool, Bool)] = [
            (NSLocalizedString("Reliable, fast window switching with high-quality thumbnails", comment: ""), true, true),
            (NSLocalizedString("Dark Mode, live preview, window controls, trackpad gestures, and more", comment: ""), true, true),
            (ProFeatureCopy.appIconsAndTitles, false, true),
            (ProFeatureCopy.search, false, true),
            (ProFeatureCopy.autoSize, false, true),
            (ProFeatureCopy.extraShortcuts, false, true),
        ]

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let headerFeature = makeHeaderCell(NSLocalizedString("Feature", comment: ""), .labelColor, alignment: .left)
        let headerFree = makeHeaderCell(NSLocalizedString("Free", comment: ""), .secondaryLabelColor, alignment: .center)
        let headerPro = makeGradientProHeaderCell(alignment: .center)
        stack.addArrangedSubview(makeRow(featureView: headerFeature, freeView: headerFree, proView: headerPro))

        for (text, free, pro) in data {
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 12)
            label.isSelectable = false
            label.preferredMaxLayoutWidth = 368
            stack.addArrangedSubview(makeRow(featureView: label, freeView: makeMarkCell(free, isPro: false), proView: makeMarkCell(pro, isPro: true)))
        }
        return stack
    }

    private static func makeRow(featureView: NSView, freeView: NSView, proView: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        featureView.translatesAutoresizingMaskIntoConstraints = false
        freeView.translatesAutoresizingMaskIntoConstraints = false
        proView.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(featureView)
        row.addSubview(freeView)
        row.addSubview(proView)
        NSLayoutConstraint.activate([
            featureView.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            featureView.widthAnchor.constraint(equalToConstant: 368),
            featureView.topAnchor.constraint(equalTo: row.topAnchor),
            featureView.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            freeView.leadingAnchor.constraint(equalTo: featureView.trailingAnchor, constant: 16),
            freeView.widthAnchor.constraint(equalToConstant: 50),
            freeView.centerYAnchor.constraint(equalTo: featureView.centerYAnchor),
            proView.leadingAnchor.constraint(equalTo: freeView.trailingAnchor, constant: 16),
            proView.widthAnchor.constraint(equalToConstant: 50),
            proView.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            proView.centerYAnchor.constraint(equalTo: featureView.centerYAnchor),
        ])
        return row
    }

    private static func makeHeaderCell(_ text: String, _ color: NSColor, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = color
        label.alignment = alignment
        return label
    }

    private static func makeGradientProHeaderCell(alignment: NSTextAlignment) -> NSTextField {
        let font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        let attr = NSMutableAttributedString(attributedString: ProGradient.makeProTextAttachment(font: font, baselineOffset: 1))
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))
        let label = NSTextField(labelWithAttributedString: attr)
        label.alignment = alignment
        return label
    }

    private static func makeMarkCell(_ on: Bool, isPro: Bool) -> NSView {
        if on && isPro {
            let image = ProGradient.makeGradientTextImage("✓", font: .systemFont(ofSize: 14, weight: .bold))
            let imageView = NSImageView()
            imageView.image = image
            imageView.imageAlignment = .alignCenter
            return imageView
        }
        let label = NSTextField(labelWithString: on ? "✓" : "—")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = on ? .systemGreen : .tertiaryLabelColor
        label.alignment = .center
        return label
    }
}

