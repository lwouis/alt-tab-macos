import Cocoa

class PermissionsWindow: NSWindow {
    var accessibilityView: PermissionView!
    var screenRecordingView: PermissionView!
    var canBecomeKey_ = true
    override var canBecomeKey: Bool { canBecomeKey_ }

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .miniaturizable, .closable], backing: .buffered, defer: false)
        delegate = self
        setupWindow()
        setupView()
    }

    func show() {
        guard !isVisible else { return }
        Logger.debug { "" }
        SystemPermissions.setFrequentTimer()
        updatePermissionViews()
        center()
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func updatePermissionViews() {
        guard isVisible else { return }
        accessibilityView.updatePermissionStatus(AccessibilityPermission.status)
        if #available(macOS 10.15, *) {
            screenRecordingView.updatePermissionStatus(ScreenRecordingPermission.status)
        }
    }

    private func setupWindow() {
        title = NSLocalizedString("AltTab needs some permissions", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
    }

    private func setupView() {
        let appIcon = LightImageView()
        appIcon.updateWithResizedCopy(App.appIcon, NSSize(width: 80, height: 80))
        appIcon.fit(80, 80)
        let appText = TitleLabel(NSLocalizedString("AltTab needs some permissions", comment: ""))
        appText.preferredMaxLayoutWidth = 380
        appText.font = .systemFont(ofSize: 25, weight: .regular)
        let header = NSStackView(views: [appIcon, appText])
        header.translatesAutoresizingMaskIntoConstraints = false
        header.spacing = GridView.interPadding
        accessibilityView = PermissionView(
            "accessibility",
            NSLocalizedString("Accessibility", comment: ""),
            NSLocalizedString("This permission is needed to focus windows after you release the shortcut", comment: ""),
            NSLocalizedString("Open Accessibility Settings…", comment: ""),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            AccessibilityPermission.update
        )
        var rows = [
            [header],
            [accessibilityView],
        ]
        if #available(macOS 10.15, *) {
            screenRecordingView = PermissionView(
                "screen-recording",
                NSLocalizedString("Screen Recording", comment: ""),
                NSLocalizedString("This permission is needed to show thumbnails and preview of open windows", comment: ""),
                NSLocalizedString("Open Screen Recording Settings…", comment: ""),
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                ScreenRecordingPermission.update,
                StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Use the app without this permission. Thumbnails won’t show.", comment: ""), "screenRecordingPermissionSkipped", labelPosition: .right))
            )
            rows.append([screenRecordingView])
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
        SystemPermissions.setInfrequentTimer()
        return true
    }
}