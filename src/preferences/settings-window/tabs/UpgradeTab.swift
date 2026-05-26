import Cocoa

class UpgradeTab {
    private static var statusLabel: LightLabel!
    private static var usageHero: UsageStatHeroView!
    private static var heroButton: ProHeroButton!
    private static var guaranteeLabel: NSTextField!
    private static var separator: NSBox!
    private static var activateLinkRow: NSStackView!
    private static var proManageTable: TableGroupView!
    private static var featuresList: NSStackView!
    private static var isActivating = false
    private static var isInitialized = false

    static func initTab() -> NSView {
        let view = makeView()
        isInitialized = true
        refreshStatus()
        return view
    }

    static func cleanup() {
        isInitialized = false
        isActivating = false
        statusLabel = nil
        usageHero = nil
        heroButton = nil
        guaranteeLabel = nil
        separator = nil
        activateLinkRow = nil
        proManageTable = nil
        featuresList = nil
    }

    private static func makeView() -> NSView {
        let headerStrip = makeHeaderStrip()
        usageHero = UsageStatHeroView()
        heroButton = makeHeroButton()
        guaranteeLabel = makeGuaranteeLabel()
        separator = makeSeparator()
        featuresList = makeFeaturesList()
        activateLinkRow = makeActivateLinkRow()
        proManageTable = makeProManageTable()
        let bodyStack = NSStackView()
        bodyStack.orientation = .vertical
        bodyStack.alignment = .centerX
        bodyStack.spacing = 0
        bodyStack.addArrangedSubview(headerStrip)
        bodyStack.setCustomSpacing(28, after: headerStrip)
        bodyStack.addArrangedSubview(usageHero)
        bodyStack.setCustomSpacing(40, after: usageHero)
        bodyStack.addArrangedSubview(heroButton)
        bodyStack.setCustomSpacing(6, after: heroButton)
        bodyStack.addArrangedSubview(guaranteeLabel)
        bodyStack.setCustomSpacing(28, after: guaranteeLabel)
        bodyStack.addArrangedSubview(separator)
        bodyStack.setCustomSpacing(24, after: separator)
        bodyStack.addArrangedSubview(featuresList)
        bodyStack.setCustomSpacing(28, after: featuresList)
        bodyStack.addArrangedSubview(activateLinkRow)
        bodyStack.setCustomSpacing(5, after: activateLinkRow)
        bodyStack.addArrangedSubview(proManageTable)
        headerStrip.widthAnchor.constraint(equalToConstant: SettingsWindow.contentWidth).isActive = true
        return bodyStack
    }

    private static func makeGuaranteeLabel() -> NSTextField {
        let label = NSTextField(labelWithString: NSLocalizedString("30-day money-back guarantee", comment: ""))
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        return label
    }

