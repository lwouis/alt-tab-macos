import Cocoa

class Switch: NSButton {
    let switchButton = NSSwitch()

    override var state: NSControl.StateValue {
        didSet {
            switchButton.state = state
            sendAction(action, to: target)
        }
    }

    /// Set the state without firing the target/action. Used when re-syncing a non-overridden
    /// per-shortcut control to a changed global value — we want the UI to follow the global
    /// without writing a UserDefaults override for the shortcut.
    func setSilently(_ newState: NSControl.StateValue) {
        switchButton.state = newState
        // Bypass `state`'s `didSet` so `sendAction` isn't called.
        super.state = newState
    }

    override var isEnabled: Bool {
        didSet { switchButton.isEnabled = isEnabled }
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
        bezelStyle = .regularSquare
        isBordered = false
        title = ""
        setButtonType(.toggle)
        switchButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(switchButton)
        switchButton.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        switchButton.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
        switchButton.topAnchor.constraint(equalTo: topAnchor).isActive = true
        switchButton.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
        switchButton.controlSize = .mini
        switchButton.target = self
        switchButton.action = #selector(switchToggled(_:))
    }

    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        switchButton.draw(dirtyRect)
    }

    @objc private func switchToggled(_ sender: NSButton) {
        state = sender.state
    }
}
