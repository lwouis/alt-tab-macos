import Cocoa

class SheetWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    class WindowContentView: NSStackView {
        var separator: NSView!

        init(_ separator: NSView) {
            super.init(frame: .zero)
            self.separator = separator
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            separator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
        }
    }

    static let width = CGFloat(500)
    let separator = NSView()
    var doneButton: NSButton!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        makeDoneButton()
        setupView()
    }

    func setupView() {
        let contentView = makeContentView()
        let view = WindowContentView(separator)
        view.orientation = .vertical
        view.alignment = .centerX
        view.spacing = TableGroupSetView.spacing
        view.addArrangedSubview(contentView)
        contentView.topAnchor.constraint(equalTo: view.topAnchor, constant: TableGroupSetView.padding).isActive = true
        contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -TableGroupSetView.padding).isActive = true
        contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: TableGroupSetView.padding).isActive = true

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = NSColor.tableSeparatorColor.cgColor
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
        sheetParent!.endSheet(self)
    }
}
