import Cocoa

class TaskbarSettingsSheet: SheetWindow {
    override func makeContentView() -> NSView {
        let table = TableGroupView(title: NSLocalizedString("Taskbar", comment: ""), width: SheetWindow.width)

        // Size settings
        let heightSlider = LabelAndControl.makeLabelWithSlider("", "taskbarHeight", 24, 64, 9, true, "px", width: 180, extraAction: { _ in
            TaskbarManager.shared.repositionAll()
            // re-adjust maximized windows when taskbar height changes
            TaskbarManager.shared.adjustAllMaximizedWindows()
        })
        let heightIndicator = heightSlider[2] as! NSTextField
        heightIndicator.alignment = .right
        heightIndicator.fit(56, heightIndicator.fittingSize.height)
        table.addRow(leftText: NSLocalizedString("Taskbar height", comment: ""),
            rightViews: [heightSlider[1], heightIndicator])

        let itemHeightSlider = LabelAndControl.makeLabelWithSlider("", "taskbarItemHeight", 18, 48, 7, true, "px", width: 180, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        let itemHeightIndicator = itemHeightSlider[2] as! NSTextField
        itemHeightIndicator.alignment = .right
        itemHeightIndicator.fit(56, itemHeightIndicator.fittingSize.height)
        table.addRow(leftText: NSLocalizedString("Item height", comment: ""),
            rightViews: [itemHeightSlider[1], itemHeightIndicator])

        let iconSizeSlider = LabelAndControl.makeLabelWithSlider("", "taskbarIconSize", 12, 32, 5, true, "px", width: 180, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        let iconSizeIndicator = iconSizeSlider[2] as! NSTextField
        iconSizeIndicator.alignment = .right
        iconSizeIndicator.fit(56, iconSizeIndicator.fittingSize.height)
        table.addRow(leftText: NSLocalizedString("Icon size", comment: ""),
            rightViews: [iconSizeSlider[1], iconSizeIndicator])

        let fontSizeSlider = LabelAndControl.makeLabelWithSlider("", "taskbarFontSize", 9, 16, 8, true, "pt", width: 180, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        let fontSizeIndicator = fontSizeSlider[2] as! NSTextField
        fontSizeIndicator.alignment = .right
        fontSizeIndicator.fit(56, fontSizeIndicator.fittingSize.height)
        table.addRow(leftText: NSLocalizedString("Font size", comment: ""),
            rightViews: [fontSizeSlider[1], fontSizeIndicator])

        // Filter settings
        table.addNewTable()

        let spacesToShow = LabelAndControl.makeDropdown("taskbarSpacesToShow", SpacesToShowPreference.allCases, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        table.addRow(leftText: NSLocalizedString("Show windows from Spaces", comment: ""),
            rightViews: [spacesToShow])

        let showMinimizedWindows = LabelAndControl.makeDropdown("taskbarShowMinimizedWindows", ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        table.addRow(leftText: NSLocalizedString("Show minimized windows", comment: ""),
            rightViews: [showMinimizedWindows])

        let showHiddenWindows = LabelAndControl.makeDropdown("taskbarShowHiddenWindows", ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        table.addRow(leftText: NSLocalizedString("Show hidden windows", comment: ""),
            rightViews: [showHiddenWindows])

        let showFullscreenWindows = LabelAndControl.makeDropdown("taskbarShowFullscreenWindows", ShowHowPreference.allCases.filter { $0 != .showAtTheEnd }, extraAction: { _ in
            TaskbarManager.shared.updateContents()
        })
        table.addRow(leftText: NSLocalizedString("Show fullscreen windows", comment: ""),
            rightViews: [showFullscreenWindows])

        table.fit()
        return table
    }
}
