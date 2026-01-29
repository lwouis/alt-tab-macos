import Cocoa

class PermissionView: StackView {
    static let greenColor = NSColor(srgbRed: 0.38, green: 0.75, blue: 0.33, alpha: 0.2)
    static let redColor = NSColor(srgbRed: 0.90, green: 0.35, blue: 0.32, alpha: 0.2)
    static let yellowColor = NSColor(srgbRed: 0.83, green: 0.66, blue: 0.07, alpha: 0.2)

    var status: NSTextField!
    var permissionStatus = PermissionStatus.notGranted

    convenience init(_ iconName: String, _ title: String, _ justification: String, _ buttonText: String, _ buttonUrl: String, _ checkFunction: @escaping () -> PermissionStatus, _ skipCheckbox: NSView? = nil) {
        let icon = NSImageView(image: NSImage.initCopy(iconName))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.fit()
        let title = BoldLabel(title)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.fit()
        let titleStack = NSStackView(views: [icon, title])
        titleStack.translatesAutoresizingMaskIntoConstraints = false
        titleStack.alignment = .centerY
        titleStack.spacing = GridView.interPadding
        titleStack.fit()
        let justification = NSTextField(wrappingLabelWithString: justification)
        justification.translatesAutoresizingMaskIntoConstraints = false
        justification.preferredMaxLayoutWidth = 500
        justification.addOrUpdateConstraint(justification.widthAnchor, justification.fittingSize.width + 5)
        let button = Button(buttonText) { _ in NSWorkspace.shared.open(URL(string: buttonUrl)!) }
        let status = NSTextField(wrappingLabelWithString: "")
        status.translatesAutoresizingMaskIntoConstraints = false
        let buttonStack = NSStackView(views: [button, status])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.alignment = .centerY
        var views = [titleStack, justification, buttonStack]
        if let skipCheckbox {
            views.append(skipCheckbox)
        }
        self.init(views, .vertical, top: GridView.interPadding, right: GridView.interPadding, bottom: GridView.interPadding, left: GridView.interPadding)
        self.status = status
        wantsLayer = true
        layer!.cornerRadius = GridView.interPadding / 2
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func updatePermissionStatus(_ permissionStatus: PermissionStatus) {
        guard status.stringValue.isEmpty || permissionStatus != self.permissionStatus else { return }
        self.permissionStatus = permissionStatus
        var color: NSColor
        var label: String
        switch permissionStatus {
            case .granted:
                color = PermissionView.greenColor
                label = NSLocalizedString("Allowed", comment: "")
            case .notGranted:
                color = PermissionView.redColor
                label = NSLocalizedString("Not allowed", comment: "")
            case .skipped:
                color = PermissionView.yellowColor
                label = NSLocalizedString("Skipped", comment: "")
        }
        status.stringValue = "● " + label
        status.textColor = color.withAlphaComponent(1)
        layer!.backgroundColor = color.cgColor
    }
}

enum PermissionStatus {
    case granted
    case notGranted
    case skipped
}
