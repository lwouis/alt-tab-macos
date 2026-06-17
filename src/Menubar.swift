import Cocoa

class Menubar {
    static var statusItem: NSStatusItem!
    static var menu: NSMenu!
    static var permissionCalloutMenuItems: [NSMenuItem]?
    private static var permissionCallout: PermissionCallout?
    private static var upgradeToProMenuItem: NSMenuItem!
    private static var supportProjectMenuItem: NSMenuItem!
    private static var myAccountMenuItem: NSMenuItem!
    private static let menuDelegate = MenubarMenuDelegate()
    private static var isVisibleObserver: NSKeyValueObservation?

    @discardableResult
    static func addMenuItem(_ title: String, _ action: Selector, _ keyEquivalent: String, _ symbolName: String?, _ color: NSColor? = nil, _ target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        if #available(macOS 26.0, *), let symbolName {
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            if let color {
                item.image = item.image?.withSymbolConfiguration(.init(paletteColors: [color]))
            }
        }
        return item
    }

    static func initialize() {
        menu = NSMenu()
        menu.title = App.name // perf: prevent going through expensive code-path within appkit
        menu.delegate = menuDelegate
        let permissionCalloutMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let callout = PermissionCallout()
        permissionCallout = callout
        permissionCalloutMenuItem.view = callout
        let calloutSeparator = NSMenuItem.separator()
        permissionCalloutMenuItems = [permissionCalloutMenuItem, calloutSeparator]
        addMenuItem(NSLocalizedString("Show", comment: "Menubar option"), #selector(App.showUiFromShortcut0), "", "eye", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(NSLocalizedString("Settings…", comment: "Menubar option"), #selector(App.showSettingsWindow), ",", "gear", nil, App.self)
        addMenuItem(NSLocalizedString("Check for updates…", comment: "Menubar option"), #selector(App.checkForUpdatesNow), "", "checkmark.arrow.trianglehead.clockwise", nil, App.self)
        addMenuItem(NSLocalizedString("Check permissions…", comment: "Menubar option"), #selector(App.checkPermissions), "", "hand.raised", nil, App.self)
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("About %@", comment: "Menubar option. %@ is AltTab"), App.name), #selector(App.showAboutWindow), "", "info.circle", nil, App.self)
        addMenuItem(NSLocalizedString("Debug tools", comment: "Menubar option"), #selector(App.showDebugWindow), "", "scope", nil, App.self)
        addMenuItem(NSLocalizedString("Send feedback…", comment: "Menubar option"), #selector(App.showFeedbackPanel), "", "text.bubble", nil, App.self)
        upgradeToProMenuItem = addMenuItem(NSLocalizedString("Get Pro", comment: "Menubar option"), App.upgradeToProAction, "", "star.fill", nil, App.self)
        upgradeToProMenuItem.view = UpgradeMenuItemView()
        myAccountMenuItem = addMenuItem(NSLocalizedString("My Account", comment: ""), App.openAccountAction, "", "person.crop.circle", nil, App.self)
        supportProjectMenuItem = addMenuItem(NSLocalizedString("Support this project", comment: "Menubar option"), App.supportProjectAction, "", "heart.fill", .red, App.self)
        refreshLicenseMenuItems()
        menu.addItem(NSMenuItem.separator())
        addMenuItem(String(format: NSLocalizedString("Quit %@", comment: "%@ is AltTab"), App.name), #selector(NSApplication.terminate(_:)), "q", nil) // "xmark.rectangle" is not necessary; macos automatically recognizes Quit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.target = self
        statusItem.button!.action = #selector(statusItemOnClick)
        statusItem.button!.sendAction(on: [.leftMouseDown, .rightMouseDown])
        // Apply icon prefs eagerly here, while the status item is still being added to the
        // menubar. Doing it later (from PreferencesEvents.initialize) sets `button.image` after
        // the WindowServer has already laid the menubar out at its imageless default size, then
        // invalidates NSStatusBarContentView mid-FBS-scene-update — `_NSDetectedLayoutRecursion`.
        applyMenubarIconPreferences()
        observeRemovalFromMenubar()
        #if DEBUG
        installQAMenuMiddleClickMonitor()
        #endif
    }

    #if DEBUG
    private static var qaMenuMiddleClickMonitor: Any?

    // NSStatusBarButton doesn't forward `.otherMouseDown` to its action even when added to
    // `sendAction(on:)`. A local event monitor sees the click before the button can swallow it.
    private static func installQAMenuMiddleClickMonitor() {
        qaMenuMiddleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            guard event.buttonNumber == 2,
                  let buttonWindow = statusItem?.button?.window,
                  event.window === buttonWindow else { return event }
            QAMenu.toggleVisibility()
            return nil
        }
    }
    #endif

    static func refreshLicenseMenuItems() {
        guard upgradeToProMenuItem != nil else { return }
        let state = LicenseManager.shared.state
        switch state {
        case .trial:
            toggleUpgradeMenuItem(true)
            supportProjectMenuItem.isHidden = true
            myAccountMenuItem.isHidden = true
        case .pro:
            toggleUpgradeMenuItem(false)
            supportProjectMenuItem.isHidden = true
            myAccountMenuItem.isHidden = false
        case .proExpired:
            toggleUpgradeMenuItem(true)
            supportProjectMenuItem.isHidden = false
            myAccountMenuItem.isHidden = false
        case .trialExpired:
            toggleUpgradeMenuItem(true)
            supportProjectMenuItem.isHidden = false
            myAccountMenuItem.isHidden = true
        }
        if case .pro = state { return }
        (upgradeToProMenuItem.view as? UpgradeMenuItemView)?.updateContent(state)
    }

    private static func toggleUpgradeMenuItem(_ show: Bool) {
        if show && !menu.items.contains(upgradeToProMenuItem) {
            if let i = menu.items.firstIndex(of: supportProjectMenuItem) {
                menu.insertItem(upgradeToProMenuItem, at: i)
            }
        }
        if !show && menu.items.contains(upgradeToProMenuItem) {
            menu.removeItem(upgradeToProMenuItem)
        }
    }

    // The callout is only useful when the user lacks Screen Recording AND has settings that need it
    // (Thumbnails style or window previews). Users who skipped the permission but use neither aren't
    // nagged (see #5623). Its copy names whichever of the two features are actually affected, so we
    // refresh the text before showing it. Re-evaluated on permission ticks and on each menu open
    // (settings can change). Decision logic lives in `PermissionCalloutResolver` (unit-tested).
    static func refreshPermissionCallout() {
        let dependentFeatures = Preferences.screenRecordingDependentFeatures
        let show = PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: ScreenRecordingPermission.status == .granted,
            dependentFeatures: dependentFeatures)
        if show { permissionCallout?.update(dependentFeatures) }
        togglePermissionCallout(show)
    }

    // NSMenuItem.isHidden isn't reliable with custom views. We add/remove to hide/show these items
    static func togglePermissionCallout(_ show: Bool) {
        permissionCalloutMenuItems?.enumerated().forEach { offset, element in
            if show && !menu.items.contains(element) {
                menu.insertItem(element, at: offset)
            }
            if !show && menu.items.contains(element) {
                menu.removeItem(element)
            }
        }
    }

    @objc static func statusItemOnClick() {
        // NSApp.currentEvent == nil if the icon is "clicked" through VoiceOver
        if let type = NSApp.currentEvent?.type, type != .leftMouseDown {
            App.showUiFromShortcut0()
        } else {
            statusItem.popUpMenu(Menubar.menu)
        }
    }

    static func menubarIconCallback(_: NSControl?) {
        // Guard: can be invoked during `LicenseManager.initialize()` (e.g. Pro users where
        // `onStateChanged` → `ProTransitionManager.onLicenseStateChanged` fires before
        // `Menubar.setup()`), at which point `statusItem` is still nil.
        guard statusItem != nil else { return }
        applyMenubarIconPreferences()
        if let menubarIconDropdown = GeneralTab.menubarIconDropdown {
            menubarIconDropdown.isEnabled = Preferences.menubarIconShown
        }
    }

    static private func applyMenubarIconPreferences() {
        if Preferences.menubarIconShown {
            loadPreferredIcon()
        } else {
            statusItem.isVisible = false
        }
    }

    // The user can ⌘-drag the icon off the menubar (enabled by `.removalAllowed`). When that
    // happens, `isVisible` flips true→false and we persist the preference. Observing here in
    // `Menubar` rather than in `GeneralTab` means we react whether or not Settings is open.
    static private func observeRemovalFromMenubar() {
        statusItem.behavior = .removalAllowed
        isVisibleObserver = statusItem.observe(\.isVisible, options: [.old, .new]) { _, change in
            if change.oldValue == true && change.newValue == false {
                Preferences.set("menubarIconShown", "false")
                GeneralTab.menuIconShownToggle?.setSilently(.off)
            }
        }
    }

    private static var badgeDotLayer: CALayer?

    static private func loadPreferredIcon() {
        let i = Preferences.menubarIcon.indexAsString
        let image = NSImage(named: "menubar-\(i)")!
        image.isTemplate = i != "2"
        statusItem.button!.image = image
        statusItem.isVisible = true
        statusItem.button!.imageScaling = .scaleProportionallyUpOrDown
        updateBadgeDotOverlay()
    }

    // CALayer rather than NSView subview: adding an NSView to NSStatusBarButton triggers
    // NSStatusBarContentView layout cascades that race with FBSScene updates at launch,
    // tripping `_NSDetectedLayoutRecursion`. CALayers don't post frame-change notifications.
    static private func updateBadgeDotOverlay() {
        badgeDotLayer?.removeFromSuperlayer()
        badgeDotLayer = nil
        guard ProTransitionManager.shared.shouldShowBadgeDot, let button = statusItem?.button else { return }
        button.wantsLayer = true
        guard let buttonLayer = button.layer else { return }
        let dotSize: CGFloat = 7
        // Anchor to the icon's bottom-right corner (not the button bounds). The button is
        // typically taller than the icon — especially on macOS Tahoe — so positioning relative
        // to button.bounds leaves the dot in the empty space below the icon. `imageRect`
        // returns the icon's actual rendered rect in NSView coords (y up).
        let imageRect = button.cell?.imageRect(forBounds: button.bounds) ?? button.bounds
        // CALayer uses y-down (origin top-left); imageRect is in NSView y-up. Convert the
        // icon's bottom edge to layer space: `button.bounds.height - imageRect.minY`.
        let dot = CALayer()
        dot.frame = NSRect(
            x: imageRect.maxX - dotSize,
            y: button.bounds.height - imageRect.minY - dotSize,
            width: dotSize, height: dotSize)
        dot.backgroundColor = NSColor.systemOrange.cgColor
        dot.cornerRadius = dotSize / 2
        dot.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        dot.autoresizingMask = [.layerMinXMargin, .layerMinYMargin]
        buttonLayer.addSublayer(dot)
        badgeDotLayer = dot
    }

    static func showPopoverFromMenubar(_ popover: NSPopover) {
        guard let button = statusItem?.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

class UpgradeMenuItemView: NSView {
    /// Insets of the gradient backdrop relative to the menu row bounds. Sized to align with the
    /// rounded highlight rect AppKit draws on hover for the other menu rows; values live in
    /// `NSEdgeInsets` so the constraint code below stays free of inline pixel literals.
    private static let backdropInsets = NSEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)

    private let label = NSTextField(labelWithString: "")
    /// Auto-layout host for the gradient. Constrained to the row edges with `backdropInsets`,
    /// so the gradient layer (sized to `backdrop.bounds` in `layout()`) follows from the
    /// constraint system rather than from manual `bounds.insetBy(...)` math.
    private let backdrop = NSView()
    private var highlightObservation: NSKeyValueObservation?
    private let gradientLayer = ProGradient.makeLayer()
    private var isShining = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.wantsLayer = true
        gradientLayer.cornerRadius = 7
        gradientLayer.masksToBounds = true
        backdrop.layer?.addSublayer(gradientLayer)
        addSubview(backdrop)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.maximumNumberOfLines = 2
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBezeled = false
        label.alignment = .left
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addSubview(label)
        let icon = NSImageView()
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.image = NSImage.fromSymbol(.starFill, pointSize: 11)
        if #available(macOS 10.14, *) { icon.contentTintColor = .white }
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(icon)
        // match standard NSMenuItem icon+text positioning. Our font-rendered icons are tight
        // ink-bounds (no typographic padding around the glyph), so we centre the icon view
        // inside the same column AppKit reserves for sibling-row icons rather than leading-
        // align it — otherwise the glyph appears shifted ~3pt left of the other icons.
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: leadingAnchor, constant: 25),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 39),
        ])
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.backdropInsets.left),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.backdropInsets.right),
            backdrop.topAnchor.constraint(equalTo: topAnchor, constant: Self.backdropInsets.top),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.backdropInsets.bottom),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradientLayer.frame = backdrop.bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        highlightObservation = enclosingMenuItem?.observe(\.isHighlighted, options: [.new]) { [weak self] _, change in
            if change.newValue == true { self?.playShineAnimation() }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for ta in trackingAreas { removeTrackingArea(ta) }
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        playShineAnimation()
    }

    private func playShineAnimation() {
        guard !isShining else { return }
        let pillBounds = gradientLayer.bounds
        let shine = CAGradientLayer()
        shine.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.3).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        shine.locations = [0, 0.5, 1]
        shine.startPoint = CGPoint(x: 0, y: 0.5)
        shine.endPoint = CGPoint(x: 1, y: 0.5)
        shine.frame = CGRect(x: -pillBounds.width, y: 0, width: pillBounds.width, height: pillBounds.height)
        gradientLayer.addSublayer(shine)
        isShining = true
        let animation = CABasicAnimation(keyPath: "position.x")
        animation.fromValue = -pillBounds.width / 2
        animation.toValue = pillBounds.width + pillBounds.width / 2
        animation.duration = 0.6
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            shine.removeFromSuperlayer()
            self?.isShining = false
        }
        shine.add(animation, forKey: "shine")
        CATransaction.commit()
    }

    func updateContent(_ state: LicenseState) {
        // "Get Pro" matches the standard menubar item size; the trial subtitle matches the smaller,
        // dimmed-white styling used by the SettingsWindow upgrade button.
        let menuFontSize = NSFont.menuFont(ofSize: 0).pointSize
        let mainAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: menuFontSize, weight: .regular),
        ]
        let secondaryAttrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.8),
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        ]
        let trialText: String
        if case .trial(let daysRemaining) = state {
            trialText = String(format: NSLocalizedString("Trial: %d days remaining", comment: ""), daysRemaining)
        } else if case .proExpired = state {
            trialText = NSLocalizedString("License doesn't cover this version", comment: "")
        } else {
            trialText = NSLocalizedString("Trial expired", comment: "")
        }
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: trialText, attributes: secondaryAttrs))
        result.append(NSAttributedString(string: "\n", attributes: mainAttrs))
        result.append(NSAttributedString(string: NSLocalizedString("Get Pro", comment: "Menubar option"), attributes: mainAttrs))
        label.attributedStringValue = result
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        App.upgradeToPro()
    }
}

