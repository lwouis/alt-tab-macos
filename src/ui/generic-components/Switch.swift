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
        }
    }

    override var isEnabled: Bool {
        didSet {
            if #available(macOS 10.15, *) {
                if let switchButton = switchButton as? NSSwitch {
                    switchButton.isEnabled = isHidden
                }
            }
        }
    }

    var isOn: Bool {
        get {
            return self.state == .on
        }
        set {
            self.state = newValue ? .on : .off
        }
    }

    init(_ isOn: Bool = false) {
        super.init(frame: .zero)
        setupButton()
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

    @objc private func switchToggled(_ sender: NSButton) {
        self.state = sender.state
        sendAction(self.action, to: self.target)
    }
}
