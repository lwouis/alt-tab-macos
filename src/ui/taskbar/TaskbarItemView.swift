import Cocoa

class TaskbarItemView: NSView {
    var window_: Window?
    private var appIcon: NSImageView!
    private var titleLabel: NSTextField!
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var showPreviewTimer: Timer?
    private var iconSize: CGFloat { Preferences.taskbarIconSize }
    private let iconPadding: CGFloat = 6
    private let titlePadding: CGFloat = 4

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupView() {
        wantsLayer = true
        layer!.cornerRadius = 4
        layer!.masksToBounds = true

        // app icon
        appIcon = NSImageView()
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appIcon)

        // title label
        titleLabel = NSTextField(labelWithString: "")
        titleLabel.font = NSFont.systemFont(ofSize: Preferences.taskbarFontSize)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        updateBackgroundColor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override var acceptsFirstResponder: Bool { true }

    // Accept first mouse click even when window is not key
    // This prevents needing to double-click to activate a window
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // Ensure tracking areas are set up when the view is added to window
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            updateTrackingAreas()
        }
    }

    override func layout() {
        super.layout()

        let iconX = iconPadding
        let iconY = (bounds.height - iconSize) / 2
        appIcon.frame = NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize)

        let labelX = iconX + iconSize + titlePadding
        let labelWidth = bounds.width - labelX - titlePadding
        let labelHeight: CGFloat = 16
        let labelY = (bounds.height - labelHeight) / 2
        titleLabel.frame = NSRect(x: labelX, y: labelY, width: max(0, labelWidth), height: labelHeight)
    }

    func updateContent(_ window: Window) {
        window_ = window

        // update icon
        if let icon = window.icon {
            appIcon.image = NSImage(cgImage: icon, size: NSSize(width: iconSize, height: iconSize))
        } else {
            appIcon.image = nil
        }

        // update font size (in case preference changed)
        titleLabel.font = NSFont.systemFont(ofSize: Preferences.taskbarFontSize)

        // update title - show window title or app name
        let title: String
        if window.title.isEmpty {
            title = window.application.localizedName ?? ""
        } else {
            title = window.title
        }
        titleLabel.stringValue = title
        titleLabel.toolTip = title
    }

    func preferredWidth() -> CGFloat {
        let titleWidth = titleLabel.attributedStringValue.size().width
        return iconPadding + iconSize + titlePadding + titleWidth + titlePadding
    }

    private func updateBackgroundColor() {
        if isHovered {
            layer!.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
            layer!.borderWidth = 1
            layer!.borderColor = NSColor.white.withAlphaComponent(0.4).cgColor
        } else {
            layer!.backgroundColor = NSColor.clear.cgColor
            layer!.borderWidth = 0
            layer!.borderColor = nil
        }
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateBackgroundColor()
        // show thumbnail preview after a short delay
        if let window = window_ {
            showPreviewTimer?.invalidate()
            showPreviewTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let self, self.isHovered else { return }
                TaskbarPreviewPanel.shared.show(for: window, relativeTo: self)
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateBackgroundColor()
        // hide thumbnail preview
        showPreviewTimer?.invalidate()
        showPreviewTimer = nil
        TaskbarPreviewPanel.shared.hide()
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        window_?.focus()
    }
}