private final class MenubarMenuDelegate: NSObject, NSMenuDelegate {
    // Trial day count is baked into `LicenseManager.state`; recompute right before the menu
    // opens so the dropdown subtitle reflects the current clock instead of the launch-day value.
    func menuWillOpen(_ menu: NSMenu) {
        LicenseManager.shared.refreshState()
        Menubar.refreshPermissionCallout()
    }
}

class PermissionCallout: StackView {
    private var label: NSTextField!
    private var button: NSButton!

    convenience init() {
        let label = NSTextField(wrappingLabelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white
        label.preferredMaxLayoutWidth = 250
        label.isSelectable = false
        label.addOrUpdateConstraint(label.widthAnchor, 250)
        let button = NSButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.attributedTitle = NSAttributedString(string: NSLocalizedString("Grant permission", comment: "Menubar callout button"), attributes: [NSAttributedString.Key.foregroundColor: NSColor.white])
        self.init([label, button], .vertical, true, top: 8, right: 15, bottom: 10, left: 15)
        self.label = label
        self.button = button
        wantsLayer = true
        layer!.backgroundColor = NSColor.purple.cgColor
    }

    // NSControl target/action never fires inside an NSMenuItem custom view: the menu's modal
    // tracking loop swallows the click before the button's own mouse-tracking can call sendAction.
    // So we route the click through the container exactly like `UpgradeMenuItemView` — `hitTest`
    // keeps the button visual-only, and `mouseUp` runs the action and dismisses the menu. (#5771)
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) != nil ? self : nil
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard button.frame.contains(location) else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        Preferences.remove("screenRecordingPermissionSkipped")
        App.restart()
    }

    // Name only the feature(s) the user actually enabled, so we never promise back a feature they
    // don't use. The wrapped label's height depends on the message, so re-fit after setting it.
    func update(_ dependentFeatures: PermissionCalloutResolver.DependentFeatures) {
        label.stringValue = PermissionCallout.message(dependentFeatures)
        // The earlier fit() pinned our height with a required constraint sized for the previous
        // (initially empty) message. While it stays active, fittingSize keeps reporting that stale
        // height, so re-fitting can't grow to fit the new text and the last line clips. Drop the
        // self-imposed size constraints first so fit() measures the real content. (#5771)
        constraints.filter {
            ($0.firstAnchor == widthAnchor || $0.firstAnchor == heightAnchor) && $0.secondAnchor == nil
        }.forEach { $0.isActive = false }
        fit()
    }

    // One reusable sentence template + a feature subject inserted at `%@`, so translators localize the
    // shared sentence (and the spacing/punctuation between its two clauses) once and only the subject
    // varies. The Thumbnails subject reuses the existing appearance-style string, already translated
    // everywhere. `.none` is unreachable here — the callout is hidden when no feature needs it.
    static func message(_ dependentFeatures: PermissionCalloutResolver.DependentFeatures) -> String {
        let subject: String
        switch dependentFeatures {
            case .thumbnails: subject = NSLocalizedString("Thumbnails", comment: "")
            case .previews: subject = NSLocalizedString("Window previews", comment: "Menubar callout subject: the preview-selected-window feature")
            case .both: subject = NSLocalizedString("Thumbnails and window previews", comment: "Menubar callout subject")
            case .none: return ""
        }
        return String(format: NSLocalizedString("AltTab is running without Screen Recording permissions. %@ won’t show.", comment: "Menubar callout. %@ is one or more feature names, e.g. Thumbnails"), subject)
    }
}
