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

    /// Features the trial did not use say "With Pro" rather than claiming use that did not happen.
    private func proTitle(_ feature: ProJourneyFeature) -> String {
        evidence.used(feature)
            ? NSLocalizedString("During your trial", comment: "")
            : NSLocalizedString("With Pro", comment: "")
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
            comparison(
                column(proTitle(.search),
                    image: ProJourneyArtwork(feature: "search-pro", height: 244, pro: true)),
                column(NSLocalizedString("Without Pro", comment: ""),
                    image: ProJourneyArtwork(feature: "search-free", height: 244)))
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
            comparison(styleColumn(style, title: proTitle(.styles)),
                styleColumn(.thumbnails, title: NSLocalizedString("Without Pro", comment: "")))
        case .shortcuts:
            heading.stringValue = NSLocalizedString("Choose which windows to switch between", comment: "")
            comparison(
                column(proTitle(.shortcuts),
                    image: ProJourneyArtwork(feature: "shortcuts-pro", height: 244, pro: true)),
                column(NSLocalizedString("Without Pro", comment: ""),
                    image: ProJourneyArtwork(feature: "shortcuts-free", height: 244)))
            if evidence.used(.shortcuts), let count = evidence.extraShortcuts {
                usage.stringValue = String(
                    format: NSLocalizedString("Extra shortcut uses during your trial: %@", comment: ""),
                    UsageStats.formatCount(count)
                )
            }
        case .autoSize:
            heading.stringValue = NSLocalizedString("Give your previews more room", comment: "")
            comparison(autoColumn(fixed: false, title: proTitle(.autoSize)),
                autoColumn(fixed: true, title: NSLocalizedString("Without Pro", comment: "")))
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

    private func styleColumn(_ style: AppearanceStylePreference, title: String) -> NSStackView {
        let feature: String
        switch style {
        case .thumbnails: feature = "thumbnails-pair"
        case .appIcons: feature = "app-icons-comparison"
        case .titles: feature = "titles-compact"
        }
        let image = ProJourneyArtwork(feature: feature, height: 244, pro: style != .thumbnails, caption: style.localizedString)
        image.setAccessibilityLabel(style.localizedString)
        return column(title, image: image)
    }

    /// The same artwork at two scales, so both sides show the same two windows.
    private func autoColumn(fixed: Bool, title: String) -> NSStackView {
        column(title, image: ProJourneyArtwork(feature: "thumbnails-pair", height: 244, scale: fixed ? 0.56 : 1, pro: !fixed,
            caption: NSLocalizedString(fixed ? "Fixed size" : "Auto Size", comment: "")))
    }

    private func comparison(_ before: NSStackView, _ after: NSStackView) {
        let arrow = NSImageView(image: NSImage(systemSymbolName:
            userInterfaceLayoutDirection == .rightToLeft ? "arrow.left" : "arrow.right",
            accessibilityDescription: nil)!)
        arrow.contentTintColor = .secondaryLabelColor
        arrow.setAccessibilityElement(false)
        let slot = NSView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(arrow)
        arrow.translatesAutoresizingMaskIntoConstraints = false
        for view in [before, slot, after] { illustration.addArrangedSubview(view) }
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: 24),
            slot.heightAnchor.constraint(equalTo: before.heightAnchor),
            arrow.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            arrow.centerYAnchor.constraint(equalTo: before.arrangedSubviews.last!.centerYAnchor),
        ])
    }

    private func column(_ title: String, image: NSView) -> NSStackView {
        let label = NSTextField(wrappingLabelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.alignment = .center
        let stack = NSStackView(views: [label, image])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        for item in [label, image] {
            item.translatesAutoresizingMaskIntoConstraints = false
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        label.preferredMaxLayoutWidth = (contentWidth - 40) / 2
        stack.widthAnchor.constraint(equalToConstant: (contentWidth - 40) / 2).isActive = true
        return stack
    }
}

/// Website scenes share one stationary desktop; only the switcher scales in comparisons.
final class ProJourneyArtwork: NSView {
    private let image: NSImage?
    private let desktop = ProJourneyArtwork.loadSupplement("desktop")
    private let feature: String
    private let scale: CGFloat
    private let caption: String?
    private var proBadge: ProBadgeView?

    init(feature: String, height: CGFloat, scale: CGFloat = 1, pro: Bool = false, caption: String? = nil) {
        self.feature = feature
        self.scale = scale
        self.caption = caption
        let source = ["search-pro": "search-match", "search-free": "thumbnails-pair",
            "shortcuts-pro": "shortcuts-all", "shortcuts-free": "shortcuts-all"][feature] ?? feature
        let path = Bundle.main.url(forResource: "\(source).en", withExtension: "svg", subdirectory: "pro-illustrations")
        image = Self.loadSupplement(source) ?? path.flatMap { NSImage(contentsOf: $0) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        if pro {
            let badge = ProBadgeView()
            addSubview(badge)
            proBadge = badge
            NSLayoutConstraint.activate([
                badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                badge.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            ])
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        let description: String
        switch feature {
        case "search", "search-pro": description = NSLocalizedString("Typing a title narrows the window list", comment: "")
        case "search-free": description = NSLocalizedString("Two windows without a search field", comment: "")
        case "shortcuts-pro": description = NSLocalizedString("Separate shortcuts for all windows and active app windows", comment: "")
        case "shortcuts-free": description = NSLocalizedString("One shortcut for all windows", comment: "")
        case "shortcuts-all": description = NSLocalizedString("Two Safari windows and one Notes window", comment: "")
        case "shortcuts-safari": description = NSLocalizedString("Only the same two Safari windows", comment: "")
        default: description = NSLocalizedString("The same two windows shown at different preview sizes", comment: "")
        }
        setAccessibilityLabel([description, caption].compactMap { $0 }.joined(separator: ": "))
    }

    private static func loadSupplement(_ feature: String) -> NSImage? {
        guard ["desktop", "shortcuts-all", "shortcuts-safari", "search-results", "search-all", "titles-compact", "app-icons-comparison", "thumbnails-pair", "search-match"].contains(feature),
            let url = Bundle.main.url(forResource: "\(feature).en", withExtension: "pdf",
                subdirectory: "pro-illustrations") else { return nil }
        return NSImage(contentsOf: url)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError("Class only supports programmatic initialization") }

    override func draw(_: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(roundedRect: bounds, xRadius: 16, yRadius: 16).addClip()
        NSColor(srgbRed: 0.11, green: 0.15, blue: 0.31, alpha: 1).setFill()
        bounds.fill()
        if let desktop {
            let factor = max(bounds.width / desktop.size.width, bounds.height / desktop.size.height)
            let size = NSSize(width: desktop.size.width * factor, height: desktop.size.height * factor)
            desktop.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                width: size.width, height: size.height))
        }
        proBadge?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        if feature.hasPrefix("search-") { drawSearch(); return }
        if feature == "shortcuts-pro" || feature == "shortcuts-free" { drawShortcuts(); return }
        if let caption {
            drawLabel(caption, in: NSRect(x: 16, y: 32, width: bounds.width - 32, height: 22), size: 14)
        }
        guard let image else { return }
        let inset = NSRect(x: 16, y: caption == nil ? 16 : 60, width: bounds.width - 32,
            height: bounds.height - (caption == nil ? 32 : 120))
        let referenceWidth = feature.hasPrefix("shortcuts-") ? 1128 : image.size.width
        let factor = min(inset.width / referenceWidth, inset.height / image.size.height) * scale
        let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
        image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
            width: size.width, height: size.height))
    }

    private func drawSearch() {
        let content = bounds.insetBy(dx: 16, dy: 16)
        let field = NSRect(x: content.minX, y: bounds.height - 64, width: content.width, height: 30)
        if feature == "search-pro" {
            NSColor.white.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: field, xRadius: 8, yRadius: 8).fill()
            let query = NSAttributedString(string: "Japan",
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
            let start = field.midX - query.size().width / 2
            NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.white]))?.draw(
                in: NSRect(x: start - 20, y: field.midY - 7, width: 14, height: 14))
            query.draw(at: NSPoint(x: start, y: field.midY - query.size().height / 2))
        }
        if let image {
            let factor = min(content.width / image.size.width, (field.minY - 72) / image.size.height)
            let size = NSSize(width: image.size.width * factor, height: image.size.height * factor)
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: field.minY - 12 - size.height,
                width: size.width, height: size.height))
        }
        drawLabel(feature == "search-pro" ? NSLocalizedString("1 matching window", comment: "")
            : NSLocalizedString("2 windows to browse", comment: ""),
            in: NSRect(x: content.minX, y: 35, width: content.width, height: 18), size: 11)
    }

    private func drawShortcuts() {
        let labels = [NSLocalizedString("All Windows", comment: ""), NSLocalizedString("Active App Only", comment: ""),
            String(format: NSLocalizedString("Up to %d shortcuts", comment: ""), Preferences.maxShortcutCount)]
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let keycaps = ["⌥⇥", "⌥`"].map { SearchDiscoveryPanel.keycap($0, dark: false, highContrast: false) }
        let keyWidth = keycaps.map { $0.size.width }.max()!
        let labelWidth = labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max()!
        let width = min(bounds.width - 32, keyWidth + 10 + ceil(labelWidth))
        let start = bounds.midX - width / 2
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        for index in 0 ..< (feature == "shortcuts-pro" ? 3 : 1) {
            let center = bounds.height - 78 - CGFloat(index) * 56
            if index < keycaps.count {
                let keys = keycaps[index]
                keys.draw(in: NSRect(x: start + (keyWidth - keys.size.width) / 2, y: center - 12,
                    width: keys.size.width, height: 24))
            }
            let text = NSAttributedString(string: labels[index],
                attributes: [.font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
            let availableWidth = max(1, width - keyWidth - 10)
            let height = ceil(text.boundingRect(with: NSSize(width: availableWidth, height: 1000),
                options: .usesLineFragmentOrigin).height)
            text.draw(in: NSRect(x: start + keyWidth + 10, y: center - height / 2, width: availableWidth, height: height))
        }
    }

    private func drawLabel(_ text: String, in rect: NSRect, size: CGFloat = 13) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
    }

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
