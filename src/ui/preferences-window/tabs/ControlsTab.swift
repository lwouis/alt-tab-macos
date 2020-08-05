import Cocoa
import ShortcutRecorder
import Preferences

class ControlsTab: NSViewController, PreferencePane {
    let preferencePaneIdentifier = PreferencePane.Identifier("Controls")
    let preferencePaneTitle = NSLocalizedString("Controls", comment: "")
    let toolbarItemIcon = NSImage(named: "controls")!

    static var nextWindowShortcut: NSControl!
    static var nextWindowShortcut2: NSControl!
    static var shortcuts = [String: Shortcut]()
    static var shortcutsActions = [
        "holdShortcut": { App.app.focusTarget() },
        "holdShortcut2": { App.app.focusTarget() },
        "focusWindowShortcut": { App.app.focusTarget() },
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
        let shortcutStyle = LabelAndControl.makeLabelWithDropdown(NSLocalizedString("then release:", comment: ""), "shortcutStyle", ShortcutStylePreference.allCases)
        let focusWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Focus selected window", comment: ""), "focusWindowShortcut", Preferences.focusWindowShortcut, labelPosition: .right)
        let previousWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select previous window", comment: ""), "previousWindowShortcut", Preferences.previousWindowShortcut, labelPosition: .right)
        let cancelShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Cancel and hide", comment: ""), "cancelShortcut", Preferences.cancelShortcut, labelPosition: .right)
        let closeWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Close window", comment: ""), "closeWindowShortcut", Preferences.closeWindowShortcut, labelPosition: .right)
        let minDeminWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Minimize/Deminimize window", comment: ""), "minDeminWindowShortcut", Preferences.minDeminWindowShortcut, labelPosition: .right)
        let quitAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Quit app", comment: ""), "quitAppShortcut", Preferences.quitAppShortcut, labelPosition: .right)
        let hideShowAppShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hide/Show app", comment: ""), "hideShowAppShortcut", Preferences.hideShowAppShortcut, labelPosition: .right)
        let enableArrows = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Arrow keys", comment: ""), "arrowKeysEnabled", extraAction: ControlsTab.arrowKeysEnabledCallback, labelPosition: .right)
        let enableMouse = LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Mouse hover", comment: ""), "mouseHoverEnabled", labelPosition: .right)
        let checkboxesExplanations = LabelAndControl.makeLabel(NSLocalizedString("Also select windows using:", comment: ""))
        let checkboxes = StackView([StackView(enableArrows), StackView(enableMouse)], .vertical)
        let shortcuts = StackView([focusWindowShortcut, previousWindowShortcut, cancelShortcut, closeWindowShortcut, minDeminWindowShortcut, quitAppShortcut, hideShowAppShortcut].map { (view: [NSView]) in StackView(view) }, .vertical)
        let orPress = LabelAndControl.makeLabel(NSLocalizedString("While open, press:", comment: ""), shouldFit: false)
        let (nextWindowShortcut, tab1View) = toShowSection("")
        let (nextWindowShortcut2, tab2View) = toShowSection("2")
        let tabView = TabView([(NSLocalizedString("Shortcut 1", comment: ""), tab1View), (NSLocalizedString("Shortcut 2", comment: ""), tab2View)])

        ControlsTab.nextWindowShortcut = nextWindowShortcut[0] as! NSControl
        ControlsTab.nextWindowShortcut2 = nextWindowShortcut2[0] as! NSControl
        ControlsTab.arrowKeysEnabledCallback(enableArrows[0] as! NSControl)

        let grid = GridView([
            [tabView],
            shortcutStyle,
            [orPress, shortcuts],
            [checkboxesExplanations, checkboxes],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: 0, length: 1))
        grid.cell(atColumnIndex: 0, rowIndex: 0).xPlacement = .leading

        // TODO: better layout logic. Maybe freeze the width of the preference window and have labels wrap on multiple lines
        // currently this looks bad if the right column inside the tabView is larger than the right column of the top gridView
        let leftColumnWidthTabView = tab1View.column(at: 0).width()
        let leftColumnWidthTopView = grid.column(at: 0).width(0)
        debugPrint("hey", leftColumnWidthTabView, leftColumnWidthTopView)
        if leftColumnWidthTabView > leftColumnWidthTopView {
            orPress.fit(tab1View.column(at: 0).width() + GridView.interPadding + TabView.padding, orPress.fittingSize.height)
        } else {
            orPress.fit()
            tabView.leftAnchor.constraint(equalTo: tabView.superview!.leftAnchor, constant: leftColumnWidthTopView - leftColumnWidthTabView + 3).isActive = true
        }

        setView(grid)
    }

