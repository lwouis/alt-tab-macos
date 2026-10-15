import Cocoa

/// Buttons shared by the Pro-transition windows and popovers.
enum ProPromptButtons {
    /// The "Get Pro" call to action. Deliberately has no `keyEquivalent`: a prompt can receive residual keys,
    /// so a stray Return must not trigger checkout (#5738).
    static func makeGetPro(_ onClick: @escaping () -> Void) -> NSButton {
        makePrimary(NSLocalizedString("Get Pro", comment: ""), onClick)
    }

    static func makePrimary(_ title: String, _ onClick: @escaping () -> Void) -> NSButton {
        let button = ProPrimaryButton(title: title, target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.bezelColor = .controlAccentColor
        button.controlSize = .large
        button.keyEquivalent = ""
        button.onAction = { _ in onClick() }
        return button
    }
}

/// Base class for the non-modal Pro-transition windows ([C] Full Upgrade, [G] Final). They ask for a choice, so
/// the window itself offers no way out: no close or minimize (buttons or shortcuts), and Escape does nothing.
/// Their own buttons close them. Subclasses set their own `contentView` after calling the designated init.
class ProPromptWindow: NSWindow {
    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        title = NSLocalizedString("AltTab Pro", comment: "")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// Shrink-wrap the window's height around its content. Called after building the content view, and
    /// again when a tab changes, since its heading can wrap differently.
    func fitContentHeight() {
        guard let view = contentView else { return }
        view.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: view.frame.width, height: view.fittingSize.height))
    }

    override func cancelOperation(_: Any?) {}
}

/// Blue comes from `bezelColor`, not from being the default button, so Return has no meaning here.
final class ProPrimaryButton: NSButton {
    override func keyDown(with event: NSEvent) {
        // Even a keyboard-focused button must not interpret residual Return as a purchase or style choice.
        guard event.keyCode != 36 && event.keyCode != 76 else { return }
        super.keyDown(with: event)
    }
}
