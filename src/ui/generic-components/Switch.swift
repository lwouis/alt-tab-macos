import Cocoa
class Switch: NSButton {

    var switchButton: NSControl?

    override var state: NSControl.StateValue {
        didSet {
            if #available(macOS 10.15, *) {
                if let switchButton = switchButton as? NSSwitch {
                    switchButton.state = state
                }
            }
            sendAction(self.action, to: self.target)
        }
    }

    override var isEnabled: Bool {
        didSet {
            if #available(macOS 10.15, *) {
                if let switchButton = switchButton as? NSSwitch {
                    switchButton.isEnabled = isEnabled
                }
            }
        }
    }

    init(_ isOn: Bool = false) {
        super.init(frame: .zero)
        setupButton()
        self.state = isOn ? .on : .off
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupButton() {
        if #available(macOS 10.15, *) {
            self.bezelStyle = .regularSquare
            self.isBordered = false
            self.title = ""
            self.setButtonType(.toggle)

            switchButton = NSSwitch(frame: self.bounds)
            switchButton?.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(switchButton!)
            switchButton?.leadingAnchor.constraint(equalTo: self.leadingAnchor).isActive = true
            switchButton?.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
            switchButton?.topAnchor.constraint(equalTo: self.topAnchor).isActive = true
            switchButton?.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
            switchButton?.controlSize = .mini

            switchButton?.target = self
            switchButton?.action = #selector(switchToggled(_:))
        } else {
            self.setButtonType(.switch)
            self.title = ""
        }
    }

    override var acceptsFirstResponder: Bool {
        switchButton == nil ? true : false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let switchButton = switchButton {
            switchButton.draw(dirtyRect)
        }
    }

    @objc private func switchToggled(_ sender: NSButton) {
        self.state = sender.state
    }
}