    private func toShowSection(_ postfix: String) -> ([NSView], GridView) {
        let toShowExplanations = LabelAndControl.makeLabel(NSLocalizedString("Show the following windows:", comment: ""))
        var holdShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Hold", comment: ""), "holdShortcut" + postfix, Preferences.holdShortcut, false, labelPosition: .leftWithoutSeparator)
        holdShortcut.append(LabelAndControl.makeLabel(NSLocalizedString("and press:", comment: "")))
        let holdAndPress = StackView(holdShortcut)
        let appsToShow = LabelAndControl.makeDropdown("appsToShow" + postfix, AppsToShowPreference.allCases)
        let spacesToShow = LabelAndControl.makeDropdown("spacesToShow" + postfix, SpacesToShowPreference.allCases)
        let screensToShow = LabelAndControl.makeDropdown("screensToShow" + postfix, ScreensToShowPreference.allCases)
        let showMinimizedWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Minimized", comment: ""), "showMinimizedWindows" + postfix, labelPosition: .right))
        let showHiddenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Hidden", comment: ""), "showHiddenWindows" + postfix, labelPosition: .right))
        let showFullscreenWindows = StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Fullscreen", comment: ""), "showFullscreenWindows" + postfix, labelPosition: .right))
        let nextWindowShortcut = LabelAndControl.makeLabelWithRecorder(NSLocalizedString("Select next window", comment: ""), "nextWindowShortcut" + postfix, Preferences.nextWindowShortcut[postfix == "" ? 0 : 1], labelPosition: .right)
        let toShowDropdowns = StackView([appsToShow, spacesToShow, screensToShow, showMinimizedWindows, showHiddenWindows, showFullscreenWindows], .vertical, false)
        toShowDropdowns.spacing = TabView.padding
        toShowDropdowns.fit()
        let tab = GridView([
            [toShowExplanations, toShowDropdowns],
            [holdAndPress, StackView(nextWindowShortcut)],
        ], TabView.padding)
        tab.column(at: 0).xPlacement = .trailing
        tab.fit()
        return (nextWindowShortcut, tab)
    }

    private static func addShortcut(_ type: KeyEventType, _ shortcut: Shortcut, _ controlId: String) {
        removeShortcutIfExists(controlId, type) // remove the previous shortcut
        shortcuts[controlId] = shortcut
    }

    @objc static func shortcutChangedCallback(_ sender: NSControl) {
        let controlId = sender.identifier!.rawValue
        if controlId == "holdShortcut" {
            addShortcut(.up, Shortcut(keyEquivalent: Preferences.holdShortcut)!, controlId)
            if let s = nextWindowShortcut {
                shortcutChangedCallback(s)
            }
        } else if controlId == "holdShortcut2" {
            addShortcut(.up, Shortcut(keyEquivalent: Preferences.holdShortcut2)!, controlId)
            if let s = nextWindowShortcut2 {
                shortcutChangedCallback(s)
            }
        } else {
            let newValue = shortcutStringValue(controlId, sender)
            if newValue.isEmpty {
                removeShortcutIfExists(controlId, .down)
            } else {
                addShortcut(.down, Shortcut(keyEquivalent: newValue)!, controlId)
            }
        }
    }

    static func shortcutStringValue(_ controlId: String, _ sender: NSControl) -> String {
        let baseValue = (sender as! RecorderControl).stringValue
        if controlId == "nextWindowShortcut" || controlId == "nextWindowShortcut2" {
            let holdShortcut = controlId == "nextWindowShortcut" ? Preferences.holdShortcut : Preferences.holdShortcut2
            // remove the holdShortcut character in case they also use it in the other shortcuts
            return holdShortcut + holdShortcut.reduce(baseValue, { $0.replacingOccurrences(of: String($1), with: "") })
        }
        return baseValue
    }

    @objc static func arrowKeysEnabledCallback(_ sender: NSControl) {
        let keys = ["←", "→", "↑", "↓"]
        if (sender as! NSButton).state == .on {
            keys.forEach { addShortcut(.down, Shortcut(keyEquivalent: $0)!, $0) }
        } else {
            keys.forEach { removeShortcutIfExists($0, .down) }
        }
    }

    private static func removeShortcutIfExists(_ controlId: String, _ type: KeyEventType) {
        if let a = shortcuts[controlId] {
            shortcuts.removeValue(forKey: controlId)
        }
    }
}
