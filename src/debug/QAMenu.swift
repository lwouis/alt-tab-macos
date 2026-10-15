#if DEBUG
import Cocoa

final class QAMenu: NSPanel {
    static var shared: QAMenu?
    private let stack = NSStackView()
    private let proSectionContent = NSStackView()
    private var proDisclosure: NSButton!
    private let status = NSTextField(wrappingLabelWithString: "")
    private var observers = [NSObjectProtocol]()

    private static let autosaveName = "QAMenu"
    private static let openSettingsOnLaunchKey = "debug.openSettingsOnLaunch"
    private static let proSectionExpandedKey = "debug.proSectionExpanded"
    private static let graphEnabledKey = "debug.graphEnabled"
    private static let sectionSpacing: CGFloat = 16

    static var openSettingsOnLaunch: Bool {
        UserDefaults.standard.bool(forKey: openSettingsOnLaunchKey)
    }

    /// Not shown in a lifecycle session, nor with `--qa-no-menu`: automated runs drive the real desktop with
    /// synthetic clicks, and this panel floats over every app on every Space, where the clicks can land on it
    /// instead.
    static var suppressed: Bool { QaLifecycle.enabled || CommandLine.arguments.contains("--qa-no-menu") }

    static var graphEnabled: Bool {
        UserDefaults.standard.bool(forKey: graphEnabledKey)
    }