    private static func makeSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return box
    }

    private static func makeActivateLinkRow() -> NSStackView {
        let haveKey = makeFooterLink(NSLocalizedString("I already have a license key", comment: "")) {
            presentActivationSheet()
        }
        let lostKey = makeFooterLink(NSLocalizedString("I lost my license key", comment: "")) {
            openAccountPage()
        }
        let dot = NSTextField(labelWithString: "·")
        dot.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        dot.textColor = .secondaryLabelColor
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .firstBaseline
        stack.spacing = 6
        stack.addArrangedSubview(haveKey)
        stack.addArrangedSubview(dot)
        stack.addArrangedSubview(lostKey)
        return stack
    }

    private static func makeFooterLink(_ title: String, onClick: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        if #available(macOS 10.14, *) {
            button.contentTintColor = .controlAccentColor
        }
        button.onAction = { _ in onClick() }
        return button
    }

    private static func makeHeaderStrip() -> NSStackView {
        let titleFont = NSFont.systemFont(ofSize: 15, weight: .medium)
        let titleText = NSLocalizedString("AltTab Pro", comment: "")
        let titleAttr = NSMutableAttributedString(string: titleText, attributes: [
            .font: titleFont,
            .foregroundColor: NSColor.labelColor,
        ])
        if let range = titleText.range(of: "Pro", options: .backwards) {
            titleAttr.replaceCharacters(in: NSRange(range, in: titleText),
                with: ProGradient.makeProTextAttachment(font: titleFont))
        }
        let titleLabel = NSTextField(labelWithAttributedString: titleAttr)
        // Match the section-title NSTextField cell drawing path. Without these, the
        // attributed-string + `ProGradient` text-attachment label takes a different
        // `NSTextFieldCell` path and renders its glyphs ~1pt lower than a plain section title.
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 0
        titleLabel.cell?.usesSingleLineMode = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        // `usesSingleLineMode = true` overshoots the multi-line baseline by ~0.5pt, leaving the
        // title 1 retina pixel above where the plain section title sits. NSStackView's `edgeInsets`
        // rounds fractional values, so we use a wrapper with an explicit AutoLayout constraint —
        // the AutoLayout engine honours fractional CGFloat constants and produces a half-pixel
        // shift on retina. `bottomAnchor + (-0.5)` keeps the wrapper's height equal to the
        // label's intrinsic height so the subtitle below it isn't pushed off.
        let titleWrapper = NSView()
        titleWrapper.translatesAutoresizingMaskIntoConstraints = false
        titleWrapper.addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: titleWrapper.topAnchor, constant: 0.5),
            titleLabel.leadingAnchor.constraint(equalTo: titleWrapper.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleWrapper.trailingAnchor),
            titleWrapper.bottomAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: -0.5),
        ])
        statusLabel = TableGroupView.makeText("")
        statusLabel.lineBreakMode = .byTruncatingTail
        let strip = NSStackView()
        strip.orientation = .vertical
        strip.spacing = SettingsWindow.sectionTitleSpacing
        strip.alignment = .leading
        strip.edgeInsets = NSEdgeInsets(top: 0, left: TableGroupView.padding, bottom: 0, right: TableGroupView.padding)
        strip.addArrangedSubview(titleWrapper)
        strip.addArrangedSubview(statusLabel)
        return strip
    }

    private static func makeHeroButton() -> ProHeroButton {
        let button = ProHeroButton()
        button.onAction = { _ in ProTransitionManager.openCheckout() }
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return button
    }

    private static func makeProManageTable() -> TableGroupView {
        let table = TableGroupView(width: SettingsWindow.contentWidth)
        let manageButton = NSButton(title: NSLocalizedString("My Account", comment: ""), target: nil, action: nil)
        manageButton.onAction = { _ in openAccountPage() }
        table.addRow(leftText: NSLocalizedString("Manage activations, view receipts, etc", comment: ""), rightViews: [manageButton], isAddSeparator: false)
        let deactivateButton = NSButton(title: NSLocalizedString("Deactivate license", comment: ""), target: nil, action: nil)
        deactivateButton.onAction = { _ in deactivateLicense() }
        let deactivateHint = TableGroupView.makeText(NSLocalizedString("License will remain valid and usable to activate AltTab on any machine", comment: ""))
        deactivateHint.textColor = .secondaryLabelColor
        table.addRow(leftViews: [TableGroupView.makeText(NSLocalizedString("Deactivate license on this machine", comment: ""))], rightViews: [deactivateButton], secondaryViews: [deactivateHint])
        return table
    }

    private static func makeFeaturesList() -> NSStackView {
        let features = [
            NSLocalizedString("App Icons & Window Titles styles", comment: ""),
            NSLocalizedString("Search windows by typing", comment: ""),
            NSLocalizedString("Auto-sizing switcher", comment: ""),
            NSLocalizedString("Up to 9 keyboard shortcuts", comment: ""),
        ]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        let header = NSTextField(labelWithString: NSLocalizedString("Pro includes:", comment: ""))
        header.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(8, after: header)
        for feature in features {
            let check = NSTextField(labelWithString: "✓")
            check.textColor = .systemGreen
            check.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            let text = NSTextField(labelWithString: feature)
            text.font = NSFont.systemFont(ofSize: 13)
            text.textColor = .labelColor
            let row = NSStackView(views: [check, text])
            row.orientation = .horizontal
            row.spacing = 8
            row.alignment = .firstBaseline
            stack.addArrangedSubview(row)
        }
        return stack
    }

    static func refreshStatus() {
        SettingsWindow.shared?.refreshUpgradeButton()
        guard isInitialized else { return }
        // `usageHero` is built once in `makeView()` and reused across the app's lifetime.
        // Re-read `UsageStats` so the displayed trigger / Pro-use numbers track usage
        // growth instead of staying frozen at first-render.
        usageHero.refresh()
        let state = LicenseManager.shared.state
        switch state {
        case .pro:
            setHeroVisible(false)
            featuresList.isHidden = true
            activateLinkRow.isHidden = true
            proManageTable.isHidden = false
            let email = LicenseManager.shared.customerEmail ?? ""
            let format = LicenseManager.shared.isLifetimeVariant
                ? NSLocalizedString("Pro Lifetime license activated for %@", comment: "")
                : NSLocalizedString("Pro license activated for %@", comment: "")
            let fullText = String(format: format, email)
            let attributed = makeStatusSubtitle(fullText)
            if !email.isEmpty, let emailRange = fullText.range(of: email) {
                attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .semibold), range: NSRange(emailRange, in: fullText))
            }
            statusLabel.attributedStringValue = attributed
        case .trial(let daysRemaining):
            setHeroVisible(true)
            featuresList.isHidden = false
            activateLinkRow.isHidden = false
            proManageTable.isHidden = true
            statusLabel.attributedStringValue = makeStatusSubtitle(String(format: NSLocalizedString("Trial: %d days remaining", comment: ""), daysRemaining))
        case .proExpired:
            setHeroVisible(true)
            featuresList.isHidden = false
            activateLinkRow.isHidden = false
            proManageTable.isHidden = true
            statusLabel.attributedStringValue = makeStatusSubtitle(NSLocalizedString("Your license doesn't cover this version. Upgrade to Lifetime Pro.", comment: ""))
        case .trialExpired:
            setHeroVisible(true)
            featuresList.isHidden = false
            activateLinkRow.isHidden = false
            proManageTable.isHidden = true
            statusLabel.attributedStringValue = makeStatusSubtitle(NSLocalizedString("Trial expired", comment: ""))
        }
    }

    private static func setHeroVisible(_ visible: Bool) {
        usageHero.isHidden = !visible
        heroButton.isHidden = !visible
        guaranteeLabel.isHidden = !visible
        separator.isHidden = !visible
    }

    private static func makeStatusSubtitle(_ text: String) -> NSMutableAttributedString {
        NSMutableAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 12),
        ])
    }

    static func openAccountPage() {
        NSWorkspace.shared.open(URL(string: Endpoints.accountUrl)!)
    }

    private static func presentActivationSheet(prefilledKey: String = "", autoFailedHint: Bool = false) {
        let alert = NSAlert()
        alert.alertStyle = autoFailedHint ? .warning : .informational
        alert.messageText = autoFailedHint
            ? NSLocalizedString("Automatic activation failed", comment: "")
            : NSLocalizedString("Activate your Pro license", comment: "")
        alert.informativeText = NSLocalizedString("Paste your license key:", comment: "")
        let field = makeKeyField(prefilled: prefilledKey)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let activateButton = alert.addButton(withTitle: NSLocalizedString("Activate", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        let gate = ActivateButtonGate()
        gate.button = activateButton
        field.delegate = gate
        activateButton.isEnabled = !prefilledKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let response = alert.runModal()
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if response == .alertFirstButtonReturn {
            activateLicense(key)
        }
    }

    private static func makeKeyField(prefilled: String) -> NSTextField {
        let placeholder = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        let font: NSFont
        if #available(macOS 10.15, *) {
            font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        } else {
            font = NSFont(name: "Menlo", size: 14) ?? NSFont.systemFont(ofSize: 14)
        }
        let textSize = (placeholder as NSString).size(withAttributes: [.font: font])
        let width = ceil(textSize.width) + 14
        let height = ceil(font.boundingRectForFont.height) + 10
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: height))
        field.placeholderString = placeholder
        field.font = font
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.cell?.lineBreakMode = .byClipping
        field.maximumNumberOfLines = 1
        field.stringValue = prefilled
        return field
    }

    private static func activateLicense(_ key: String) {
        guard !key.isEmpty, !isActivating else { return }
        isActivating = true
        LicenseManager.shared.activate(key) { result in
            isActivating = false
            switch result {
            case .success:
                refreshStatus()
                App.resetPreferencesDependentComponents()
            case .failure(let error):
                if case let LicenseAPIError.seatLimitExceeded(instances) = error, !instances.isEmpty {
                    presentSeatLimitSheet(key: key, instances: instances)
                    return
                }
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = NSLocalizedString("Activation failed", comment: "")
                alert.informativeText = error.localizedDescription
                addDebugInfoToAlert(alert, error)
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("My Account", comment: ""))
                if alert.runModal() == .alertSecondButtonReturn {
                    openAccountPage()
                }
            }
        }
    }

    private static func presentSeatLimitSheet(key licenseKey: String, instances: [ActiveInstance]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = NSLocalizedString("This license is already activated elsewhere", comment: "")
        alert.informativeText = NSLocalizedString("Pick a machine to deactivate so you can activate here.", comment: "")

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        var buttons: [NSButton] = []
        for (i, instance) in instances.enumerated() {
            let name = instance.machineName ?? String(format: NSLocalizedString("Machine %@", comment: ""), String(instance.id.prefix(8)))
            let lastSeen = formatter.string(from: instance.lastSeenAt)
            let title = String(format: NSLocalizedString("%@ — last seen %@", comment: ""), name, lastSeen)
            let button = NSButton(radioButtonWithTitle: title, target: nil, action: nil)
            button.tag = i
            if i == 0 { button.state = .on }
            buttons.append(button)
            stack.addArrangedSubview(button)
        }
        stack.frame = NSRect(x: 0, y: 0, width: 380, height: CGFloat(instances.count) * 22)
        alert.accessoryView = stack

        alert.addButton(withTitle: NSLocalizedString("Deactivate and activate here", comment: ""))
        let cancelButton = alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        cancelButton.keyEquivalent = "\u{1b}" // Escape

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn,
              let selected = buttons.first(where: { $0.state == .on }),
              selected.tag < instances.count else {
            return
        }
        let instance = instances[selected.tag]
        LicenseManager.shared.deactivateInstance(licenseKey: licenseKey, instanceId: instance.id) { result in
            switch result {
            case .success:
                activateLicense(licenseKey)
            case .failure(let error):
                let errAlert = NSAlert()
                errAlert.alertStyle = .warning
                errAlert.messageText = NSLocalizedString("Couldn't deactivate that machine", comment: "")
                errAlert.informativeText = error.localizedDescription
                addDebugInfoToAlert(errAlert, error)
                errAlert.runModal()
            }
        }
    }

    private static func deactivateLicense() {
        LicenseManager.shared.deactivate { result in
            switch result {
            case .success:
                refreshStatus()
                App.resetPreferencesDependentComponents()
            case .failure(let error):
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = NSLocalizedString("Deactivation failed", comment: "")
                alert.informativeText = error.localizedDescription
                addDebugInfoToAlert(alert, error)
                alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("My Account", comment: ""))
                if alert.runModal() == .alertSecondButtonReturn {
                    openAccountPage()
                }
            }
        }
    }

    private static func addDebugInfoToAlert(_ alert: NSAlert, _ error: Error) {
        let debugInfo: String?
        if let licenseError = error as? LicenseAPIError {
            debugInfo = licenseError.debugInfo
        } else {
            debugInfo = nil
        }
        guard let debugInfo else { return }
        let disclosure = NSButton(title: NSLocalizedString("Show details (for support)", comment: ""), target: nil, action: nil)
        disclosure.bezelStyle = .disclosure
        disclosure.setButtonType(.pushOnPushOff)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 350, height: 0))
        textView.isEditable = false
        textView.isSelectable = true
        if #available(macOS 10.15, *) {
            textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        } else {
            textView.font = NSFont(name: "Menlo", size: 10) ?? NSFont.systemFont(ofSize: 10)
        }
        textView.string = debugInfo
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.sizeToFit()
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 370, height: min(textView.frame.height + 4, 120)))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.isHidden = true
        let container = NSStackView(views: [disclosure, scrollView])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 6
        disclosure.onAction = { _ in
            scrollView.isHidden = disclosure.state == .off
            alert.layout()
            alert.window.center()
        }
        alert.accessoryView = container
    }

    static func navigateToUpgradeTab() {
        App.showSettingsWindow()
        SettingsWindow.shared?.showUpgradeView()
    }

    static func showAutoActivating(_ licenseKey: String) {
        navigateToUpgradeTab()
    }

    static func showAutoActivationSuccess() {
        refreshStatus()
    }

    static func showAutoActivationFailed(_ licenseKey: String) {
        navigateToUpgradeTab()
        presentActivationSheet(prefilledKey: licenseKey, autoFailedHint: true)
    }
}

private final class ActivateButtonGate: NSObject, NSTextFieldDelegate {
    weak var button: NSButton?

    func controlTextDidChange(_ note: Notification) {
        guard let field = note.object as? NSTextField else { return }
        button?.isEnabled = !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

final class ProHeroButton: ProGradientButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let blue = NSColor(red: 0x44 / 255.0, green: 0x88 / 255.0, blue: 0xFF / 255.0, alpha: 1).cgColor
        gradientLayer.colors = [blue, blue, blue]
        layer?.shadowOpacity = 0
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
        ]
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let title = NSMutableAttributedString(string: NSLocalizedString("Get Pro", comment: ""), attributes: attrs)
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        attributedTitle = title
        if #available(macOS 10.14, *) {
            contentTintColor = .white
        }
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }
}
