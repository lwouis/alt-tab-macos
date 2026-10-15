import Cocoa

class UpgradeTab {
    private static var introduction: MascotMessageView!
    private static var journey: ProJourneyView!
    private static var footer: NSView!
    private static var proManageTable: TableGroupView!
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
        introduction = nil
        journey = nil
        footer = nil
        proManageTable = nil
    }

    private static func makeView() -> NSView {
        let header = makeHeaderStrip()
        journey = ProJourneyView(width: SettingsWindow.contentWidth - 2 * TableGroupView.padding)
        journey.spacing = 8
        let purchase = ProPromptButtons.makeGetPro {
            ProTransitionManager.openCheckout(from: .settingsUpgradeTab)
        }
        footer = journey.makeFooter(actions: purchase, leading: makeActivateLinkRow())
        proManageTable = makeProManageTable()
        let stack = NSStackView(views: [header, journey, footer, proManageTable])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(20, after: journey)
        return stack
    }

    private static func makeActivateLinkRow() -> NSStackView {
        let haveKey = makeFooterLink(NSLocalizedString("Enter license key", comment: "")) {
            presentActivationSheet()
        }
        let lostKey = makeFooterLink(NSLocalizedString("Lost your license key?", comment: "")) {
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
        button.contentTintColor = .controlAccentColor
        button.onAction = { _ in onClick() }
        return button
    }

    private static func makeHeaderStrip() -> MascotMessageView {
        introduction = ProJourneyView.makeIntroduction(width: SettingsWindow.contentWidth - 2 * TableGroupView.padding)
        return introduction
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

    static func refreshStatus() {
        SettingsWindow.shared?.refreshUpgradeButton()
        guard isInitialized else { return }
        journey.refresh()
        ProJourneyView.refreshIntroduction(introduction)
        switch LicenseManager.shared.state {
        case .pro:
            showSections(journey: false, licenseLinks: false)
        case .trialNotStarted:
            showSections(journey: false, licenseLinks: true)
        case .trial, .proExpired, .trialExpired:
            showSections(journey: true, licenseLinks: true)
        }
    }

    /// Before the trial, the footer keeps only its license links.
    private static func showSections(journey showsJourney: Bool, licenseLinks: Bool) {
        journey.isHidden = !showsJourney
        journey.setPurchaseHidden(!showsJourney)
        footer.isHidden = !showsJourney && !licenseLinks
        proManageTable.isHidden = licenseLinks
    }

    static func openAccountPage() {
        NSWorkspace.shared.open(URL(string: Endpoints.accountUrl)!)
    }

    static func presentActivationSheet(prefilledKey: String = "", autoFailedHint: Bool = false) {
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
        alert.present(attachedTo: SettingsWindow.shared) { response in
            // The field holds its delegate weakly; this keeps the gate alive while the sheet is up.
            withExtendedLifetime(gate) {}
            guard response == .alertFirstButtonReturn else { return }
            activateLicense(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func makeKeyField(prefilled: String) -> NSTextField {
        let placeholder = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        let font: NSFont
        font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
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
            case let .failure(error):
                if case let LicenseAPIError.seatLimitExceeded(instances) = error, !instances.isEmpty {
                    presentSeatLimitSheet(key: key, instances: instances)
                    return
                }
                presentLicenseError(NSLocalizedString("Activation failed", comment: ""), error)
            }
        }
    }

    static func presentSeatLimitSheet(key licenseKey: String, instances: [ActiveInstance]) {
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

        alert.present(attachedTo: SettingsWindow.shared) { response in
            guard response == .alertFirstButtonReturn,
                  let selected = buttons.first(where: { $0.state == .on }),
                  selected.tag < instances.count else { return }
            deactivate(instances[selected.tag], thenActivate: licenseKey)
        }
    }

    private static func deactivate(_ instance: ActiveInstance, thenActivate licenseKey: String) {
        LicenseManager.shared.deactivateInstance(licenseKey: licenseKey, instanceId: instance.id) { result in
            switch result {
            case .success:
                activateLicense(licenseKey)
            case let .failure(error):
                let errAlert = NSAlert()
                errAlert.alertStyle = .warning
                errAlert.messageText = NSLocalizedString("Couldn't deactivate that machine", comment: "")
                errAlert.informativeText = error.localizedDescription
                addDebugInfoToAlert(errAlert, error)
                errAlert.present(attachedTo: SettingsWindow.shared) { _ in }
            }
        }
    }

    private static func deactivateLicense() {
        LicenseManager.shared.deactivate { result in
            switch result {
            case .success:
                refreshStatus()
                App.resetPreferencesDependentComponents()
            case let .failure(error):
                presentLicenseError(NSLocalizedString("Deactivation failed", comment: ""), error)
            }
        }
    }

    static func presentLicenseError(_ title: String, _ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        addDebugInfoToAlert(alert, error)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("My Account", comment: ""))
        alert.present(attachedTo: SettingsWindow.shared) {
            if $0 == .alertSecondButtonReturn { openAccountPage() }
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
        textView.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
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

    static func navigateToUpgradeTab(for feature: ProJourneyFeature? = nil) {
        if let feature {
            ProTransitionManager.shared.state.recordIntent(feature)
            ProTransitionManager.shared.state.recordMessage()
        }
        App.showSettingsWindow()
        SettingsWindow.shared?.showUpgradeView()
        if let feature {
            journey?.select(feature)
        }
    }

    #if DEBUG
    /// Rebuilt, so the tab follows the history again instead of an earlier explicit selection.
    static func showForQa(_ feature: ProJourneyFeature?) {
        SettingsWindow.qaDiscard()
        App.showSettingsWindow()
        SettingsWindow.shared?.showUpgradeView()
        refreshStatus()
        if let feature { journey?.select(feature) }
    }
    #endif

    static func showAutoActivating() {
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
