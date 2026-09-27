import Cocoa

/// The first screen a new user sees. It walks the two macOS permissions one step at a time (see
/// `PermissionFlow`) and offers exactly two named exits in its bottom bar: quit, or grant. Reopened
/// later from "Check permissions…" with nothing left to resolve, grant becomes close.
///
/// There is deliberately no close box. The old window had one, and clicking it terminated the
/// app silently — users took it for "I'll deal with this later" and then wondered why AltTab was
/// gone. Losing the titlebar means losing the drag handle too, hence `isMovableByWindowBackground`.
class PermissionsWindow: NSWindow {
    static let contentWidth = CGFloat(470)
    private static let contentInset = CGFloat(22)
    static var shared: PermissionsWindow!
    /// Whether this launch displayed the permissions flow.
    static private(set) var wasWalkedThisLaunch = false
    override var canBecomeKey: Bool { SecondaryWindows.canBecomeKey }

    private var accessibilityView: PermissionView!
    private var screenRecordingView: PermissionView!
    private var primaryButton: NSButton!
    private var waiveView: NSView!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        delegate = self
        setupWindow()
        setupView()
        Self.shared = self
        Self.updatePermissionViews()
    }

    #if DEBUG
    /// Set by `QaSurfaces` to photograph the window as someone who has not granted anything sees it. Every
    /// permission check calls `updatePermissionViews`, so setting the views once would not hold.
    static var qaForcedStatus: PermissionStatus?
    #endif

    static func updatePermissionViews() {
        guard let window = Self.shared else { return }
        #if DEBUG
        if let forced = qaForcedStatus {
            window.render(forced, forced)
            return
        }
        #endif
        window.render(AccessibilityPermission.status, ScreenRecordingPermission.status)
    }

    /// "Grant permission" next to "Skipped", also reached from the menubar callout: the window shows Screen Recording
    /// live again, and macOS asks, or opens the pane if it already did.
    static func grantScreenRecording() {
        App.showPermissionsWindow()
        ScreenRecordingPermission.request()
        ScreenRecordingPermission.unwaive()
    }

    static func show() {
        guard !Self.shared.isVisible else { return }
        Logger.debug { "" }
        wasWalkedThisLaunch = true
        Self.shared.center()
        App.shared.activate(ignoringOtherApps: true)
        Self.shared.makeKeyAndOrderFront(nil)
    }

    private func setupWindow() {
        applySecondaryWindowChrome(NSLocalizedString("AltTab requires some permissions", comment: "Permissions window title"))
        isMovableByWindowBackground = true
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach {
            standardWindowButton($0)?.isHidden = true
        }
    }

    private func setupView() {
        let content = NSStackView(views: [makeHeader(), makeAccessibilityView(), makeScreenRecordingView()])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.setHuggingPriority(.defaultHigh, for: .vertical)
        let bar = makeBottomBar()
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubviews([content, bar])
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            content.topAnchor.constraint(equalTo: root.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.contentInset),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.contentInset),
            bar.topAnchor.constraint(equalTo: content.bottomAnchor, constant: 18),
            bar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            accessibilityView.widthAnchor.constraint(equalTo: content.widthAnchor),
            screenRecordingView.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])
        contentView = root
    }

    private func makeHeader() -> NSView {
        let iconSize = NSSize(width: 50, height: 50)
        let icon = LightImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.updateContents(.cgImage(App.appIcon(for: iconSize)), iconSize)
        icon.fit(iconSize.width, iconSize.height)
        let text = NSTextField(wrappingLabelWithString: title)
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 19.5, weight: .semibold)
        let header = NSStackView(views: [icon, text])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.spacing = 14
        header.alignment = .centerY
        return header
    }

    private func makeAccessibilityView() -> NSView {
        accessibilityView = PermissionView(
            1,
            Self.accessibilityPermissionName(),
            NSLocalizedString("AltTab requires this permission to focus windows for you.", comment: "Permissions window"),
            .accessibility)
        return accessibilityView
    }

    /// macOS 27 renamed the Accessibility list "Device Control and Data Access". The card keeps its first half: Grant
    /// lands the user on the list, so it only has to be recognizable there, and "Data Access" would promise more than
    /// AltTab uses. The translations are the first half of Apple's own, from the Privacy & Security pane.
    private static func accessibilityPermissionName() -> String {
        if #available(macOS 27.0, *) {
            return NSLocalizedString("Device Control", comment: "Name of the Accessibility permission since macOS 27: the first half of \"Device Control and Data Access\", as System Settings shows it")
        }
        return NSLocalizedString("Accessibility", comment: "")
    }

    private func makeScreenRecordingView() -> NSView {
        screenRecordingView = PermissionView(
            2,
            NSLocalizedString("Screen Recording", comment: ""),
            NSLocalizedString("AltTab requires this permission to show you pictures of each window.", comment: "Permissions window"),
            .screenRecording,
            onGrantAfterSkip: { Self.grantScreenRecording() })
        return screenRecordingView
    }

    private func makeBottomBar() -> NSView {
        let quit = Button(String(format: NSLocalizedString("Quit %@", comment: "%@ is AltTab"), App.name)) { _ in
            App.shared.terminate(nil)
        }
        quit.attributedTitle = NSAttributedString(string: quit.title, attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.systemFont(ofSize: 12.5, weight: .medium),
        ])
        primaryButton = Button(NSLocalizedString("Grant permission", comment: "Permissions window button")) { [weak self] _ in
            self?.performPrimaryAction()
        }
        primaryButton.keyEquivalent = "\r"
        waiveView = makeWaiveView()
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: 12).isActive = true
        let bar = PermissionsBottomBar(views: [quit, spacer, waiveView, primaryButton])
        // The spacer is the gap: the stack's spacing on both of its sides made the bar 11pt wider than the window
        bar.setCustomSpacing(0, after: quit)
        bar.setCustomSpacing(0, after: spacer)
        return bar
    }

    /// "Continue without thumbnails", with what it costs written underneath. Deliberately not a
    /// button: it is the weaker of the two paths and shouldn't look like the way forward.
    private func makeWaiveView() -> NSView {
        let link = Button(NSLocalizedString("Continue without thumbnails", comment: "Permissions window")) { _ in
            ScreenRecordingPermission.waive()
        }
        link.isBordered = false
        link.attributedTitle = NSAttributedString(string: link.title, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: 11.5),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        let warning = NSTextField(labelWithString: "⚠︎ " + NSLocalizedString("Windows will show as app icons", comment: "Permissions window"))
        warning.translatesAutoresizingMaskIntoConstraints = false
        warning.font = .systemFont(ofSize: 10.5)
        warning.textColor = .systemOrange
        let stack = NSStackView(views: [link, warning])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 2
        return stack
    }

    private func performPrimaryAction() {
        switch PermissionFlow.primaryAction(accessibility: AccessibilityPermission.status, screenRecording: ScreenRecordingPermission.status) {
            case .grant: grantLiveStep()
            case .close: close()
        }
    }

    private func grantLiveStep() {
        guard let step = PermissionFlow.liveStep(accessibility: AccessibilityPermission.status, screenRecording: ScreenRecordingPermission.status) else { return }
        Logger.debug { "\(step)" }
        switch step {
            case .accessibility: AccessibilityPermission.request()
            case .screenRecording: ScreenRecordingPermission.request()
        }
    }

    private func render(_ accessibility: PermissionStatus, _ screenRecording: PermissionStatus) {
        accessibilityView.update(PermissionFlow.state(of: .accessibility, accessibility: accessibility, screenRecording: screenRecording), accessibility,
            offersGrantAfterSkip: PermissionFlow.offersGrantAfterSkip(.accessibility, accessibility: accessibility, screenRecording: screenRecording))
        screenRecordingView.update(PermissionFlow.state(of: .screenRecording, accessibility: accessibility, screenRecording: screenRecording), screenRecording,
            offersGrantAfterSkip: PermissionFlow.offersGrantAfterSkip(.screenRecording, accessibility: accessibility, screenRecording: screenRecording))
        waiveView.isHidden = !PermissionFlow.showsWaiveOption(accessibility: accessibility, screenRecording: screenRecording)
        primaryButton.title = PermissionFlow.primaryAction(accessibility: accessibility, screenRecording: screenRecording) == .close
            ? NSLocalizedString("Close", comment: "Permissions window button")
            : NSLocalizedString("Grant permission", comment: "Permissions window button")
        contentView!.layoutSubtreeIfNeeded()
        setContentSize(contentView!.fittingSize)
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

extension PermissionsWindow: NSWindowDelegate {
    /// Reachable via Cmd-W and the Window menu even without a close button. Before the permissions
    /// pass, closing is the same decision as `Quit AltTab` — say so rather than quitting silently.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !SystemPermissions.preStartupPermissionsPassed else { return true }
        Logger.debug { "accessibility:\(AccessibilityPermission.status), screenRecording:\(ScreenRecordingPermission.status)" }
        App.shared.terminate(self)
        return false // prevent the close; termination will close everything once
    }
}

/// The bar holding the two exits: a hairline above it and a recessed fill, so it reads as window
/// chrome rather than as part of the steps.
private class PermissionsBottomBar: NSView {
    private let stack: NSStackView

    init(views: [NSView]) {
        stack = NSStackView(views: views)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.alignment = .centerY
        stack.spacing = 16
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
        ])
    }

    func setCustomSpacing(_ spacing: CGFloat, after view: NSView) {
        stack.setCustomSpacing(spacing, after: view)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}
