import Cocoa

class Day1WelcomeLetterWindow: ProPromptWindow {
    static var shared: Day1WelcomeLetterWindow?

    static func show(forceFreshInstall: Bool? = nil) {
        if shared == nil { shared = Day1WelcomeLetterWindow(forceFreshInstall: forceFreshInstall) }
        App.showSecondaryWindow(shared!)
    }

    convenience init(forceFreshInstall: Bool? = nil) {
        self.init(size: NSSize(width: 560, height: 520), miniaturizable: false, movableByBackground: true)

        let isFresh = forceFreshInstall ?? ProTransitionState.isFreshInstall

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleFormat = isFresh
            ? NSLocalizedString("Welcome to %@", comment: "")
            : NSLocalizedString("%@ now has a Pro tier", comment: "")
        let header = ProPromptHeader(title: String(format: titleFormat, App.name), size: .large)

        let messageText = isFresh
            ? NSLocalizedString("AltTab is a free, open-source window switcher for macOS. Pro features are available with a 14-day free trial.", comment: "")
            : NSLocalizedString("You have 14 days to try all Pro features. After that, Pro features will step back and the core window switcher will keep working exactly as before.\n\nAltTab stays free and open-source. Pro is an optional one-time purchase that funds continued development.", comment: "")
        let message = NSTextField(wrappingLabelWithString: messageText)
        message.font = .systemFont(ofSize: 14)
        message.isSelectable = false
        message.translatesAutoresizingMaskIntoConstraints = false
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let comparisonView = makeComparisonView()
        comparisonView.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: NSLocalizedString("Start my 14-day trial", comment: ""), target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        if #available(macOS 11.0, *) { button.controlSize = .large }
        button.onAction = { [weak self] _ in self?.close() }

        container.addSubview(header)
        container.addSubview(message)
        container.addSubview(comparisonView)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 30),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -30),

            message.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            message.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            message.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),

            comparisonView.topAnchor.constraint(equalTo: message.bottomAnchor, constant: 20),
            comparisonView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            comparisonView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),

            button.topAnchor.constraint(equalTo: comparisonView.bottomAnchor, constant: 28),
            button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -24),
        ])

        contentView = container

        container.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: contentView!.frame.width, height: container.fittingSize.height))
    }

    private func makeComparisonView() -> NSView {
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

    private func makeRow(featureView: NSView, freeView: NSView, proView: NSView) -> NSView {
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

    private func makeHeaderCell(_ text: String, _ color: NSColor, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = color
        label.alignment = alignment
        return label
    }

    private func makeGradientProHeaderCell(alignment: NSTextAlignment) -> NSTextField {
        let font = NSFont.systemFont(ofSize: 12, weight: .bold)
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        let attr = NSMutableAttributedString(attributedString: ProGradient.makeProTextAttachment(font: font, baselineOffset: 1))
        attr.addAttribute(.paragraphStyle, value: para, range: NSRange(location: 0, length: attr.length))
        let label = NSTextField(labelWithAttributedString: attr)
        label.alignment = alignment
        return label
    }

    private func makeMarkCell(_ on: Bool, isPro: Bool) -> NSView {
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

