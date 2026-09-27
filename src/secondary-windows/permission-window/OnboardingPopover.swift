import Cocoa
import Carbon.HIToolbox
import ShortcutRecorder

/// The end of the first-run flow, off the menubar icon, in two beats. First it hands over the
/// shortcut and waits for it to be used, lighting each key as the user presses it. It steps aside
/// while the switcher is up, then comes back as "That's it": the shortcut restated, the trial
/// announced when it stands in for the welcome letter, and one button into Settings.
///
/// Neither beat can be dismissed: the only way past the first is the shortcut, the only way past the
/// second is the button. Each beat activates AltTab and makes the popover key, since a popover washes
/// out whenever it isn't. For the second beat, that takes focus back from the window the switcher
/// just focused; the user leaves it with a click on the button anyway.
enum OnboardingPopover {
    private static var popover: AnchoredPopover?
    private static var stage = Stage.waitingForShortcut
    private static var trialDaysToAnnounce: Int?
    private static var keyMonitors = [Any]()
    private static var pendingDone: DispatchWorkItem?
    private static weak var holdKey: KeycapView?
    private static weak var nextKey: KeycapView?
    private static weak var tick: SuccessTickView?

    /// Returns false before the menubar exists, so the caller can fall back. A hidden or unplaced icon is not a
    /// reason to: the popover then shows under the menu bar (`StatusItemAnchor`).
    static func show(trialDaysToAnnounce: Int?) -> Bool {
        guard Menubar.statusItem != nil else {
            Logger.debug { "no menubar yet" }
            return false
        }
        close()
        Self.trialDaysToAnnounce = trialDaysToAnnounce
        if UserDefaults.standard.bool(forKey: "onboardingShortcutUsed") {
            stage = .done
            presentCompletion()
        } else {
            Self.popover = makePopover()
            stage = .waitingForShortcut
            present(makeTryItView())
            startKeyFeedback()
        }
        return true
    }

    /// Called at every summon and every cycling keystroke, where the checks are the whole cost on
    /// every launch that never saw the popover. The switcher showing up is the proof the shortcut
    /// landed. Either beat steps aside so a late presentation cannot cover the switcher. Closing
    /// can be a round trip to the window server, so it waits for the frame the user is waiting for.
    static func switcherWasSummoned() {
        if stage == .switcherOpen { pendingDone?.cancel(); return }
        guard let popover else { return }
        stage = .switcherOpen
        stopKeyFeedback()
        popover.cancelPresentation()
        DispatchQueue.main.async {
            guard Self.popover === popover, stage == .switcherOpen else { return }
            popover.close()
        }
    }

