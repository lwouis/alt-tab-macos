import Cocoa

/// Shared by the expiration announcement and the persistent Settings page.
final class ProJourneyView: NSStackView {
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let usage = NSTextField(wrappingLabelWithString: "")
    private let illustration = NSStackView()
    private let purchase = NSStackView()
    private let tabs: NSSegmentedControl
    private var evidence = ProJourneyEvidence()
    private var selectionWasExplicit = false
    private var reservesUsageLine = false
    private var refreshGeneration = 0
    private var selected: ProJourneyFeature
    private let preferred: ProJourneyFeature?
    private let contentWidth: CGFloat

    /// Prompts supply evidence before presentation. Settings may adopt loaded history only while hidden.
    init(width: CGFloat, preferred: ProJourneyFeature? = nil, evidence: ProJourneyEvidence? = nil) {
        contentWidth = width
        self.preferred = preferred
        self.evidence = evidence ?? ProJourneyEvidence()
        selected = self.evidence.openingFeature(requested: preferred)
        tabs = NSSegmentedControl(
            labels: [NSLocalizedString("Search", comment: ""), NSLocalizedString("Styles", comment: ""),
                     NSLocalizedString("Shortcuts", comment: ""), NSLocalizedString(
                         "Auto Size",
                         comment: ""
                     )],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .leading
        spacing = 16
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.isSelectable = false
        usage.isSelectable = false
        usage.font = .systemFont(ofSize: 13)
        usage.textColor = .labelColor
        usage.alignment = .natural
        tabs.segmentDistribution = .fillEqually
        tabs.onAction = { [weak self] _ in
            guard let self else { return }
            select(ProJourneyFeature.allCases[tabs.selectedSegment])
        }
        illustration.orientation = .horizontal
        illustration.distribution = .fill
        illustration.alignment = .centerY
        illustration.heightAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        illustration.spacing = 8
        for item in [heading, tabs, illustration] {
            item.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(item)
            item.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        render()
        if evidence == nil { refresh() }
    }

    static func makeIntroduction(width: CGFloat) -> MascotMessageView {
        let view = MascotMessageView(title: "", message: "", emphasizeMessage: true)
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        refreshIntroduction(view)
        return view
    }

    static func refreshIntroduction(_ view: MascotMessageView) {
        let license = LicenseManager.shared
        let status: String
        let message: String
        switch license.state {
        case .trialNotStarted:
            status = ProFeatureCopy.trialSetup
            message = ""
        case .trialExpired:
            status = NSLocalizedString("Your AltTab Pro trial has ended", comment: "")
            message = NSLocalizedString("Get Pro to keep these features", comment: "")
        case .proExpired:
            status = NSLocalizedString("This version needs a newer license", comment: "")
            message = NSLocalizedString("Get Pro for this version", comment: "")
        case let .trial(daysRemaining):
            status = String(format: NSLocalizedString("Trial: %d days remaining", comment: ""), daysRemaining)
            message = NSLocalizedString("Try all four Pro features.", comment: "")
        case .pro:
            let format = license.isLifetimeVariant
                ? NSLocalizedString("Pro Lifetime license activated for %@", comment: "")
                : NSLocalizedString("Pro license activated for %@", comment: "")
            status = String(format: format, license.customerEmail ?? "")
            message = NSLocalizedString("Unlimited access to all four Pro features", comment: "")
        }
        view.update(title: status, message: message, proGradient: license.isProLocked)
    }

    func select(_ feature: ProJourneyFeature) {
        selectionWasExplicit = true
        selected = feature
        render()
    }

    func refresh() {
        refreshGeneration += 1
        let generation = refreshGeneration
        UsageStats.loadTrialEvidence { [weak self] evidence in
            guard let self, refreshGeneration == generation else { return }
            self.evidence = evidence
            if !selectionWasExplicit && window?.isVisible != true {
                selected = evidence.openingFeature(requested: preferred)
            }
            render()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func render() {
        tabs.selectedSegment = ProJourneyFeature.allCases.firstIndex(of: selected)!
        for arrangedSubview in illustration.arrangedSubviews {
            illustration.removeArrangedSubview(arrangedSubview); arrangedSubview.removeFromSuperview()
        }
        usage.stringValue = ""
        switch selected {
        case .search:
            heading.stringValue = NSLocalizedString("Find a window by typing", comment: "")
            comparison("search-comparison", during: duringLabel(.search))
            if evidence.used(.search), let count = evidence.searches {
                usage.stringValue = String(
                    format: NSLocalizedString("Searches started during your trial: %@", comment: ""),
                    UsageStats.formatCount(count)
                )
            }
        case .styles:
            let style = evidence.adoptedStyle.flatMap { AppearanceStylePreference.allCases[safe: $0] } ??
                .titles
            heading.stringValue = style == .titles
                ? NSLocalizedString("See your windows in a compact list", comment: "")
                : NSLocalizedString("Recognize your apps at a glance", comment: "")
            comparison(style == .appIcons ? "styles-app-icons-comparison" : "styles-titles-comparison",
                during: duringLabel(.styles))
        case .shortcuts:
            heading.stringValue = NSLocalizedString("Choose which windows to switch between", comment: "")
            comparison("shortcuts-comparison", during: duringLabel(.shortcuts))
            if evidence.used(.shortcuts), let count = evidence.extraShortcuts {
                usage.stringValue = String(
                    format: NSLocalizedString("Extra shortcut uses during your trial: %@", comment: ""),
                    UsageStats.formatCount(count)
                )
            }
        case .autoSize:
            heading.stringValue = NSLocalizedString("Give your previews more room", comment: "")
            comparison("auto-size-comparison", during: duringLabel(.autoSize))
        }
        if !usage.stringValue.isEmpty {
            let attributed = NSMutableAttributedString(string: usage.stringValue,
                attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor])
            let count = selected == .search ? evidence.searches : evidence.extraShortcuts
            if let count {
                let range = (usage.stringValue as NSString).range(of: UsageStats.formatCount(count))
                if range.location != NSNotFound {
                    attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .semibold), range: range)
                }
            }
            usage.attributedStringValue = attributed
        }
        usage.isHidden = usage.stringValue.isEmpty && !reservesUsageLine
        window?.contentView?.needsLayout = true
        (window as? ProPromptWindow)?.fitContentHeight()
    }

    /// Settings puts its license links in `leading`, under the usage.
    func makeFooter(actions: NSView, leading: NSView? = nil) -> NSView {
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        let info = NSStackView(views: [usage] + (leading.map { [$0] } ?? []))
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 8
        purchase.setViews([actions, makePurchaseTerms()], in: .top)
        purchase.orientation = .vertical
        purchase.alignment = .trailing
        purchase.spacing = 4
        for view in [info, purchase] {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        purchase.setContentHuggingPriority(.required, for: .horizontal)
        purchase.setContentCompressionResistancePriority(.required, for: .horizontal)
        let purchaseWidth = purchase.fittingSize.width
        usage.preferredMaxLayoutWidth = max(1, contentWidth - purchaseWidth - 16)
        NSLayoutConstraint.activate([
            footer.widthAnchor.constraint(equalToConstant: contentWidth),
            purchase.widthAnchor.constraint(equalToConstant: purchaseWidth),
            info.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            info.trailingAnchor.constraint(lessThanOrEqualTo: purchase.leadingAnchor, constant: -16),
            info.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            info.topAnchor.constraint(greaterThanOrEqualTo: footer.topAnchor),
            info.bottomAnchor.constraint(lessThanOrEqualTo: footer.bottomAnchor),
            purchase.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            purchase.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            purchase.topAnchor.constraint(greaterThanOrEqualTo: footer.topAnchor),
            purchase.bottomAnchor.constraint(lessThanOrEqualTo: footer.bottomAnchor),
        ])
        return footer
    }

    /// Prompts: usage on its own line, kept while empty so switching tabs doesn't resize the window. Below it,
    /// [dismiss] beside [Get Pro] at the trailing edge, and the persistent opt-out, if any, alone at the leading
    /// edge, level with them. Unlike Settings, no terms.
    func makePromptFooter(optOut: NSView?, dismiss: NSView, getPro: NSView) -> NSView {
        reservesUsageLine = true
        usage.isHidden = false
        usage.preferredMaxLayoutWidth = contentWidth
        let actions = NSStackView(views: [dismiss, getPro])
        actions.spacing = 12
        let footer = NSView()
        for view in [usage, actions] + (optOut.map { [$0] } ?? []) {
            view.translatesAutoresizingMaskIntoConstraints = false
            footer.addSubview(view)
        }
        NSLayoutConstraint.activate([
            footer.widthAnchor.constraint(equalToConstant: contentWidth),
            usage.topAnchor.constraint(equalTo: footer.topAnchor),
            usage.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            usage.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            actions.topAnchor.constraint(equalTo: usage.bottomAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: footer.bottomAnchor),
        ])
        if let optOut {
            NSLayoutConstraint.activate([
                optOut.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
                optOut.centerYAnchor.constraint(equalTo: getPro.centerYAnchor),
                optOut.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -16),
            ])
        }
        return footer
    }

    /// Hides the purchase actions and terms, leaving the footer's leading content.
    func setPurchaseHidden(_ hidden: Bool) {
        purchase.isHidden = hidden
    }

    private func makePurchaseTerms() -> NSTextField {
        let terms = NSTextField(wrappingLabelWithString: ProFeatureCopy.purchaseTerms)
        terms.font = .systemFont(ofSize: 11)
        terms.textColor = .secondaryLabelColor
        terms.isSelectable = false
        terms.alignment = userInterfaceLayoutDirection == .rightToLeft ? .left : .right
        terms.preferredMaxLayoutWidth = contentWidth / 2
        return terms
    }

    /// The artwork's own Pro caption says "During your trial"; features the trial did not use say "With Pro".
    private func duringLabel(_ feature: ProJourneyFeature) -> String? {
        evidence.used(feature) ? nil : NSLocalizedString("With Pro", comment: "")
    }

    private func comparison(_ artwork: String, during: String? = nil) {
        let view = ProComparisonView(artwork,
            overrides: during.map { ["comparison.during": $0] } ?? [:])
        illustration.addArrangedSubview(view)
        view.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 276 / 600).isActive = true
    }
}

