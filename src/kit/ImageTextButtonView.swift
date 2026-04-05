import Cocoa

class ImageTextButtonView: NSStackView {
    class ImageButton: NSButton {
        override var focusRingMaskBounds: NSRect {
            return bounds
        }

        override func drawFocusRingMask() {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                xRadius: ImageTextButtonView.cornerRadius, yRadius: ImageTextButtonView.cornerRadius)
            path.fill()
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if window?.firstResponder == self && NSApp.isActive {
                let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                    xRadius: ImageTextButtonView.cornerRadius, yRadius: ImageTextButtonView.cornerRadius)
                path.lineWidth = 2.0
                path.stroke()
            }
        }

        override func mouseDown(with event: NSEvent) {
            let parent = superview as? ImageTextButtonView
            parent?.isPressed = true
            parent?.updateStyle()
            // NSButton.mouseDown blocks until the click is released or canceled.
            super.mouseDown(with: event)
            parent?.isPressed = false
            parent?.updateStyle()
        }
    }

    /// Pass-through label: the click should activate the parent style tile, not the label itself.
    /// Returning `nil` from `hitTest` lets the click bubble up to `ImageTextButtonView.mouseDown`.
    /// `mouseDownCanMoveWindow=false` is required because `SettingsWindow.isMovableByWindowBackground`
    /// would otherwise drag the window from a label hit (NSTextField labels return `true` by default).
    class ClickableLabel: NSTextField {
        override var mouseDownCanMoveWindow: Bool { false }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    static let spacing = CGFloat(5)
    static let cornerRadius = CGFloat(7)
    static let borderWidth = CGFloat(3)
    static let padding = CGFloat(0)

    var onClick: ActionClosure?
    var button: NSButton!
    var label: NSTextField!
    fileprivate(set) var isPressed = false
    private var windowObservers = [NSObjectProtocol]()

    var state: NSControl.StateValue = .off {
        didSet {
            button.state = state
            updateStyle()
        }
    }

    init(title: String, rawName: String, image: WidthHeightImage,
         state: NSControl.StateValue = .off,
         spacing: CGFloat = ImageTextButtonView.spacing,
         cornerRadius: CGFloat = ImageTextButtonView.cornerRadius) {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .centerX
        self.spacing = spacing
        translatesAutoresizingMaskIntoConstraints = false
        makeButton(rawName, state, image, cornerRadius: cornerRadius)
        makeLabel(title)
        self.state = state
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func makeButton(_ rawName: String, _ state: NSControl.StateValue, _ image: WidthHeightImage,
                            padding: CGFloat = ImageTextButtonView.padding,
                            cornerRadius: CGFloat = ImageTextButtonView.cornerRadius) {
        button = ImageButton(radioButtonWithTitle: "", target: nil, action: nil)
        button.imagePosition = .imageOnly
        button.focusRingType = .default
        button.translatesAutoresizingMaskIntoConstraints = false
        button.wantsLayer = true
        button.layer?.cornerRadius = cornerRadius
        button.layer?.borderWidth = ImageTextButtonView.borderWidth
        button.state = state
        addArrangedSubview(button)
        // Create an NSView to contain the image and provide padding
        let imageContainer = NSView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        // TODO: The appearance theme functionality has not been implemented yet.
        // We will implement it later; for now, use the light theme.
        let imageView = NSImageView(image: NSImage(named: image.name + "_light")!)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = cornerRadius - 3
        imageContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: padding),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -padding),
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -padding),
        ])
        button.addSubview(imageContainer)
        let imageAspectRatio = image.height / image.width
        NSLayoutConstraint.activate([
            imageContainer.topAnchor.constraint(equalTo: button.topAnchor),
            imageContainer.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            imageContainer.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor, constant: ImageTextButtonView.borderWidth),
            button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: ImageTextButtonView.borderWidth),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ImageTextButtonView.borderWidth),
            button.heightAnchor.constraint(equalTo: button.widthAnchor, multiplier: imageAspectRatio),
        ])
        button.identifier = NSUserInterfaceItemIdentifier(rawName)
        button.onAction = { control in
            self.state = .on
            self.onClick?(control)
        }
    }

    private func makeLabel(_ labelText: String) {
        label = ClickableLabel(labelWithString: labelText)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(label)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateStyle()
        var fired = false
        while let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            if next.type == .leftMouseUp {
                let p = convert(next.locationInWindow, from: nil)
                if bounds.contains(p) { fired = true }
                break
            }
        }
        isPressed = false
        updateStyle()
        if fired { button.performClick(nil) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservers.forEach { NotificationCenter.default.removeObserver($0) }
        windowObservers.removeAll()
        guard let window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updateStyle()
            })
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        updateStyle()
    }

    func updateStyle() {
        let isSelected = button.state == .on
        let isKey = window?.isKeyWindow ?? false
        let selectedColor: NSColor
        if #available(macOS 10.14, *) {
            selectedColor = isKey ? NSColor.systemAccentColor : NSColor.unemphasizedSelectedContentBackgroundColor
        } else {
            selectedColor = isKey ? NSColor.systemAccentColor : NSColor.lightGray
        }
        let previousAppearance = NSAppearance.current
        NSAppearance.current = effectiveAppearance
        let borderColor: NSColor = isSelected ? selectedColor : NSColor.lightGray.withAlphaComponent(0.3)
        button.layer?.borderColor = borderColor.cgColor
        NSAppearance.current = previousAppearance
        button.layer?.borderWidth = ImageTextButtonView.borderWidth
        label.font = isSelected ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12)
        alphaValue = isPressed ? 0.7 : 1.0
    }
}
