import Cocoa

class FilterTab {
    static func initTab() -> NSView {
        let minWindowWidth = LabelAndControl.makeNumberField("minWindowWidth", "0")
        let maxWindowWidth = LabelAndControl.makeNumberField("maxWindowWidth", "0")
        let minWindowX = LabelAndControl.makeNumberField("minWindowX", "0")
        let maxWindowX = LabelAndControl.makeNumberField("maxWindowX", "0")
        let minWindowY = LabelAndControl.makeNumberField("minWindowY", "0")
        let maxWindowY = LabelAndControl.makeNumberField("maxWindowY", "0")

        let table = TableGroupView(width: PreferencesWindow.width)
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Minimum window width (px)", comment: ""), rightViews: [minWindowWidth]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Maximum window width (px)", comment: ""), rightViews: [maxWindowWidth]))
        table.addNewTable()
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Minimum X position (px)", comment: ""), rightViews: [minWindowX]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Maximum X position (px)", comment: ""), rightViews: [maxWindowX]))
        table.addNewTable()
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Minimum Y position (px)", comment: ""), rightViews: [minWindowY]))
        table.addRow(TableGroupView.Row(leftTitle: NSLocalizedString("Maximum Y position (px)", comment: ""), rightViews: [maxWindowY]))
        table.fit()

        let infoText = NSTextField(wrappingLabelWithString: NSLocalizedString("Set to 0 to disable filtering. Windows outside the specified ranges will be hidden from the switcher.", comment: ""))
        infoText.textColor = .secondaryLabelColor
        infoText.translatesAutoresizingMaskIntoConstraints = false
        infoText.preferredMaxLayoutWidth = PreferencesWindow.width - TableGroupSetView.leftRightPadding

        let view = TableGroupSetView(originalViews: [table, infoText])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }
}