/// The SVG contains the complete comparison; the app owns the native Pro badge.
final class ProComparisonView: NSView {
    init(_ artwork: String, overrides: [String: String] = [:]) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let image = LocalizedIllustrationView(artwork, overrides: overrides)
        let badge = ProBadgeView()
        let proPanel = NSLayoutGuide()
        addLayoutGuide(proPanel)
        addSubview(image)
        addSubview(badge)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor),
            image.trailingAnchor.constraint(equalTo: trailingAnchor),
            image.topAnchor.constraint(equalTo: topAnchor),
            image.bottomAnchor.constraint(equalTo: bottomAnchor),
            proPanel.leftAnchor.constraint(equalTo: leftAnchor),
            proPanel.widthAnchor.constraint(equalTo: widthAnchor, multiplier:
                userInterfaceLayoutDirection == .rightToLeft ? 1 : 280 / 600),
            badge.rightAnchor.constraint(equalTo: proPanel.rightAnchor, constant: -12),
            badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Class only supports programmatic initialization") }
}

final class ProJourneyCard: NSView {
    init(content: NSView) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("Class only supports programmatic initialization") }

    override func draw(_: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Celebrates a new activation from the menu bar icon, like the onboarding's own success.
enum ProActivationPopover {
    private static var popover: AnchoredPopover?

    static func show() {
        guard popover?.isShown != true else { return }
        close()
        let popover = AnchoredPopover()
        popover.behavior = .transient
        self.popover = popover
        let tick = SuccessTickView()
        let title = NSTextField(wrappingLabelWithString: NSLocalizedString("Pro is ready", comment: ""))
        title.font = .systemFont(ofSize: 24, weight: .bold)
        let subtitle = NSTextField(wrappingLabelWithString: NSLocalizedString(
            "Unlimited access to all four Pro features",
            comment: ""
        ))
        let done = ProPromptButtons.makePrimary(NSLocalizedString("Enjoy!", comment: "Closes the celebration after a Pro license is activated")) { [weak popover] in
            popover?.close()
        }
        title.alignment = .center
        subtitle.alignment = .center
        subtitle.font = .systemFont(ofSize: 13)
        let stack = NSStackView(views: [tick, title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)
        let width: CGFloat = 384
        for label in [title, subtitle] {
            label.isSelectable = false
            label.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        let features = NSStackView()
        features.orientation = .vertical
        features.alignment = .leading
        features.spacing = 16
        features.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let entries = [
            (NSLocalizedString("Search", comment: ""), NSLocalizedString("Find a window by typing", comment: "")),
            (ProFeatureCopy.appIconsAndTitles, NSLocalizedString("Choose a style", comment: "")),
            (NSLocalizedString("Auto Size", comment: ""), NSLocalizedString("Give your previews more room", comment: "")),
            (NSLocalizedString("Shortcuts", comment: ""), NSLocalizedString("Give different groups of windows their own shortcuts.", comment: "")),
        ]
        for (index, entry) in entries.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                features.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalToConstant: width - 40).isActive = true
            }
            let check = NSImageView(image: NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)!
                .withSymbolConfiguration(.init(pointSize: 18, weight: .semibold))!)
            check.contentTintColor = .systemGreen
            check.setAccessibilityElement(false)
            check.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let name = NSTextField(wrappingLabelWithString: entry.0)
            name.font = .systemFont(ofSize: 15, weight: .semibold)
            let detail = NSTextField(wrappingLabelWithString: entry.1)
            detail.font = .systemFont(ofSize: 13)
            detail.textColor = .secondaryLabelColor
            let labels = NSStackView(views: [name, detail])
            labels.orientation = .vertical
            labels.alignment = .leading
            labels.spacing = 4
            for label in [name, detail] {
                label.isSelectable = false
                label.widthAnchor.constraint(equalToConstant: width - 76).isActive = true
            }
            let row = NSStackView(views: [check, labels])
            row.spacing = 14
            row.alignment = .centerY
            features.addArrangedSubview(row)
        }
        stack.addArrangedSubview(ProJourneyCard(content: features))
        done.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        stack.addArrangedSubview(done)
        stack.translatesAutoresizingMaskIntoConstraints = false
        popover.present(stack, from: Menubar.statusItem, onShown: { [weak tick] in
            guard let tick, let window = tick.window, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
            tick.pop()
            ConfettiBurst.fire(around: window.convertToScreen(tick.convert(tick.bounds, to: nil)), above: window)
        })
    }

    static func close() {
        popover?.close()
    }
}
