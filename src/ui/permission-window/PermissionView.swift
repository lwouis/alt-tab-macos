import Cocoa

class PermissionView: StackView {
    static let greenColor = NSColor(srgbRed: 0.38, green: 0.75, blue: 0.33, alpha: 0.2)
    static let redColor = NSColor(srgbRed: 0.90, green: 0.35, blue: 0.32, alpha: 0.2)

    var checkFunction: (() -> Bool)!
    var button: NSButton!
    var status: NSTextField!
    var isPermissionGranted = false

    convenience init(_ iconName: String, _ title: String, _ justification: String, _ buttonText: String, _ buttonUrl: String, _ checkFunction: @escaping () -> Bool) {
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
        justification.widthAnchor.constraint(equalToConstant: justification.fittingSize.width + 5).isActive = true
        let button = Button(buttonText) { _ in NSWorkspace.shared.open(URL(string: buttonUrl)!) }
        let status = NSTextField(wrappingLabelWithString: "")
        status.translatesAutoresizingMaskIntoConstraints = false
        let buttonStack = NSStackView(views: [button, status])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.alignment = .centerY
        self.init([titleStack, justification, buttonStack], .vertical, top: GridView.interPadding, right: GridView.interPadding, bottom: GridView.interPadding, left: GridView.interPadding)
        self.checkFunction = checkFunction
        self.button = button
        self.status = status
        wantsLayer = true
        layer!.cornerRadius = GridView.interPadding / 2
        updatePermissionStatus(checkFunction())
    }

    func updatePermissionStatus(_ isPermissionGranted: Bool) {
        self.isPermissionGranted = isPermissionGranted
        if isPermissionGranted {
            let color = PermissionView.greenColor
            button.isEnabled = false
            status.stringValue = "● " + NSLocalizedString("Allowed", comment: "")
            status.textColor = color.withAlphaComponent(1)
            layer!.backgroundColor = color.cgColor
        } else {
            let color = PermissionView.redColor
            button.isEnabled = true
            status.stringValue = "● " + NSLocalizedString("Not allowed", comment: "")
            status.textColor = color.withAlphaComponent(1)
            layer!.backgroundColor = color.cgColor
        }
    }
}