    /// Called from the end of every dismissal. The second beat waits a second after the switcher is
    /// gone, so the window it focused settles before the popover takes focus back. Summoning the
    /// switcher again within that second restarts the wait.
    static func switcherWasDismissed() {
        guard let popover, stage == .switcherOpen else { return }
        pendingDone?.cancel()
        let item = DispatchWorkItem {
            guard Self.popover === popover, stage == .switcherOpen else { return }
            stage = .done
            presentCompletion()
        }
        pendingDone = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private static func presentCompletion() {
        popover?.close()
        popover = makePopover()
        Preferences.set("onboardingShortcutUsed", "true", false)
        present(makeDoneView(trialDaysToAnnounce)) {
            if trialDaysToAnnounce != nil { ProTransitionManager.shared.hasSeenWelcome = true }
            celebrate()
        }
    }

    private static func makePopover() -> AnchoredPopover {
        let popover = AnchoredPopover()
        popover.behavior = .applicationDefined
        popover.delegate = UndismissablePopover.shared
        return popover
    }

    private static func present(_ content: NSView, onShown: (() -> Void)? = nil) {
        guard let popover, let item = Menubar.statusItem else { return }
        popover.present(content, from: item, onShown: onShown)
    }

    /// The check mark springs in and throws confetti, past the popover's edges.
    private static func celebrate() {
        guard let tick, let window = tick.window, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        tick.pop()
        ConfettiBurst.fire(around: window.convertToScreen(tick.convert(tick.bounds, to: nil)), above: window)
    }

    fileprivate static func chooseStyle() {
        close()
        Preferences.markSettingsWindowShownOnFirstLaunch()
        ProTransitionManager.shared.state.onboardingInProgress = false
        ProTransitionManager.shared.onAppLaunchComplete()
        App.showAndCenterSettingsWindow()
        SettingsWindow.shared?.navigateToSection("appearance")
    }

    private static func close() {
        pendingDone?.cancel()
        pendingDone = nil
        stopKeyFeedback()
        popover?.close()
        popover = nil
    }

    /// Global monitors see presses while another app is frontmost, local ones while AltTab is.
    /// Both only run during the first beat.
    private static func startKeyFeedback() {
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        keyMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: events) { refreshKeys($0) },
            NSEvent.addLocalMonitorForEvents(matching: events) { refreshKeys($0); return $0 },
        ].compactMap { $0 }
    }

    private static func stopKeyFeedback() {
        keyMonitors.forEach { NSEvent.removeMonitor($0) }
        keyMonitors = []
    }

    private static func refreshKeys(_ event: NSEvent) {
        let holdFlags = Preferences.holdShortcut[safe: 0].flatMap { $0 }?.modifierFlags ?? .option
        holdKey?.isPressed = !holdFlags.isEmpty && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: holdFlags)
        guard event.type != .flagsChanged else { return }
        let nextKeyCode = Preferences.nextWindowShortcut[safe: 0].flatMap { $0 }?.carbonKeyCode ?? UInt32(kVK_Tab)
        guard UInt32(event.keyCode) == nextKeyCode else { return }
        nextKey?.isPressed = event.type == .keyDown
    }

    /// First beat: the shortcut as two keycaps, and nothing to click.
    private static func makeTryItView() -> NSView {
        let title = OnboardingLayout.title(NSLocalizedString("AltTab is ready", comment: "Onboarding popover"))
        let hold = KeycapWithCaption(NSLocalizedString("hold", comment: "Onboarding popover, above the key to keep down"), OnboardingLayout.holdGlyphs)
        let plus = OnboardingLayout.plusSign()
        let press = KeycapWithCaption(NSLocalizedString("press", comment: "Onboarding popover, above the key to press"), OnboardingLayout.nextGlyphs)
        holdKey = hold.key
        nextKey = press.key
        let keys = NSStackView(views: [hold, plus, press])
        keys.translatesAutoresizingMaskIntoConstraints = false
        keys.alignment = .bottom
        keys.spacing = 10
        plus.centerYAnchor.constraint(equalTo: hold.key.centerYAnchor).isActive = true
        let stack = NSStackView(views: [title, keys, OnboardingLayout.tryItNow()])
        stack.spacing = 16
        return OnboardingLayout.root(stack)
    }

    /// Second beat: confirms the keypress landed, announces the trial, and leads into Settings.
    private static func makeDoneView(_ trialDays: Int?) -> NSView {
        let title = OnboardingLayout.title(NSLocalizedString("That's it", comment: "Onboarding popover, once the shortcut was used"))
        let reminder = pressAnyTime()
        let button = AccentButton(NSLocalizedString("Choose a style", comment: "Onboarding popover; opens Settings on Appearance")) {
            chooseStyle()
        }
        let trial = trialDays.map { TrialCard($0) }
        let tick = SuccessTickView()
        Self.tick = tick
        let stack = NSStackView(views: [tick, title, reminder, trial, button].compactMap { $0 })
        stack.spacing = 8
        stack.setCustomSpacing(14, after: stack.views[0])
        stack.setCustomSpacing(14, after: title)
        stack.setCustomSpacing(18, after: reminder)
        if let trial {
            trial.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        stack.setCustomSpacing(22, after: trial ?? reminder)
        // wider when the sentence needs it (French, Russian), rather than cutting it off
        return OnboardingLayout.root(stack, width: max(290, reminder.fittingSize.width + 2 * OnboardingLayout.horizontalInset))
    }

    /// "Press [⌥ Option] + [⇥ Tab] any time.", the user's own keys as small keycaps between the two
    /// halves of the sentence.
    private static func pressAnyTime() -> NSView {
        let template = NSLocalizedString("Press %@ any time.", comment: "Onboarding popover, once the shortcut was used; %@ is the keyboard shortcut")
        let halves = template.components(separatedBy: "%@")
        let keys = [OnboardingLayout.holdGlyphs, OnboardingLayout.nextGlyphs].map {
            KeycapView($0, name: OnboardingLayout.keyName($0), scale: .small)
        }
        let words = [halves.first, halves.count > 1 ? halves.last : nil].map { half -> NSTextField? in
            guard let half = half?.trimmingCharacters(in: .whitespaces), !half.isEmpty else { return nil }
            let label = NSTextField(labelWithString: half)
            label.font = .systemFont(ofSize: 15)
            label.textColor = .secondaryLabelColor
            return label
        }
        let plus = NSTextField(labelWithString: "+")
        plus.font = .systemFont(ofSize: 13)
        plus.textColor = .tertiaryLabelColor
        let row = NSStackView(views: [words[0], keys[0], plus, keys[1], words[1]].compactMap { $0 })
        row.translatesAutoresizingMaskIntoConstraints = false
        row.alignment = .centerY
        row.spacing = 6
        // "Drücke jederzeit %@." leaves a lone period, which belongs against the key
        if let last = words[1], last.stringValue.allSatisfy(\.isPunctuation) { row.setCustomSpacing(2, after: keys[1]) }
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.staticText)
        row.setAccessibilityLabel(String(format: template, OnboardingLayout.holdGlyphs + OnboardingLayout.nextGlyphs))
        return row
    }
}

