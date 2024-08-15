import Cocoa

class SheetWindow: NSWindow {
    static let width = CGFloat(512)
    var doneButton: NSButton!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        makeDoneButton()
        setupWindow()
        setupView()
    }

    func setupWindow() {
        makeKeyAndOrderFront(nil)
    }

    func setupView() {
        let contentView = makeContentView()
        let view = NSStackView()
        view.orientation = .vertical
        view.alignment = .centerX
        view.spacing = TableGroupSetView.spacing
        view.addArrangedSubview(contentView)
        contentView.topAnchor.constraint(equalTo: view.topAnchor, constant: TableGroupSetView.padding).isActive = true
        contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TableGroupSetView.padding).isActive = true
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TableGroupSetView.padding).isActive = true

        let separator = NSView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = TableGroupView.borderColor.cgColor
        view.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: SheetWindow.width + TableGroupSetView.leftRightPadding).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        separator.topAnchor.constraint(equalTo: contentView.bottomAnchor, constant: TableGroupSetView.padding).isActive = true

        view.addArrangedSubview(doneButton)
        doneButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TableGroupSetView.padding).isActive = true
        doneButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -TableGroupSetView.padding).isActive = true
        self.contentView = view
    }

    func makeContentView() -> NSView {
        return NSView()
    }

    private func makeDoneButton() {
        doneButton = NSButton(title: NSLocalizedString("Done", comment: ""), target: self, action: #selector(cancel))
        doneButton.keyEquivalent = "\r"
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.widthAnchor.constraint(equalToConstant: 70).isActive = true
        if #available(macOS 10.14, *) {
            doneButton.bezelColor = NSColor.controlAccentColor
        }
    }

    // allow to close with the escape key
    @objc func cancel(_ sender: Any?) {
        close()
    }
}
