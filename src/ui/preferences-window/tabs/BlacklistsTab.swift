import Cocoa
import Sparkle
import UniformTypeIdentifiers

class BlacklistsTab {
    static func initTab() -> NSView {
        let blacklist = BlacklistView()
        let add = NSSegmentedControl(images: [NSImage(named: NSImage.addTemplateName)!, NSImage(named: NSImage.removeTemplateName)!], trackingMode: .momentary, target: nil, action: nil)
        add.onAction = {
            let tableView = blacklist.documentView as! TableView
            if ($0 as! NSSegmentedControl).selectedSegment == 0 {
                let dialog = NSOpenPanel()
                dialog.allowsMultipleSelection = false
                dialog.allowedContentTypes = [.application]
                dialog.canChooseDirectories = false
                dialog.beginSheetModal(for: App.app.preferencesWindow) {
                    if $0 == .OK, let url = dialog.url, let bundleId = Bundle(url: url)?.bundleIdentifier {
                        tableView.insertRow(bundleId)
                    }
                }
            } else {
                tableView.removeSelectedRows()
            }
        }
        let table = TableGroupView(width: PreferencesWindow.width)
        _ = table.addRow(leftViews: [blacklist], secondaryViews: [add])
        let view = TableGroupSetView(originalViews: [table])
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: view.fittingSize.width).isActive = true
        return view
    }
}