/// Esc and clicks elsewhere ask the delegate first; `close()` doesn't.
private class UndismissablePopover: NSObject, NSPopoverDelegate {
    static let shared = UndismissablePopover()

    func popoverShouldClose(_ popover: NSPopover) -> Bool { false }
}

private enum Stage {
    case waitingForShortcut
    case switcherOpen
    case done
}

private enum OnboardingLayout {
    static let horizontalInset = CGFloat(24)

    static func title(_ text: String) -> NSTextField {
        let title = NSTextField(labelWithString: text)
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        return title
    }

    /// `width` nil hugs the content. The second beat needs one: its wrapping trial text has no width
    /// of its own.
    static func root(_ stack: NSStackView, width: CGFloat? = nil) -> NSView {
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .centerX
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: horizontalInset),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -horizontalInset),
        ])
        width.map { root.widthAnchor.constraint(equalToConstant: $0).isActive = true }
        return root
    }

    static func plusSign() -> NSTextField {
        let plus = NSTextField(labelWithString: "+")
        plus.translatesAutoresizingMaskIntoConstraints = false
        plus.font = .systemFont(ofSize: 15)
        plus.textColor = .tertiaryLabelColor
        return plus
    }

    static func tryItNow() -> NSView {
        let dot = DotView(color: .systemGreen, diameter: 7)
        let label = NSTextField(labelWithString: NSLocalizedString("Try it right now", comment: "Onboarding popover"))
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        let row = NSStackView(views: [dot, label])
        row.translatesAutoresizingMaskIntoConstraints = false
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    /// The user's own glyphs: an unfinished first launch can resume after the shortcut was customized.
    static var holdGlyphs: String { Preferences.holdShortcut[safe: 0].flatMap { $0 }?.description ?? "⌥" }
    static var nextGlyphs: String { Preferences.nextWindowShortcut[safe: 0].flatMap { $0 }?.description ?? "⇥" }

    /// A lone modifier or Tab spelled out, since ⌥ alone means nothing to many new users. English and
    /// lowercase in every language: Apple prints control, option and command that way on the
    /// keyboards of every country. Most non-US keyboards show only a symbol for tab and shift; they
    /// are spelled out anyway, for the same reason as ⌥.
    static func keyName(_ glyphs: String) -> String? {
        ["⌘": "command", "⌥": "option", "⌃": "control", "⇧": "shift", "⇥": "tab"][glyphs]
    }
}

/// The trial, announced the moment the switcher has just worked. It replaces the welcome letter for
/// new users, so it carries the letter's one promise: the switcher itself stays free.
private class TrialCard: NSView {
    private let gradient = ProGradient.makeLayer(alpha: 0.12)

