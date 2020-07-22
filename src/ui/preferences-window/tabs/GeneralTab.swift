import Cocoa
import ShortcutRecorder
import Preferences

class GeneralTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("General")
    let preferencePaneTitle = NSLocalizedString("General", comment: "")
    let toolbarItemIcon = NSImage(named: NSImage.preferencesGeneralName)!

    static var shortcutActions = [String: ShortcutAction]()
    static var shortcutsDependentOnHoldShortcut = [NSControl]()
    static var shortcutsActionsBlocks = [
        "holdShortcut": { App.app.focusTarget() },
        "nextWindowShortcut": { App.app.showUiOrCycleSelection(0) },
        "nextWindowShortcut2": { App.app.showUiOrCycleSelection(1) },
        "previousWindowShortcut": { App.app.cycleSelection(.trailing) },
        "→": { App.app.cycleSelection(.right) },
        "←": { App.app.cycleSelection(.left) },
        "↑": { App.app.cycleSelection(.up) },
        "↓": { App.app.cycleSelection(.down) },
        "cancelShortcut": { App.app.hideUi() },
        "closeWindowShortcut": { App.app.closeSelectedWindow() },
        "minDeminWindowShortcut": { App.app.minDeminSelectedWindow() },
        "quitAppShortcut": { App.app.quitSelectedApp() },
        "hideShowAppShortcut": { App.app.hideShowSelectedApp() },
    ]

    override func loadView() {
        let startAtLogin = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Start at login:", comment: ""), "startAtLogin", extraAction: startAtLoginCallback)
        let hideMenubarIcon = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hide menubar icon:", comment: ""), "hideMenubarIcon", extraAction: hideMenubarIconCallback)
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), "holdShortcut", Preferences.holdShortcut, false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press:", comment: "")))
        let previousWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)
        let cancelShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)
        let closeWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)
        let minDeminWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)
        let quitAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)
        let hideShowAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)
        let enableArrows = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Arrow keys", comment: ""), "arrowKeysEnabled", extraAction: GeneralTab.arrowKeysEnabledCallback, labelPosition: .right)
        let enableMouse = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Mouse hover", comment: ""), "mouseHoverEnabled", labelPosition: .right)
        let holdAndPress = StackView(holdShortcut)
        let checkboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Select windows using:", comment: ""))
        let checkboxes = StackView([StackView(enableArrows), StackView(enableMouse)], .vertical)
        let shortcuts = StackView([previousWindowShortcut, cancelShortcut, closeWindowShortcut, minDeminWindowShortcut, quitAppShortcut, hideShowAppShortcut].map { (view: [NSView]) in StackView(view) }, .vertical)
        let thenRelease = LabelAndControl.makeLabel(NSLocalizedString("then release:", comment: ""))
        let orPress = LabelAndControl.makeLabel(NSLocalizedString("or press:", comment: ""))
        let focusSelectedWindow = LabelAndControl.makeLabel(NSLocalizedString("Focus selected window", comment: ""))
        let toShowExplanations = LabelAndControl.makeLabel(NSLocalizedString("Show the following windows:", comment: ""))

        let tab1 = NSTabViewItem(identifier: 1)
        tab1.label = "1"
        let (nextWindowShortcut, tab1View) = toShowSection("")
        tab1.view = tab1View
        let tab2 = NSTabViewItem(identifier: 2)
        tab2.label = "2"
        let (nextWindowShortcut2, tab2View) = toShowSection("2")
        tab2.view = tab2View
        let tabView = TabView()
        tabView.addTabViewItem(tab1)
        tabView.addTabViewItem(tab2)
        tabView.tabPosition = .right
        tabView.heightAnchor.constraint(equalToConstant: tabView.fittingSize.height - 8).isActive = true

        let vertical1 = StackView([toShowExplanations, holdAndPress], .vertical, false, top: 5, bottom: 3)
        vertical1.alignment = .trailing
        vertical1.distribution = .equalCentering
        vertical1.heightAnchor.constraint(equalToConstant: tabView.fittingSize.height - 14).isActive = true
        let grid = GridView([
            startAtLogin,
            hideMenubarIcon,
            [vertical1, tabView],
            [thenRelease, focusSelectedWindow],
            [orPress, shortcuts],
            [checkboxesExplanations, checkboxes],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.row(at: 2).rowAlignment = .none
        [2, 5].forEach { grid.row(at: $0).topPadding = GridView.interPadding }
        grid.fit()

        GeneralTab.shortcutsDependentOnHoldShortcut.append(contentsOf: [enableArrows[0] as! NSControl] +
            [nextWindowShortcut, nextWindowShortcut2, previousWindowShortcut, cancelShortcut,
             closeWindowShortcut, minDeminWindowShortcut, quitAppShortcut, hideShowAppShortcut].map { $0[0] as! NSControl })
        GeneralTab.arrowKeysEnabledCallback(enableArrows[0] as! NSControl)
        startAtLoginCallback(startAtLogin[1] as! NSControl)
        hideMenubarIconCallback(hideMenubarIcon[1] as! NSControl)

        view = grid
    }

    private func toShowSection(_ postfix: String) -> ([NSView], NSView) {
        let appsToShow = dropdown("appsToShow" + postfix, AppsToShowPreference.allCases)
        let spacesToShow = dropdown("spacesToShow" + postfix, SpacesToShowPreference.allCases)
        let screensToShow = dropdown("screensToShow" + postfix, ScreensToShowPreference.allCases)
        let showMinimizedWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Minimized", comment: ""), "showMinimizedWindows" + postfix, labelPosition: .right))
        let showHiddenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hidden", comment: ""), "showHiddenWindows" + postfix, labelPosition: .right))
        let showFullscreenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fullscreen", comment: ""), "showFullscreenWindows" + postfix, labelPosition: .right))
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), "nextWindowShortcut" + postfix, Preferences.nextWindowShortcut[postfix == "" ? 0 : 1], labelPosition: .right)
        let toShowDropdowns = StackView([appsToShow, spacesToShow, screensToShow, showMinimizedWindows, showHiddenWindows, showFullscreenWindows], .vertical, false)
        toShowDropdowns.spacing = 8
        toShowDropdowns.fit()
        let tab = StackView([toShowDropdowns, StackView(nextWindowShortcut)], .vertical, false)
        tab.spacing = GridView.padding
        tab.fit()
        return (nextWindowShortcut, tab)
    }

    private func dropdown(_ rawName: String, _ macroPreferences: [MacroPreference]) -> NSControl {
        let dropdown = LabelAndControl.makeDropDown(rawName, macroPreferences)
        return LabelAndControl.setupControl(dropdown, rawName)
    }

    private static func addShortcut(_ type: KeyEventType, _ shortcut: Shortcut, _ controlId: String) {
        removeShortcutIfExists(controlId, type) // remove the previous shortcut
        shortcutActions[controlId] = ShortcutAction(shortcut: shortcut, actionHandler: { _ in
            let isShortcutInitiatingTheApp = ["nextWindowShortcut", "nextWindowShortcut2"].contains(controlId)
            if isShortcutInitiatingTheApp {
                App.app.appIsBeingUsed = true
            }
            if App.app.appIsBeingUsed {
                let isShortcutClosingTheUi = ["holdShortcut", "cancelShortcut"].contains(controlId)
                if isShortcutClosingTheUi {
                    App.app.appIsBeingUsed = false
                    App.app.isFirstSummon = true
                }
                DispatchQueue.main.async { () -> () in shortcutsActionsBlocks[controlId]!() }
            }
            return true
        })
        App.shortcutMonitor.addAction(shortcutActions[controlId]!, forKeyEvent: type)
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl, _ rawName: String) {
        if rawName == "holdShortcut" {
            addShortcut(.up, Shortcut(keyEquivalent: Preferences.holdShortcut)!, rawName)
            shortcutsDependentOnHoldShortcut.forEach {
                if $0.identifier!.rawValue == "arrowKeysEnabled" {
                    GeneralTab.arrowKeysEnabledCallback($0)
                } else {
                    GeneralTab.shortcutChangedCallback($0, rawName)
                }
            }
        } else {
            // remove the holdShortcut character in case they also use it in the other shortcuts
            let newValue = Preferences.holdShortcut.reduce((sender as! RecorderControl).stringValue, { $0.replacingOccurrences(of: String($1), with: "") })
            if newValue.isEmpty {
                removeShortcutIfExists(rawName, .down)
                return
            }
            addShortcut(.down, Shortcut(keyEquivalent: Preferences.holdShortcut + newValue)!, rawName)
        }
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        let keys = ["←", "→", "↑", "↓"]
        if (sender as! NSButton).state == .on {
            keys.forEach { addShortcut(.down, Shortcut(keyEquivalent: Preferences.holdShortcut + $0)!, $0) }
        } else {
            keys.forEach { removeShortcutIfExists($0, .down) }
        }
    }

    private static func removeShortcutIfExists(_ controlId: String, _ type: KeyEventType) {
        if let a = shortcutActions[controlId] {
            App.shortcutMonitor.removeAction(_: a, forKeyEvent: type)
            shortcutActions.removeValue(forKey: controlId)
        }
    }

    // adding/removing login item depending on the checkbox state
    @available(OSX, deprecated: 10.11)
    func startAtLoginCallback(_ sender: NSControl) {
        let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil).takeRetainedValue()
        let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil).takeRetainedValue() as! [LSSharedFileListItem]
        let itemName = Bundle.main.bundleURL.lastPathComponent as CFString
        let itemUrl = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
        loginItemsSnapshot.forEach {
            if (LSSharedFileListItemCopyDisplayName($0)?.takeRetainedValue() == itemName) ||
                   (LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == itemUrl) {
                LSSharedFileListItemRemove(loginItems, $0)
            }
        }
        if (sender as! NSButton).state == .on {
            let _ = LSSharedFileListInsertItemURL(loginItems, kLSSharedFileListItemBeforeFirst.takeRetainedValue(), nil, nil, itemUrl, nil, nil).takeRetainedValue()
        }
    }

    private func hideMenubarIconCallback(_ sender: NSControl) {
        App.statusItem.isVisible = (sender as! NSButton).state == .off
    }
}
