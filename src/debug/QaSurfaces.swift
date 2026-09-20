#if DEBUG
import Cocoa

// Every window, sheet, popover, alert and menu AltTab can put on screen, opened by id for the QA suite's
// visual non-regression test (VR-01). The suite photographs each one and compares it with the
// picture the maintainer last accepted, so what matters here is that the same id shows the same pixels on
// every run, unless AltTab itself changed.
//
// The suite drives it through the CLI port (`CliServer`):
//   --qa-surfaces        the ids, and the license states each one is worth photographing in
//   --qa-look=<l>        light or dark, for the whole app
//   --qa-license=<s>     trial, expired or pro
//   --qa-open=<id>       put that surface on screen, closing whatever the previous one left
//   --qa-shown           the window numbers to photograph, and how many pages of scrolling it holds
//   --qa-page=<n>        scroll the surface to its n-th page (0-based)
//   --qa-close           put everything away
//
// Whatever would change between two runs is held still, so a difference in the pictures is a difference in
// AltTab: the usage numbers are pinned, the update check answers "up to date" without the network, the Pro
// prompts are marked seen so none schedules itself mid-run, windows open at their default size rather than
// the one they were last left at, and no text field keeps a blinking caret.
enum QaSurfaces {
    struct Info: Codable {
        let id: String
        /// Nil for "all three": most surfaces look the same in every license state, but that is exactly the
        /// kind of thing the suite is there to notice.
        let licenses: [String]?
    }

    struct Shown: Codable {
        let wids: [UInt32]
        let pages: Int
    }

    /// The stretch of a scroll view's (flipped) document one surface covers, photographed a screenful at a time.
    struct Pager {
        let scrollView: NSScrollView
        let top: CGFloat
        let bottom: CGFloat

        var pages: Int {
            let height = scrollView.contentView.bounds.height
            guard height > 0 else { return 1 }
            return max(1, Int(((bottom - top) / height - 0.01).rounded(.up)))
        }

        func scroll(to page: Int) {
            let clip = scrollView.contentView
            let docHeight = scrollView.documentView?.frame.height ?? 0
            let y = max(0, min(top + CGFloat(page) * clip.bounds.height, docHeight - clip.bounds.height))
            clip.scroll(to: NSPoint(x: 0, y: y))
            scrollView.reflectScrolledClipView(clip)
            // Overlay scrollers fade on their own clock; the contents underneath are what this page records.
            scrollView.verticalScroller?.alphaValue = 0
        }
    }

    /// What `--qa-shown` photographs: the windows the surface named, or failing that whatever appeared on
    /// screen after it was asked for (popovers, alerts and menus are windows nobody keeps a reference to).
    private struct Target {
        var windows: (() -> [NSWindow])?
        var pager: (() -> Pager?)?
    }

    private struct Surface {
        let id: String
        let licenses: [String]?
        /// Surfaces that live in the Settings window keep it open between them, rather than rebuilding it.
        let inSettings: Bool
        let open: () -> Target
    }

    private static let trial = ["trial"]
    private static let expired = ["expired"]
    private static var current: Target?
    private static var currentId: String?
    private static var windowsBefore = Set<UInt32>()
    private static var popovers = NSHashTable<NSPopover>.weakObjects()
    private static var observingPopovers = false
    private static var renderGeneration = 0
    private static var settlingGeneration: Int?
    private static var readyGeneration: Int?

