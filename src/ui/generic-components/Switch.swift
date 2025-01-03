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
            sendAction(action, to: target)
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
        state = isOn ? .on : .off
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupButton() {
        if #available(macOS 10.15, *) {
            bezelStyle = .regularSquare
            isBordered = false
            title = ""
            setButtonType(.toggle)
            switchButton = NSSwitch(frame: bounds)
            switchButton?.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(switchButton!)
            switchButton?.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
            switchButton?.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
            switchButton?.topAnchor.constraint(equalTo: topAnchor).isActive = true
            switchButton?.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            switchButton?.controlSize = .mini
            switchButton?.target = self
            switchButton?.action = #selector(switchToggled(_:))
        } else {
            setButtonType(.switch)
            title = ""
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
        state = sender.state
    }
}
