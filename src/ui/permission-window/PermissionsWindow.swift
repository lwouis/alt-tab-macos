import Cocoa

class PermissionsWindow: NSWindow {
    static var accessibilityView: PermissionView!
    static var screenRecordingView: PermissionView!
    static var canBecomeKey_ = true
    override var canBecomeKey: Bool { Self.canBecomeKey_ }
    static var shared: PermissionsWindow!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        delegate = self
        setupWindow()
        setupView()
        setFrameAutosaveName("PermissionsWindow")
        Self.shared = self
    }

    static func updatePermissionViews() {
        accessibilityView.updatePermissionStatus(AccessibilityPermission.status)
        if #available(macOS 10.15, *) {
            screenRecordingView.updatePermissionStatus(ScreenRecordingPermission.status)
        }
    }

    static func show() {
        guard !Self.shared.isVisible else { return }
        Logger.debug { "" }
        Self.shared.center()
        App.shared.activate(ignoringOtherApps: true)
        Self.shared.makeKeyAndOrderFront(nil)
        SystemPermissions.setFrequentTimer()
    }

    private func setupWindow() {
        title = NSLocalizedString("AltTab needs some permissions", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.closable])
    }

    private func setupView() {
        let appIcon = LightImageView()
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.updateContents(.cgImage(App.appIcon), NSSize(width: 80, height: 80))
        appIcon.fit(80, 80)
        let appText = TitleLabel(NSLocalizedString("AltTab needs some permissions", comment: ""))
        appText.preferredMaxLayoutWidth = 380
        appText.font = .systemFont(ofSize: 25, weight: .regular)
        let header = NSStackView(views: [appIcon, appText])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.spacing = GridView.interPadding
        Self.accessibilityView = PermissionView(
            "accessibility",
            NSLocalizedString("Accessibility", comment: ""),
            NSLocalizedString("This permission is needed to focus windows after you release the shortcut", comment: ""),
            NSLocalizedString("Open Accessibility Settings…", comment: ""),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        )
        var rows = [
            [header],
            [Self.accessibilityView],
        ]
        if #available(macOS 10.15, *) {
            Self.screenRecordingView = PermissionView(
                "screen-recording",
                NSLocalizedString("Screen Recording", comment: ""),
                NSLocalizedString("This permission is needed to show thumbnails and preview of open windows", comment: ""),
                NSLocalizedString("Open Screen Recording Settings…", comment: ""),
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Use the app without this permission. Thumbnails won’t show.", comment: ""), "screenRecordingPermissionSkipped", labelPosition: .right))
            )
            rows.append([Self.screenRecordingView])
        }
        let widestRowWidth = rows.reduce(0) { max($0, $1[0]!.fittingSize.width) }
        rows.forEach { $0[0]!.fit(widestRowWidth, $0[0]!.fittingSize.height) }
        let view = GridView(rows as! [[NSView]])
        view.fit()
        setContentSize(view.fittingSize)
        contentView = view
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

extension PermissionsWindow: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        Logger.debug { "preStartupPermissionsPassed:\(SystemPermissions.preStartupPermissionsPassed), accessibility:\(AccessibilityPermission.status), screenRecording:\(ScreenRecordingPermission.status)" }
        if !SystemPermissions.preStartupPermissionsPassed {
            if AccessibilityPermission.status == .notGranted || ScreenRecordingPermission.status == .notGranted {
                Logger.error {
                    """
                    Before using this app, you need to give permission in System Settings > Privacy & Security > Accessibility.
                    Please authorize and re-launch.
                    See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx
                    """
                }
                App.shared.terminate(self)
                return false // prevent the close; termination will close everything once
            }
        }
        return true
    }
}
