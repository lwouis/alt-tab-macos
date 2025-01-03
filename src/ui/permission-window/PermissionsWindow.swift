import Cocoa

class PermissionsWindow: NSWindow, NSWindowDelegate {
    var accessibilityView: PermissionView!
    var screenRecordingView: PermissionView!

    convenience init() {
        self.init(contentRect: .zero, styleMask: [.titled, .miniaturizable, .closable], backing: .buffered, defer: false)
        delegate = self
        setupWindow()
        setupView()
    }

    func show(_ startupBlock: @escaping () -> Void) {
        accessibilityView.updatePermissionStatus(SystemPermissions.accessibilityIsGranted())
        if #available(macOS 10.15, *) {
            screenRecordingView.updatePermissionStatus(SystemPermissions.screenRecordingIsGranted())
        }
        center()
        App.shared.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        if #available(macOS 10.15, *), !SystemPermissions.preStartupPermissionsPassed {
            // this call triggers the permission prompt, however it's the only way to force the app to be listed with a checkbox
            SLSRequestScreenCaptureAccess()
        }
        SystemPermissions.pollPermissionsToUpdatePermissionsWindow(startupBlock)
    }

    func windowWillClose(_ notification: Notification) {
        Logger.debug(SystemPermissions.preStartupPermissionsPassed)
        if !SystemPermissions.preStartupPermissionsPassed {
            if SystemPermissions.accessibilityIsGranted() == .notGranted || SystemPermissions.screenRecordingIsGranted() == .notGranted {
                Logger.error("Before using this app, you need to give permission in System Preferences > Security & Privacy > Privacy > Accessibility.",
                    "Please authorize and re-launch.",
                    "See https://help.rescuetime.com/article/59-how-do-i-enable-accessibility-permissions-on-mac-osx")
                App.shared.terminate(self)
            }
        } else {
            SystemPermissions.timerPermissionsToUpdatePermissionsWindow?.invalidate()
        }
    }

    private func setupWindow() {
        title = NSLocalizedString("AltTab needs some permissions", comment: "")
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        styleMask.insert([.miniaturizable, .closable])
    }

    private func setupView() {
        let appIcon = NSImageView(image: NSImage.initResizedCopy("app", 80, 80))
        appIcon.imageScaling = .scaleNone
        let appText = TitleLabel(NSLocalizedString("AltTab needs some permissions", comment: ""))
        appText.preferredMaxLayoutWidth = 380
        appText.font = .systemFont(ofSize: 25, weight: .regular)
        let header = NSStackView(views: [appIcon, appText])
        header.spacing = GridView.interPadding
        accessibilityView = PermissionView(
            "accessibility",
            NSLocalizedString("Accessibility", comment: ""),
            NSLocalizedString("This permission is needed to focus windows after you release the shortcut", comment: ""),
            NSLocalizedString("Open Accessibility Preferences…", comment: ""),
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            SystemPermissions.accessibilityIsGranted
        )
        var rows = [
            [header],
            [accessibilityView],
        ]
        if #available(macOS 10.15, *) {
            screenRecordingView = PermissionView(
                "screen-recording",
                NSLocalizedString("Screen Recording", comment: ""),
                NSLocalizedString("This permission is needed to show screenshots and titles of open windows", comment: ""),
                NSLocalizedString("Open Screen Recording Preferences…", comment: ""),
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
                SystemPermissions.screenRecordingIsGranted,
                StackView(LabelAndControl.makeLabelWithCheckbox(NSLocalizedString("Use the app without this permission. Thumbnails won’t show.", comment: ""), "screenRecordingPermissionSkipped", labelPosition: .right))
            )
            rows.append([screenRecordingView])
        }
        let view = GridView(rows as! [[NSView]])
        view.fit()
        setContentSize(view.fittingSize)
        contentView = view
    }
}