    init(_ days: Int) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer!.cornerRadius = 8
        layer!.masksToBounds = true
        layer!.addSublayer(gradient)
        let title = NSTextField(wrappingLabelWithString: String(format: NSLocalizedString("%d days of AltTab Pro, starting now", comment: "Onboarding popover; %d is the trial length in days"), days))
        title.translatesAutoresizingMaskIntoConstraints = false
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        let body = NSTextField(wrappingLabelWithString: NSLocalizedString("Everything is unlocked while it runs. After that, the switcher keeps working exactly as it does now, and the Pro extras step back.", comment: "Onboarding popover, under the trial announcement"))
        body.translatesAutoresizingMaskIntoConstraints = false
        body.font = .systemFont(ofSize: 11)
        body.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [title, body])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }
}

/// Always blue: AppKit only draws a default button blue in the key window, and the popover stops
/// being key as soon as the user clicks elsewhere. Return still triggers it while the popover is key.
/// It accepts the first click, which would otherwise only activate AltTab.
private class AccentButton: NSButton {
    private static let padding = NSSize(width: 16, height: 6)
    override var wantsUpdateLayer: Bool { true }

    convenience init(_ title: String, _ onClick: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        onAction = { _ in onClick() }
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        keyEquivalent = "\r"
        wantsLayer = true
        layer!.cornerRadius = 7
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ])
    }

    override var intrinsicContentSize: NSSize {
        let title = attributedTitle.size()
        return NSSize(width: ceil(title.width) + 2 * Self.padding.width, height: ceil(title.height) + 2 * Self.padding.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateLayer() {
        layer!.backgroundColor = (isHighlighted ? NSColor.controlAccentColor.shadow(withLevel: 0.2)! : NSColor.controlAccentColor).cgColor
    }
}

/// "hold" above a keycap.
private class KeycapWithCaption: NSStackView {
    private(set) var key: KeycapView!

    convenience init(_ caption: String, _ glyphs: String) {
        let label = NSTextField(labelWithString: caption)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let key = KeycapView(glyphs, name: OnboardingLayout.keyName(glyphs), scale: .large)
        self.init(views: [label, key])
        self.key = key
        translatesAutoresizingMaskIntoConstraints = false
        orientation = .vertical
        alignment = .centerX
        spacing = 5
    }
}

/// A key with its symbol on top and its name along the bottom, both centered. Drawn like the search
/// hint's keycap: a face with a thin outline, lifted by a thicker bottom edge. Pressed, the face
/// sinks onto that edge and lights up in the accent color.
private class KeycapView: NSView {
    struct Scale {
        let minSize: NSSize
        let glyphFont: NSFont
        let nameFont: NSFont
        let inset: CGFloat
        let cornerRadius: CGFloat
        let lift: CGFloat
        static let large = Scale(minSize: NSSize(width: 64, height: 52), glyphFont: .systemFont(ofSize: 14), nameFont: .systemFont(ofSize: 11),
            inset: 7, cornerRadius: 7, lift: 2)
        static let small = Scale(minSize: NSSize(width: 40, height: 38), glyphFont: .systemFont(ofSize: 12), nameFont: .systemFont(ofSize: 10),
            inset: 4, cornerRadius: 5, lift: 1.5)
    }

    private let scale: Scale
    private let glyph: NSTextField
    private let name: NSTextField?
    /// Every label constraint whose constant follows the face as it sinks.
    private var sinkingConstraints = [(NSLayoutConstraint, CGFloat)]()
    var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            sinkingConstraints.forEach { $0.0.constant = $0.1 + (isPressed ? scale.lift / 2 : 0) }
            refreshTextColors()
            needsDisplay = true
        }
    }

    init(_ glyphs: String, name: String?, scale: Scale) {
        self.scale = scale
        glyph = NSTextField(labelWithString: glyphs)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        // the system font draws ⇥ visibly smaller than the modifier symbols next to it
        glyph.font = glyphs == "⇥" ? scale.glyphFont.withSize(scale.glyphFont.pointSize * 1.15) : scale.glyphFont
        self.name = name.map { NSTextField(labelWithString: $0) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(glyph)
        // as narrow as the name allows: without an intrinsic width, a stack view would stretch the key
        let narrowest = widthAnchor.constraint(equalToConstant: scale.minSize.width)
        // below the name's resistance to being cut, which is `.defaultHigh` too
        narrowest.priority = .defaultHigh - 1
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: scale.minSize.width),
            narrowest,
            heightAnchor.constraint(equalToConstant: scale.minSize.height),
        ])
        if let label = self.name { layOutGlyphAndName(label) } else { layOutGlyphAlone() }
        refreshTextColors()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    /// Offsets are from the view's edges; the unpressed face starts 1pt in, and ends `lift` above the bottom.
    private func layOutGlyphAndName(_ label: NSTextField) {
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = scale.nameFont
        addSubview(label)
        let glyphTop = glyph.topAnchor.constraint(equalTo: topAnchor, constant: 1 + scale.inset)
        let nameBottom = label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(1 + scale.lift + scale.inset))
        sinkingConstraints = [(glyphTop, glyphTop.constant), (nameBottom, nameBottom.constant)]
        NSLayoutConstraint.activate([
            glyphTop,
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            nameBottom,
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 1 + scale.inset + 2),
        ])
    }

    /// Glyphs with no single name (a combination, a letter) sit in the middle, like a letter key's.
    private func layOutGlyphAlone() {
        let centerY = glyph.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -scale.lift / 2)
        sinkingConstraints = [(centerY, centerY.constant)]
        NSLayoutConstraint.activate([
            centerY,
            glyph.centerXAnchor.constraint(equalTo: centerXAnchor),
            glyph.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 1 + scale.inset),
        ])
    }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let r = scale.cornerRadius
        let edge = NSRect(x: 1, y: 1, width: bounds.width - 2, height: bounds.height - 2 - scale.lift)
        let face = edge.offsetBy(dx: 0, dy: isPressed ? scale.lift / 2 : scale.lift)
        NSColor(calibratedWhite: 0, alpha: dark ? 0.5 : 0.28).setFill()
        NSBezierPath(roundedRect: edge, xRadius: r, yRadius: r).fill()
        let facePath = NSBezierPath(roundedRect: face, xRadius: r, yRadius: r)
        (isPressed ? NSColor.controlAccentColor : NSColor(calibratedWhite: dark ? 0.32 : 1, alpha: 1)).setFill()
        facePath.fill()
        NSColor(calibratedWhite: dark ? 0.42 : 0.8, alpha: 1).setStroke()
        facePath.lineWidth = 0.75
        facePath.stroke()
    }

    private func refreshTextColors() {
        glyph.textColor = isPressed ? .white : .labelColor
        name?.textColor = isPressed ? .white : .secondaryLabelColor
    }
}