    /// The reply to one of the commands above, or nil for a command that is not one of them.
    static func command(_ raw: String) -> Codable? {
        switch raw {
            case "--qa-surfaces": return list()
            case "--qa-shown": return shown()
            case "--qa-close": closeAll(); return CliServer.noOutput
            default: break
        }
        let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
            case "--qa-open": return open(parts[1]) ? CliServer.noOutput : CliServer.error
            case "--qa-look": setLook(parts[1])
            case "--qa-license": setLicense(parts[1])
            case "--qa-page": page(Int(parts[1]) ?? 0)
            default: return nil
        }
        return CliServer.noOutput
    }

    static func list() -> [Info] {
        ProGradient.animationsDisabledForQa = true
        observePopovers()
        disableAnimations()
        return surfaces.map { Info(id: $0.id, licenses: $0.licenses) }
    }

    static func open(_ id: String) -> Bool {
        guard let surface = surfaces.first(where: { $0.id == id }) else { return false }
        observePopovers()
        pinVolatileContent()
        closeAll(keepSettings: surface.inSettings)
        currentId = id
        let generation = renderGeneration
        if id != "switcher" { App.shared.activate(ignoringOtherApps: true) }
        if surface.inSettings { SettingsWindow.shared?.disableScreenUpdatesUntilFlush() }
        windowsBefore = Set(onScreenWindowNumbers())
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            current = surface.open()
        }
        disableAnimations()
        current?.windows?().forEach { prepareForRendering($0, generation) }
        return true
    }

    static func shown() -> Shown {
        disableAnimations()
        let windows = current?.windows?() ?? []
        let pages = current?.pager?()?.pages ?? 1
        let wids = windows.isEmpty
            ? onScreenWindowNumbers().filter { !windowsBefore.contains($0) }
            : windows.filter { $0.isVisible }.compactMap { UInt32(exactly: $0.windowNumber) }
        let numbered = NSApp.windows.compactMap { window in
            UInt32(exactly: window.windowNumber).map { ($0, window) }
        }
        let byNumber = Dictionary(numbered, uniquingKeysWith: { first, _ in first })
        let generation = renderGeneration
        guard !wids.isEmpty else { return Shown(wids: [], pages: pages) }
        if readyGeneration != generation {
            if settlingGeneration != generation {
                let renderedWindows = windows.isEmpty ? wids.compactMap { byNumber[$0] } : windows
                renderedWindows.forEach { prepareForRendering($0, generation) }
                if currentId != "switcher", let front = wids.first.flatMap({ byNumber[$0] }) {
                    App.shared.activate(ignoringOtherApps: true)
                    front.makeKey()
                    front.makeFirstResponder(nil)
                    settleLayout(front)
                    guard NSApp.isActive, front.isKeyWindow else { return Shown(wids: [], pages: pages) }
                }
                settlingGeneration = generation
                finishRendering(renderedWindows, generation)
            }
            return Shown(wids: [], pages: pages)
        }
        if currentId != "switcher", let front = wids.first.flatMap({ byNumber[$0] }) {
            guard NSApp.isActive, front.isKeyWindow else { return Shown(wids: [], pages: pages) }
        }
        return Shown(wids: wids, pages: pages)
    }

    static func page(_ n: Int) {
        current?.pager?()?.scroll(to: n)
        current?.windows?().forEach(settleLayout)
    }

    static func setLook(_ look: String) {
        SettingsWindow.qaDiscard()
        let appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
        App.shared.appearance = appearance
        Menubar.menu.appearance = appearance
    }

    /// Day 4 of the trial and a long-expired one, rather than whatever day the machine happens to be on: the
    /// day count is printed in the Upgrade button, the menubar menu and the prompts.
    static func setLicense(_ license: String) {
        SettingsWindow.qaDiscard()
        switch license {
            case "trial":
                LicenseManager.shared.mockTrialDay(4)
            case "expired":
                LicenseManager.shared.mockTrialDay(40)
            default:
                LicenseManager.shared.mockProUser()
        }
        Menubar.menubarIconCallback(nil)
    }

    static func closeAll(keepSettings: Bool = false) {
        renderGeneration += 1
        settlingGeneration = nil
        readyGeneration = nil
        currentId = nil
        Menubar.menu.cancelTrackingWithoutAnimation()
        if NSApp.modalWindow != nil { NSApp.abortModal() }
        popovers.allObjects.forEach { $0.close() }
        Popover.shared.hide()
        if SwitcherSession.isActive { App.hideUi() }
        if let settings = SettingsWindow.shared, let sheet = settings.attachedSheet {
            sheet.animationBehavior = .none
            QaSheetAnimation.disable(on: sheet)
            settings.endSheet(sheet)
            sheet.orderOut(nil)
        }
        if !keepSettings { SettingsWindow.qaDiscard() }
        let windows: [NSWindow?] = [AboutWindow.shared, FeedbackWindow.shared, PermissionsWindow.shared,
            Day1WelcomeLetterWindow.shared, Day15ProactiveWindow.shared, Day15FullUpgradeWindow.shared,
            Day35FinalWindow.shared]
        windows.compactMap { $0 }.filter { $0.isVisible }.forEach { $0.close() }
        PermissionsWindow.qaForcedStatus = nil
        current = nil
    }

    // MARK: - the surfaces

    private static let surfaces: [Surface] = settingsSurfaces() + controlsSurfaces() + sheetSurfaces()
        + windowSurfaces() + proSurfaces() + alertSurfaces() + menubarSurfaces()

    private static func settingsSurfaces() -> [Surface] {
        ["appearance", "general", "exceptions"].map { section in
            Surface(id: "settings.\(section)", licenses: nil, inSettings: true) { settings(section) }
        } + [Surface(id: "settings.upgrade", licenses: nil, inSettings: true) { settings(nil) }]
    }

    private static func controlsSurfaces() -> [Surface] {
        let segments = ["filtering", "appearance", "ordering"]
        return [false, true].flatMap { gesture in
            segments.enumerated().map { segment, name in
                Surface(id: "settings.controls.\(gesture ? "gesture" : "shortcut").\(name)", licenses: nil, inSettings: true) {
                    _ = settings("controls")
                    ControlsTab.qaSelect(gesture: gesture, segment: segment)
                    return settings("controls")
                }
            }
        } + [Surface(id: "popover.gesture-info", licenses: nil, inSettings: true) {
            _ = settings("controls")
            ControlsTab.qaSelect(gesture: true, segment: 0)
            hoverInfoButton(in: SettingsWindow.shared)
            return Target()
        }]
    }

    private static func sheetSurfaces() -> [Surface] {
        let sheets: [(String, () -> Void)] = [
            ("customize-style", { AppearanceTab.showCustomizeStyleSheet() }),
            ("animations", { AppearanceTab.showAnimationsSheet() }),
            ("shortcuts-when-active", { ControlsTab.showShortcutsSettings() }),
            ("additional-controls", { ControlsTab.showAdditionalControlsSettings() }),
        ]
        return sheets.map { name, show in
            Surface(id: "sheet.\(name)", licenses: nil, inSettings: true) {
                _ = settings(nil)
                show()
                return Target(windows: { [SettingsWindow.shared?.attachedSheet].compactMap { $0 } })
            }
        } + [Surface(id: "popover.hide-status-icons-info", licenses: nil, inSettings: true) {
            _ = settings(nil)
            AppearanceTab.showCustomizeStyleSheet()
            hoverInfoButton(in: SettingsWindow.shared?.attachedSheet)
            return Target()
        }]
    }

    private static func windowSurfaces() -> [Surface] {
        [
            Surface(id: "about", licenses: nil, inSettings: false) {
                App.showAboutWindow()
                return target(AboutWindow.shared) { AboutWindow.shared.flatMap { documentPager($0.contentView as? NSScrollView) } }
            },
            Surface(id: "feedback", licenses: nil, inSettings: false) { feedback(nil) },
            Surface(id: "feedback.bug", licenses: nil, inSettings: false) { feedback("selectBug") },
            Surface(id: "feedback.suggestion", licenses: nil, inSettings: false) { feedback("selectEnhancement") },
            Surface(id: "permissions", licenses: nil, inSettings: false) { permissions(granted: true) },
            Surface(id: "permissions.missing", licenses: nil, inSettings: false) { permissions(granted: false) },
        ]
    }

    private static func proSurfaces() -> [Surface] {
        let reasons: [(String, HardGateReason?)] = [
            ("not-engaged", nil),
            ("extra-shortcut", .feature(.extraShortcut(index: 1))),
            ("search", .feature(.searchInSwitcher)),
            ("app-icons", .proPreferences(appearanceStyle: .appIcons, shortcut: false)),
            ("titles", .proPreferences(appearanceStyle: .titles, shortcut: false)),
        ]
        return [
            Surface(id: "pro.welcome.new", licenses: trial, inSettings: false) { welcome(freshInstall: true) },
            Surface(id: "pro.welcome.upgrade", licenses: trial, inSettings: false) { welcome(freshInstall: false) },
            Surface(id: "pro.day4-tour", licenses: trial, inSettings: false) { Day4TourPopover.show(); return Target() },
            Surface(id: "pro.day12-heads-up", licenses: trial, inSettings: false) { Day12HeadsUpPopover.show(); return Target() },
            Surface(id: "pro.day15-proactive", licenses: expired, inSettings: false) {
                Day15ProactiveWindow.show()
                return target(Day15ProactiveWindow.shared)
            },
            Surface(id: "pro.day21-reminder", licenses: expired, inSettings: false) { Day21ReminderPopover.show(); return Target() },
            Surface(id: "pro.day35-final", licenses: expired, inSettings: false) {
                Day35FinalWindow.show()
                return target(Day35FinalWindow.shared)
            },
        ] + reasons.flatMap { name, reason in
            [
                Surface(id: "pro.day15-full-upgrade.\(name)", licenses: expired, inSettings: false) {
                    Day15FullUpgradeWindow.show(for: reason)
                    return target(Day15FullUpgradeWindow.shared)
                },
                Surface(id: "pro.day15-hard-gate.\(name)", licenses: expired, inSettings: false) {
                    Day15HardGatePopover.show(for: reason)
                    return Target()
                },
            ]
        }
    }

    /// Alerts run a modal loop of their own, so they are opened on the next turn of the main loop and the
    /// harness finds their window among the ones that appeared. `closeAll` aborts the loop, and every caller
    /// here reads an aborted alert as neither of its buttons, so nothing is reset, activated or sent.
    private static func alertSurfaces() -> [Surface] {
        let alerts: [(String, () -> Void)] = [
            ("reset-settings", { GeneralTab.resetPreferences() }),
            ("language-change", { GeneralTab.setLanguageCallback(NSControl()) }),
            ("conflicting-shortcut", { _ = ControlsTab.confirmUnassigningConflict("• " + NSLocalizedString("Show", comment: "Menubar option")) }),
            ("settings-not-saved.symlink", { PreferencesPersistenceCheck.debugShowDialog(symlinked: true) }),
            ("settings-not-saved.unwritable", { PreferencesPersistenceCheck.debugShowDialog(symlinked: false) }),
            ("activate-license", { UpgradeTab.presentActivationSheet() }),
            ("activation-failed", { UpgradeTab.presentActivationSheet(prefilledKey: "QA-LICENSE-KEY", autoFailedHint: true) }),
            ("seat-limit", { UpgradeTab.presentSeatLimitSheet(key: "QA-LICENSE-KEY", instances: seats) }),
            ("license-error", { UpgradeTab.presentLicenseError(NSLocalizedString("Activation failed", comment: ""), LicenseAPIError.invalidKey) }),
            ("license-error.details", {
                UpgradeTab.presentLicenseError(NSLocalizedString("Activation failed", comment: ""),
                    LicenseAPIError.invalidResponse(debugInfo: "HTTP 500\n{\"error\": \"qa\"}"))
            }),
        ]
        return alerts.map { name, show in
            Surface(id: "alert.\(name)", licenses: nil, inSettings: false) {
                later(show)
                return Target()
            }
        } + [Surface(id: "alert.feedback-confirm", licenses: nil, inSettings: false) {
            _ = feedback("selectEnhancement")
            later { _ = FeedbackWindow.shared?.perform(NSSelectorFromString("sendCallback")) }
            return Target()
        }]
    }

    /// Not the icon itself: whether it can be seen at all depends on how crowded the menubar is, and on a
    /// laptop the notch hides it more often than not.
    private static func menubarSurfaces() -> [Surface] {
        [
            Surface(id: "menubar.menu", licenses: nil, inSettings: false) {
                later { Menubar.popUpMenu() }
                return Target()
            },
            // Pro only: once the license lapses, the Pro styles give way to thumbnails, and the suite relaunches
            // AltTab once per style to photograph them.
            Surface(id: "switcher", licenses: ["pro"], inSettings: false) {
                App.showUi(0)
                return target(TilesPanel.shared)
            },
        ]
    }

    // MARK: - opening

    /// For what runs a loop of its own (an alert's modal session, a menu's tracking): a run-loop block rather
    /// than a main-queue one. The main queue is serial, so a modal loop started from one of its blocks would
    /// hold it, and every command after this one, which the CLI port hands to the main queue, would wait
    /// for an alert nobody is there to dismiss.
    private static func later(_ body: @escaping () -> Void) {
        RunLoop.main.perform(inModes: [.default], block: body)
    }

    private static func settings(_ section: String?) -> Target {
        let window = SettingsWindow.shared ?? SettingsWindow()
        App.showSecondaryWindow(window)
        window.orderFrontRegardless()
        window.qaShow(section)
        return Target(windows: { [SettingsWindow.shared].compactMap { $0 } },
                      pager: { SettingsWindow.shared?.qaPager(section) })
    }

    private static func feedback(_ selector: String?) -> Target {
        App.sparkleDelegate?.cachedResult = .upToDate
        App.showFeedbackPanel()
        if let selector { _ = FeedbackWindow.shared?.perform(NSSelectorFromString(selector)) }
        return target(FeedbackWindow.shared)
    }

    /// The permission timer repaints the statuses every few seconds, so "missing" is forced rather than set.
    private static func permissions(granted: Bool) -> Target {
        PermissionsWindow.qaForcedStatus = granted ? nil : .notGranted
        App.showPermissionsWindow()
        PermissionsWindow.updatePermissionViews()
        return target(PermissionsWindow.shared)
    }

    private static func welcome(freshInstall: Bool) -> Target {
        Day1WelcomeLetterWindow.shared?.close()
        Day1WelcomeLetterWindow.shared = nil
        Day1WelcomeLetterWindow.show(forceFreshInstall: freshInstall)
        return target(Day1WelcomeLetterWindow.shared)
    }

    private static func target(_ window: NSWindow?, pager: (() -> Pager?)? = nil) -> Target {
        Target(windows: { [window].compactMap { $0 } }, pager: pager)
    }

    private static func documentPager(_ scrollView: NSScrollView?) -> Pager? {
        guard let scrollView, let document = scrollView.documentView else { return nil }
        scrollView.layoutSubtreeIfNeeded()
        return Pager(scrollView: scrollView, top: 0, bottom: document.frame.height)
    }

    /// The two info popovers open on hover. Their button is found rather than named, and hovered through
    /// the closure the pointer would have run.
    private static func hoverInfoButton(in window: NSWindow?) {
        guard let root = window?.contentView, let button = firstInfoButton(root) else { return }
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)
        if let event { button.onMouseEntered?(event, button) }
    }

    private static func firstInfoButton(_ view: NSView) -> ClickHoverImageView? {
        if let button = view as? ClickHoverImageView, button.onMouseEntered != nil, !button.isHiddenOrHasHiddenAncestor {
            return button
        }
        for subview in view.subviews {
            if let found = firstInfoButton(subview) { return found }
        }
        return nil
    }

    // MARK: - holding things still

    private static let seats = [
        ActiveInstance(id: "qa-instance-1", machineName: "MacBook Pro", lastSeenAt: Date(timeIntervalSince1970: 1_767_225_600)),
        ActiveInstance(id: "qa-instance-2", machineName: "Mac mini", lastSeenAt: Date(timeIntervalSince1970: 1_769_904_000)),
    ]

    /// Relative to now, and re-pinned before every surface, so a week's count cannot drift as the run goes on.
    private static func pinVolatileContent() {
        let now = Int(Date().timeIntervalSince1970)
        // A minute clear of both ends: a count made a few milliseconds after this pin must not decide
        // differently whether the event exactly one week ago belongs to "the past week".
        let triggers = (0..<4600).map { now - 60 - 300 * $0 }
        UsageStats.qaPinned = [
            "triggers": triggers,
            "triggersAppIcons": triggers.enumerated().filter { $0.offset % 4 == 0 }.map { $0.element },
            "triggersExtraShortcuts": triggers.enumerated().filter { $0.offset % 7 == 0 }.map { $0.element },
            "searches": triggers.enumerated().filter { $0.offset % 10 == 0 }.map { $0.element },
        ]
        App.sparkleDelegate?.cachedResult = .upToDate
    }

    private static func observePopovers() {
        guard !observingPopovers else { return }
        observingPopovers = true
        NotificationCenter.default.addObserver(forName: NSPopover.willShowNotification, object: nil, queue: .main) { note in
            if let popover = note.object as? NSPopover {
                popover.animates = false
                popovers.add(popover)
            }
        }
    }

    private static func disableAnimations() {
        NSApp.windows.forEach { $0.animationBehavior = .none }
    }

    private static func settleLayout(_ window: NSWindow) {
        guard let view = window.contentView else { return }
        view.needsUpdateConstraints = true
        view.updateConstraintsForSubtreeIfNeeded()
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.needsDisplay = true
        view.displayIfNeeded()
        CATransaction.flush()
    }

    /// Hold screen updates while AppKit resolves constraints and backing layers. `--qa-shown` stays empty
    /// through two idle boundaries, so ScreenCaptureKit never has to race the intermediate frames.
    private static func prepareForRendering(_ window: NSWindow, _ generation: Int) {
        guard generation == renderGeneration else { return }
        window.animationBehavior = .none
        if window is SettingsWindow {
            window.collectionBehavior.insert(.canJoinAllSpaces)
            App.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
        alignToBackingPixels(window)
        window.disableScreenUpdatesUntilFlush()
        settleLayout(window)
        if window is SettingsWindow {
            ControlsTab.qaClearHover()
            ExceptionsTab.qaClearHover()
            (window as? SettingsWindow)?.qaHideScrollers()
            settleLayout(window)
        }
    }

    private static func alignToBackingPixels(_ window: NSWindow) {
        let scale = window.screen?.backingScaleFactor ?? NSScreen.preferred.backingScaleFactor
        guard scale > 0 else { return }
        let origin = window.frame.origin
        window.setFrameOrigin(NSPoint(x: (origin.x * scale).rounded() / scale,
                                      y: (origin.y * scale).rounded() / scale))
    }

    private static func finishRendering(_ windows: [NSWindow], _ generation: Int) {
        var idlePass = 0
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true,
                                                          CFIndex.max) { observer, _ in
            guard generation == renderGeneration else {
                if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
                return
            }
            idlePass += 1
            if idlePass == 1 {
                windows.forEach(settleLayout)
                DispatchQueue.main.async {}
                return
            }
            if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
            windows.forEach(settleLayout)
            readyGeneration = generation
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    private static func onScreenWindowNumbers() -> [UInt32] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let excluded = Set([QAMenu.shared?.windowNumber, Menubar.statusItem?.button?.window?.windowNumber].compactMap { $0 })
        return infos.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? pid_t == pid,
                  let number = info[kCGWindowNumber as String] as? UInt32,
                  !excluded.contains(Int(number)) else { return nil }
            return number
        }
    }
}
#endif