    static func toggleVisibility() {
        guard let panel = shared else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 220, height: 0),
                   styleMask: [.titled, .closable, .miniaturizable, .utilityWindow], backing: .buffered, defer: false)
        level = .floating
        title = "QA Menu"
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        addBaseButtons()
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        contentView = container
        sizeToFitContent()
        // setFrameAutosaveNameSafely drops a corrupt persisted frame (which would abort the app) and
        // applies a valid one; it returns whether a valid saved frame existed, so center otherwise.
        if !setFrameAutosaveNameSafely(Self.autosaveName) {
            center()
        }
    }

    private func addBaseButtons() {
        let langDropdown = NSPopUpButton()
        langDropdown.addItems(withTitles: LanguagePreference.allCases.map { $0.localizedString })
        langDropdown.selectItem(at: CachedUserDefaults.intFromMacroPref("language", LanguagePreference.allCases))
        langDropdown.onAction = { sender in
            let index = (sender as! NSPopUpButton).indexOfSelectedItem
            UserDefaults.standard.set(String(index), forKey: "language")
            CachedUserDefaults.removeFromCache("language")
            Preferences.language.applyToAppleLanguages()
            App.restart()
        }
        let settingsButton = NSButton(title: "Settings…", target: nil, action: nil)
        settingsButton.onAction = { _ in App.showSettingsWindow() }
        let openOnLaunchCheckbox = NSButton(checkboxWithTitle: "Open on launch", target: nil, action: nil)
        openOnLaunchCheckbox.state = Self.openSettingsOnLaunch ? .on : .off
        openOnLaunchCheckbox.onAction = { sender in
            UserDefaults.standard.set((sender as! NSButton).state == .on, forKey: Self.openSettingsOnLaunchKey)
        }
        let graphCheckbox = NSButton(checkboxWithTitle: "Live queue graph", target: nil, action: nil)
        graphCheckbox.state = Self.graphEnabled ? .on : .off
        graphCheckbox.onAction = { sender in
            let on = (sender as! NSButton).state == .on
            UserDefaults.standard.set(on, forKey: Self.graphEnabledKey)
            DebugMenu.setEnabled(on)
        }
        let quitButton = NSButton(title: "Quit", target: nil, action: nil)
        quitButton.onAction = { _ in App.shared.terminate(nil) }
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 8
        topRow.addView(settingsButton, in: .leading)
        topRow.addView(openOnLaunchCheckbox, in: .leading)
        topRow.addView(quitButton, in: .trailing)
        stack.addArrangedSubview(topRow)
        topRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -stack.edgeInsets.right).isActive = true
        stack.addArrangedSubview(row([langDropdown, graphCheckbox]))
        addTrialSection()
    }

    /// Wipe every UserDefaults suite the app uses plus every keychain entry under the license service,
    /// so the next launch behaves exactly like a brand-new install.
    private static func mockFreshInstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Wipe AltTab's settings, trial, usage history and license?"
        alert.informativeText = "Removes everything stored for \(App.bundleIdentifier) on this Mac, including a real license key, which would then need activating again. Relaunch afterwards to start as a new install."
        alert.addButton(withTitle: "Wipe")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.removePersistentDomain(forName: App.bundleIdentifier)
        UserDefaults.standard.removePersistentDomain(forName: LicenseManager.defaultsSuiteName)
        UserDefaults.standard.removePersistentDomain(forName: "\(App.bundleIdentifier).usage")
        SystemKeychain(service: LicenseManager.keychainService).removeAll()
    }

    // MARK: - Trial journey

    private func addTrialSection() {
        let isExpanded = UserDefaults.standard.object(forKey: Self.proSectionExpandedKey) as? Bool ?? false
        proDisclosure = NSButton(title: "", target: nil, action: nil)
        proDisclosure.bezelStyle = .disclosure
        proDisclosure.setButtonType(.pushOnPushOff)
        proDisclosure.state = isExpanded ? .on : .off
        proDisclosure.onAction = { [weak self] _ in
            guard let self else { return }
            let expanded = proDisclosure.state == .on
            UserDefaults.standard.set(expanded, forKey: Self.proSectionExpandedKey)
            proSectionContent.isHidden = !expanded
            refreshStatus()
            sizeToFitContent()
        }
        if let prior = stack.arrangedSubviews.last {
            stack.setCustomSpacing(Self.sectionSpacing, after: prior)
        }
        let header = row([proDisclosure, sectionLabel("Trial journey")])
        stack.addArrangedSubview(header)
        proSectionContent.orientation = .vertical
        proSectionContent.alignment = .leading
        proSectionContent.spacing = 6
        proSectionContent.isHidden = !isExpanded
        stack.addArrangedSubview(proSectionContent)
        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabelColor
        status.preferredMaxLayoutWidth = 340
        status.isSelectable = true
        proSectionContent.addArrangedSubview(status)
        proSectionContent.addArrangedSubview(row([scenarioMenu(), surfaceMenu(), toolsMenu()]))
        proSectionContent.addArrangedSubview(row(clockControls()))
        proSectionContent.addArrangedSubview(sectionLabel("History, for the trial-ended window and Settings:"))
        proSectionContent.addArrangedSubview(row(historyControls()))
        proSectionContent.addArrangedSubview(row([
            attemptedPopup(),
            makeButton("Trial ended") { QaTrial.showTrialEnded() },
            makeButton("Day 35") { QaTrial.showDay35() },
            makeButton("Settings") { QaTrial.showSettings() },
        ]))
        observeJourney()
        refreshStatus()
    }

    private func scenarioMenu() -> NSPopUpButton {
        pullDown("Play scenario", QaTrial.scenarioSections.map { section in
            (section.0, section.1.map { scenario in (scenario.title, { QaTrial.play(scenario) }) })
        })
    }

    private func surfaceMenu() -> NSPopUpButton {
        pullDown("Show", QaTrial.surfaceSections)
    }

    private func toolsMenu() -> NSPopUpButton {
        pullDown("More", [(nil, [
            ("Reset trial state and clock", { QaTrial.reset() }),
            ("Toggle reminder opt-out", { ProTransitionManager.shared.userOptedOut.toggle() }),
            ("Revalidate license", { LicenseManager.shared.revalidateWithServer() }),
            ("Mock fresh install…", { Self.mockFreshInstall() }),
        ])])
    }

    private func clockControls() -> [NSView] {
        let day = popup(QaTrial.days.map { "Day \($0)" }, selected: QaTrial.days.firstIndex(of: 15)!)
        let time = popup(QaTrial.times.map { String(format: "%02d:%02d", $0.0, $0.1) }, selected: 1)
        let go = makeButton("Go") {
            QaTrial.start(day: QaTrial.days[day.indexOfSelectedItem], at: QaTrial.times[time.indexOfSelectedItem])
            QaTrial.nextStep = ""
        }
        go.toolTip = "Start that day at that time, with earlier prompts already seen"
        let next = makeButton("Next day") { QaTrial.nextDay() }
        next.toolTip = "Same user, one day later: flags are kept and due timers fire"
        return [day, time, go, next]
    }

    private func historyControls() -> [NSView] {
        let counts: [Int?] = [nil, 0, 37]
        let label: (Int?) -> String = { $0.map(String.init) ?? "unknown" }
        let searches = popup(counts.map { "Search: " + label($0) }, selected: 2) { QaTrial.history.searches = counts[$0] }
        let styles = AppearanceStylePreference.allCases
        let style = popup(["Style: none", "Style: App Icons", "Style: Titles"], selected: 1) { QaTrial.history.style = styles[$0] }
        let extraCounts: [Int?] = [nil, 0, 12]
        let shortcuts = popup(extraCounts.map { "Shortcuts: " + label($0) }, selected: 2) { QaTrial.history.extraShortcuts = extraCounts[$0] }
        let auto = popup(["Auto Size: off", "Auto Size: on"], selected: 1) { QaTrial.history.autoSize = $0 == 1 }
        return [searches, style, shortcuts, auto]
    }

    private func attemptedPopup() -> NSPopUpButton {
        let features: [ProJourneyFeature?] = [nil] + ProJourneyFeature.allCases
        let titles = ["Opens on: history", "Opens on: tried Search", "Opens on: tried Styles", "Opens on: tried Shortcuts", "Opens on: tried Auto Size"]
        let button = popup(titles, selected: 0) { QaTrial.history.attempted = features[$0] }
        button.toolTip = "The feature of the last blocked attempt. Day 35 falls back to Search."
        return button
    }

    /// Event-driven, no tick: prompts open and close as windows and popovers, and a refresh follows every
    /// action. The clock line can lag between events.
    private func observeJourney() {
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification,
                                          NSPopover.didShowNotification, NSPopover.didCloseNotification,
                                          ProTransitionManager.proLockStateDidChangeNotification]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshStatusSoon()
            })
        }
    }

    private func refreshStatusSoon() {
        DispatchQueue.main.async { [weak self] in self?.refreshStatus() }
    }

    private func refreshStatus() {
        guard !proSectionContent.isHidden else { return }
        let text = QaTrial.status
        guard status.stringValue != text else { return }
        status.stringValue = text
        sizeToFitContent()
    }

    // MARK: - Controls

    private func row(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.spacing = 4
        return row
    }

    /// The first item of a pull-down is its title. Section headers are disabled items.
    private func pullDown(_ title: String, _ sections: [(String?, [(String, () -> Void)])]) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: true)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10)
        button.autoenablesItems = false
        button.addItem(withTitle: title)
        var actions = [() -> Void]()
        for (index, section) in sections.enumerated() {
            if index > 0 { button.menu?.addItem(.separator()) }
            if let header = section.0 {
                let item = NSMenuItem(title: header, action: nil, keyEquivalent: "")
                item.isEnabled = false
                button.menu?.addItem(item)
            }
            for (title, action) in section.1 {
                button.addItem(withTitle: title)
                button.lastItem?.tag = actions.count
                button.lastItem?.indentationLevel = section.0 == nil ? 0 : 1
                actions.append(action)
            }
        }
        button.onAction = { [weak self] sender in
            guard let item = (sender as? NSPopUpButton)?.selectedItem, item.isEnabled, actions.indices.contains(item.tag) else { return }
            actions[item.tag]()
            self?.refreshStatusSoon()
        }
        return button
    }

    private func popup(_ titles: [String], selected: Int, _ onSelect: ((Int) -> Void)? = nil) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10)
        button.addItems(withTitles: titles)
        button.selectItem(at: selected)
        button.onAction = { sender in onSelect?((sender as! NSPopUpButton).indexOfSelectedItem) }
        return button
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10)
        button.onAction = { _ in action() }
        return button
    }

    private func sizeToFitContent() {
        var size = stack.fittingSize
        size.width += stack.edgeInsets.right
        setContentSize(size)
    }

}
#endif
