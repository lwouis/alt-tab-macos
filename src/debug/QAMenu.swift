#if DEBUG
import Cocoa

final class QAMenu: NSPanel {
    static var shared: QAMenu?
    private let stack = NSStackView()
    private let proSectionContent = NSStackView()
    private var proDisclosure: NSButton!
    private let corruptedSectionContent = NSStackView()
    private var corruptedDisclosure: NSButton!

    private static let autosaveName = "QAMenu"
    private static let openSettingsOnLaunchKey = "debug.openSettingsOnLaunch"
    private static let proSectionExpandedKey = "debug.proSectionExpanded"
    private static let corruptedSectionExpandedKey = "debug.corruptedSectionExpanded"
    private static let graphEnabledKey = "debug.graphEnabled"
    private static let sectionSpacing: CGFloat = 16

    static var openSettingsOnLaunch: Bool {
        UserDefaults.standard.bool(forKey: openSettingsOnLaunchKey)
    }

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
            if Preferences.language == .systemDefault {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([Preferences.language.appleLanguageCode!], forKey: "AppleLanguages")
            }
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
        stack.addArrangedSubview(graphCheckbox)
        stack.addArrangedSubview(langDropdown)
        addProTransitionButtons()
        addCorruptedSettingsButtons()
    }

    private func addCorruptedSettingsButtons() {
        let isExpanded = UserDefaults.standard.object(forKey: Self.corruptedSectionExpandedKey) as? Bool ?? false
        corruptedDisclosure = NSButton(title: "", target: nil, action: nil)
        corruptedDisclosure.bezelStyle = .disclosure
        corruptedDisclosure.setButtonType(.pushOnPushOff)
        corruptedDisclosure.state = isExpanded ? .on : .off
        corruptedDisclosure.onAction = { [weak self] _ in
            guard let self else { return }
            let expanded = self.corruptedDisclosure.state == .on
            UserDefaults.standard.set(expanded, forKey: Self.corruptedSectionExpandedKey)
            self.corruptedSectionContent.isHidden = !expanded
            self.sizeToFitContent()
        }
        if let prior = stack.arrangedSubviews.last {
            stack.setCustomSpacing(Self.sectionSpacing, after: prior)
        }
        let header = NSStackView(views: [corruptedDisclosure, sectionLabel("Corrupted settings file")])
        header.orientation = .horizontal
        header.spacing = 4
        stack.addArrangedSubview(header)
        stack.setCustomSpacing(Self.sectionSpacing, after: header)

        corruptedSectionContent.orientation = .vertical
        corruptedSectionContent.alignment = .leading
        corruptedSectionContent.spacing = 8
        corruptedSectionContent.isHidden = !isExpanded
        stack.addArrangedSubview(corruptedSectionContent)

        corruptedSectionContent.addArrangedSubview(sectionLabel("Show “can’t save settings” dialog:"))
        let dialogRow = NSStackView(views: [
            makeButton("Symlink") { PreferencesPersistenceCheck.debugShowDialog(symlinked: true) },
            makeButton("Unwritable") { PreferencesPersistenceCheck.debugShowDialog(symlinked: false) },
        ])
        dialogRow.orientation = .horizontal
        dialogRow.spacing = 4
        corruptedSectionContent.addArrangedSubview(dialogRow)
    }

    /// Wipe every UserDefaults suite the app uses plus every keychain entry under the license service,
    /// so the next launch behaves exactly like a brand-new install.
    private static func mockFreshInstall() {
        UserDefaults.standard.removePersistentDomain(forName: App.bundleIdentifier)
        UserDefaults.standard.removePersistentDomain(forName: LicenseManager.defaultsSuiteName)
        UserDefaults.standard.removePersistentDomain(forName: "\(App.bundleIdentifier).usage")
        SystemKeychain(service: LicenseManager.keychainService).removeAll()
    }

    private func addProTransitionButtons() {
        let isExpanded = UserDefaults.standard.object(forKey: Self.proSectionExpandedKey) as? Bool ?? false
        proDisclosure = NSButton(title: "", target: nil, action: nil)
        proDisclosure.bezelStyle = .disclosure
        proDisclosure.setButtonType(.pushOnPushOff)
        proDisclosure.state = isExpanded ? .on : .off
        proDisclosure.onAction = { [weak self] _ in
            guard let self else { return }
            let expanded = self.proDisclosure.state == .on
            UserDefaults.standard.set(expanded, forKey: Self.proSectionExpandedKey)
            self.proSectionContent.isHidden = !expanded
            self.sizeToFitContent()
        }
        if let prior = stack.arrangedSubviews.last {
            stack.setCustomSpacing(Self.sectionSpacing, after: prior)
        }
        let proHeader = NSStackView(views: [proDisclosure, sectionLabel("Pro Transition")])
        proHeader.orientation = .horizontal
        proHeader.spacing = 4
        stack.addArrangedSubview(proHeader)
        stack.setCustomSpacing(Self.sectionSpacing, after: proHeader)

        proSectionContent.orientation = .vertical
        proSectionContent.alignment = .leading
        proSectionContent.spacing = 8
        proSectionContent.isHidden = !isExpanded
        stack.addArrangedSubview(proSectionContent)

        proSectionContent.addArrangedSubview(sectionLabel("Mock Day:"))
        let mockDayRow = NSStackView(views: [
            makeButton("1") { Self.mockDay(1) },
            makeButton("13") { Self.mockDay(13) },
            makeButton("15 (expired)") { Self.mockDay(15) },
            makeButton("21") { Self.mockDay(21) },
            makeButton("35") { Self.mockDay(35) },
            makeButton("Pro") { LicenseManager.shared.mockProUser() },
        ])
        mockDayRow.orientation = .horizontal
        mockDayRow.spacing = 4
        proSectionContent.addArrangedSubview(mockDayRow)
        proSectionContent.setCustomSpacing(Self.sectionSpacing, after: mockDayRow)

        proSectionContent.addArrangedSubview(sectionLabel("Show window/popover for Day:"))

        let showRow1 = NSStackView(views: [
            makeButton("1 Welcome (new)") {
                Day1WelcomeLetterWindow.shared?.close()
                Day1WelcomeLetterWindow.shared = nil
                Day1WelcomeLetterWindow.show(forceFreshInstall: true)
            },
            makeButton("1 Welcome (upgrade)") {
                Day1WelcomeLetterWindow.shared?.close()
                Day1WelcomeLetterWindow.shared = nil
                Day1WelcomeLetterWindow.show(forceFreshInstall: false)
            },
            makeButton("4 Tour") { Day4TourPopover.show() },
            makeButton("12 HeadsUp") { Day12HeadsUpPopover.show() },
        ])
        showRow1.orientation = .horizontal
        showRow1.spacing = 4
        proSectionContent.addArrangedSubview(showRow1)

        let showRow2 = NSStackView(views: [
            makeButton("15 FullUpgrade") { ProTransitionManager.shared.showFullUpgradeWindow() },
            makeButton("15 Proactive") { ProTransitionManager.shared.showProactiveDay15Window() },
            makeButton("15 HardGate") { Day15HardGatePopover.show() },
        ])
        showRow2.orientation = .horizontal
        showRow2.spacing = 4
        proSectionContent.addArrangedSubview(showRow2)

        let showRow3 = NSStackView(views: [
            makeButton("21 Reminder") { Day21ReminderPopover.show() },
            makeButton("35 Final") { Day35FinalWindow.show() },
        ])
        showRow3.orientation = .horizontal
        showRow3.spacing = 4
        proSectionContent.addArrangedSubview(showRow3)
        proSectionContent.setCustomSpacing(Self.sectionSpacing, after: showRow3)

        proSectionContent.addArrangedSubview(sectionLabel("Reset:"))
        let resetRow1 = NSStackView(views: [
            makeButton("Free Pass") {
                ProTransitionManager.shared.freePassUsed = false
                Logger.debug { "freePassUsed reset to false" }
            },
            makeButton("Day4 Tour") {
                ProTransitionManager.shared.hasSeenDay4Tour = false
                Logger.debug { "hasSeenDay4Tour reset to false" }
            },
            makeButton("Switcher Trigger") {
                ProTransitionManager.shared.hasTriggeredPostExpirationSwitcher = false
                Logger.debug { "hasTriggeredPostExpirationSwitcher reset to false" }
            },
        ])
        resetRow1.orientation = .horizontal
        resetRow1.spacing = 4
        proSectionContent.addArrangedSubview(resetRow1)

        let resetRow2 = NSStackView(views: [
            makeButton("Toggle Opt-Out") {
                let mgr = ProTransitionManager.shared
                mgr.userOptedOut = !mgr.userOptedOut
                Logger.debug { "userOptedOut = \(mgr.userOptedOut)" }
            },
            makeButton("Revalidate") { LicenseManager.shared.revalidateWithServer() },
            makeButton("Mock fresh install") { Self.mockFreshInstall() },
        ])
        resetRow2.orientation = .horizontal
        resetRow2.spacing = 4
        proSectionContent.addArrangedSubview(resetRow2)
    }

    /// Mock passage of time to a specific day. Resets transition state and marks earlier prompts
    /// as already seen so they don't re-fire. Mock Day 15 lands on the post-trial *grace* period
    /// (trial expired, no Day15 window shown yet) so QA can click `Day15 Proactive` or
    /// `Day15 FullUpgrade` to exercise each path, then observe the locked state after.
    private static func mockDay(_ day: Int) {
        let mgr = ProTransitionManager.shared
        mgr.resetAllState()
        if day > 1 { mgr.hasSeenWelcome = true }
        if day > 4 { mgr.hasSeenDay4Tour = true }
        if day > 12 { mgr.hasSeenDay12 = true }
        LicenseManager.shared.mockTrialDay(day)
        Menubar.menubarIconCallback(nil)
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
