import Cocoa

/// Buttons shared by the Pro-transition windows and popovers.
enum ProPromptButtons {
    /// The "Get Pro" call to action. Deliberately has no `keyEquivalent`: these prompts steal focus,
    /// so a stray Return must not trigger checkout (#5738).
    static func makeGetPro(large: Bool, _ onClick: @escaping () -> Void) -> NSButton {
        let button = NSButton(title: NSLocalizedString("Get Pro", comment: ""), target: nil, action: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        if large {
            if #available(macOS 11.0, *) { button.controlSize = .large }
        } else {
            button.controlSize = .small
        }
        button.onAction = { _ in onClick() }
        return button
    }
}

/// Base class for non-modal Pro-transition windows ([A] Welcome, [C] Full Upgrade, [D] Proactive,
/// [G] Final). Centralises the window chrome that every Day X window needs: hidden titlebar,
/// hidden traffic-light buttons, no hide-on-deactivate, no release-on-close. Subclasses set
/// their own `contentView` after calling the designated init.
class ProPromptWindow: NSWindow {
    convenience init(size: NSSize, miniaturizable: Bool = true, movableByBackground: Bool = false) {
        var mask: NSWindow.StyleMask = [.titled, .closable, .fullSizeContentView]
        if miniaturizable { mask.insert(.miniaturizable) }
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: mask, backing: .buffered, defer: false)
        title = NSLocalizedString("AltTab Pro", comment: "")
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = movableByBackground
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// The centred [header / usage hero / Get Pro / dismiss link] column shared by [C] Full Upgrade,
    /// [D] Proactive and [G] Final. Only the three spacings differ between them. Installs the result
    /// as `contentView` and shrink-wraps the height.
    func setHeroContentView(header: ProPromptHeader, hero: UsageStatHeroView, purchase: NSButton,
                            dismiss: NSButton, sidePadding: CGFloat, gap: CGFloat, dismissGap: CGFloat) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        [header, hero, purchase, dismiss].forEach { container.addSubview($0) }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            header.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            header.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: sidePadding),
            header.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -sidePadding),

            hero.topAnchor.constraint(equalTo: header.bottomAnchor, constant: gap),
            hero.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: sidePadding),
            hero.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -sidePadding),

            purchase.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: gap),
            purchase.centerXAnchor.constraint(equalTo: container.centerXAnchor),

            dismiss.topAnchor.constraint(equalTo: purchase.bottomAnchor, constant: dismissGap),
            dismiss.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            dismiss.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
        ])
        contentView = container
        fitContentHeight()
    }

    /// Shrink-wrap the window's height around its content. Called after building the content view, and
    /// again on every re-show: the singletons are reused, and their content (usage numbers, supporting
    /// lines) changes height between shows.
    func fitContentHeight() {
        guard let view = contentView else { return }
        view.layoutSubtreeIfNeeded()
        setContentSize(NSSize(width: view.frame.width, height: view.fittingSize.height))
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