private class DotView: NSView {
    private let color: NSColor

    init(color: NSColor, diameter: CGFloat) {
        self.color = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: diameter),
            heightAnchor.constraint(equalToConstant: diameter),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// The green circle with the checkmark.
private class SuccessTickView: NSView {
    private static let diameter = CGFloat(50)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.diameter),
            heightAnchor.constraint(equalToConstant: Self.diameter),
        ])
    }

    /// Springs in from small, about its center. The transform applies about the layer's anchor,
    /// which AppKit keeps at the corner, so the scale is wrapped in a move to the center and back.
    /// Scale and move are both linear in the scale factor, so the spring interpolates them exactly.
    func pop() {
        guard let layer else { return }
        let center = CGPoint(x: bounds.width * (0.5 - layer.anchorPoint.x), y: bounds.height * (0.5 - layer.anchorPoint.y))
        let toCenter = CATransform3DMakeTranslation(-center.x, -center.y, 0)
        let small = CATransform3DConcat(CATransform3DConcat(toCenter, CATransform3DMakeScale(0.4, 0.4, 1)), CATransform3DInvert(toCenter))
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: small)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.damping = 9
        spring.stiffness = 180
        spring.initialVelocity = 6
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: bounds).fill()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: bounds.width * 0.30, y: bounds.height * 0.52))
        check.line(to: NSPoint(x: bounds.width * 0.44, y: bounds.height * 0.36))
        check.line(to: NSPoint(x: bounds.width * 0.72, y: bounds.height * 0.66))
        check.lineWidth = 4
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor.white.setStroke()
        check.stroke()
    }
}
