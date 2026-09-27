import Cocoa

/// A status item can have a frame before its window and visible rect are ready. NSPopover.show
/// silently does nothing in that state. Keep the request until layout makes it usable, or cancel it.
/// An icon macOS never puts in the menu bar gets the same content, without the arrow, under the menu bar
/// (`StatusItemAnchor`).
class AnchoredPopover: NSPopover {
    var isWaitingForAnchor: Bool { pending != nil }
    var settleTimeout = StatusItemAnchor.settleTimeout
    private var generation = UInt64(0)
    private var pending: (() -> Bool)?
    private var scheduled = false
    private var showingGeneration: UInt64?
    private var viewObservations = [NSKeyValueObservation]()
    private var windowObservations = [NSKeyValueObservation]()
    private var updateObserver: NSObjectProtocol?
    private var shownObserver: NSObjectProtocol?
    private var closedObserver: NSObjectProtocol?
    private var floatingAnchor: NSWindow?

    func present(_ content: NSView, from item: NSStatusItem, onShown: (() -> Void)? = nil) {
        present(content, from: item.button!, anchorIsHidden: { [weak item] in !(item?.isVisible ?? false) }, onShown: onShown)
    }

    func present(_ content: NSView, from anchor: NSView, anchorIsHidden: @escaping () -> Bool = { false }, onShown: (() -> Void)? = nil) {
        cancelPresentation()
        let request = generation
        let requestedAt = ProcessInfo.processInfo.systemUptime
        observe(anchor)
        shownObserver = NotificationCenter.default.addObserver(forName: NSPopover.didShowNotification, object: self, queue: nil) { [weak self] _ in
            guard let self, self.generation == request, self.showingGeneration == request else { return }
            self.removeObserver(&self.shownObserver)
            onShown?()
        }
        closedObserver = NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: self, queue: nil) { [weak self] _ in
            guard let self, self.generation == request else { return }
            self.cancelPresentation()
            self.contentViewController = nil
        }
        pending = { [weak self, weak anchor] in
            guard let self, let anchor else { return false }
            let readiness = self.readiness(of: anchor, isHidden: anchorIsHidden(),
                deadlinePassed: ProcessInfo.processInfo.systemUptime - requestedAt >= self.settleTimeout)
            guard readiness != .settling else { return false }
            let controller = NSViewController()
            controller.view = content
            self.contentViewController = controller
            self.showingGeneration = request
            return readiness == .ready ? self.showImmediately(from: anchor) : self.showUnanchored()
        }
        retryAtSettleDeadline(request)
        retryPresentation()
    }

    func cancelPresentation() {
        generation += 1
        pending = nil
        scheduled = false
        showingGeneration = nil
        stopObservingAnchor()
        removeObserver(&shownObserver)
        removeObserver(&closedObserver)
    }

    func retryPresentation() {
        guard pending != nil, !scheduled else { return }
        scheduled = true
        let request = generation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == request else { return }
            self.scheduled = false
            guard let pending = self.pending else { return }
            let shown = pending()
            guard self.generation == request else { return }
            if shown {
                self.pending = nil
                self.stopObservingAnchor()
            }
        }
    }

    /// An icon macOS never places produces no layout event to retry on (measured on macOS 27 with the item switched
    /// off in System Settings), so the deadline itself has to trigger the fallback.
    private func retryAtSettleDeadline(_ request: UInt64) {
        DispatchQueue.main.asyncAfter(deadline: .now() + settleTimeout) { [weak self] in
            guard let self, self.generation == request else { return }
            self.retryPresentation()
        }
    }

    func readiness(of anchor: NSView, isHidden: Bool, deadlinePassed: Bool) -> StatusItemAnchor.Readiness {
        let window = anchor.window
        return StatusItemAnchor.readiness(isHidden: isHidden, windowVisible: window?.isVisible ?? false,
            windowFrame: window?.frame ?? .zero, bounds: anchor.bounds, visibleRect: anchor.visibleRect,
            screens: NSScreen.screens.map { StatusItemAnchor.Screen($0) }, deadlinePassed: deadlinePassed)
    }

    func showImmediately(from anchor: NSView) -> Bool {
        floatingAnchor?.orderOut(nil)
        return display(relativeTo: anchor, hidingArrow: false)
    }

    /// Centered under the menu bar of the screen the user works on. With no icon to point at, the arrow would
    /// point at nothing, so it is hidden through the private `shouldHideAnchor` (checked on macOS 27). Without
    /// that key, the arrow points up at the menu bar, which still says where the icon lives.
    func showUnanchored() -> Bool {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return false }
        let window = floatingAnchor ?? Self.makeFloatingAnchor()
        floatingAnchor = window
        window.setFrameOrigin(NSPoint(x: screen.frame.midX, y: screen.visibleFrame.maxY - 1))
        window.orderFrontRegardless()
        return display(relativeTo: window.contentView!, hidingArrow: true)
    }

    private func display(relativeTo view: NSView, hidingArrow: Bool) -> Bool {
        if responds(to: NSSelectorFromString("setShouldHideAnchor:")) { setValue(hidingArrow, forKey: "shouldHideAnchor") }
        NSApp.activate(ignoringOtherApps: true)
        show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        if isShown { contentViewController?.view.window?.makeKey() }
        return isShown
    }

    private static func makeFloatingAnchor() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }

    override func close() {
        cancelPresentation()
        // performClose may refuse a popover with a child window. Dismissal must finish before
        // opening Settings or replacing the content, rather than leaving an outgoing animation.
        let animated = animates
        animates = false
        super.close()
        animates = animated
        contentViewController = nil
        floatingAnchor?.orderOut(nil)
    }

    private func observe(_ anchor: NSView) {
        viewObservations = [
            anchor.observe(\.frame, options: [.new]) { [weak self] _, _ in self?.retryPresentation() },
            anchor.observe(\.bounds, options: [.new]) { [weak self] _, _ in self?.retryPresentation() },
            anchor.observe(\.window, options: [.new]) { [weak self] anchor, _ in
                self?.observeWindow(of: anchor)
                self?.retryPresentation()
            },
        ]
        observeWindow(of: anchor)
        updateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.retryPresentation()
        }
    }

    private func observeWindow(of anchor: NSView) {
        windowObservations = []
        guard let window = anchor.window else { return }
        windowObservations = [
            window.observe(\.frame, options: [.new]) { [weak self] _, _ in self?.retryPresentation() },
            window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in self?.retryPresentation() },
        ]
    }

    private func stopObservingAnchor() {
        viewObservations = []
        windowObservations = []
        removeObserver(&updateObserver)
    }

    private func removeObserver(_ observer: inout NSObjectProtocol?) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    deinit {
        for observer in [updateObserver, shownObserver, closedObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        floatingAnchor?.orderOut(nil)
    }
}

/// Whether a status item is somewhere the user can see it. Measured on macOS 27 (2026-10-03):
/// - a new item has no height, then sits off-screen at (0, -33), for 50 to 300ms before macOS places it;
/// - an item with no room left (the notch, too many items) or hidden with `isVisible = false` stays at (0, -33), with
///   no screen, while its window still reports itself visible and unoccluded;
/// - an item switched off in System Settings > Menu Bar before launch is never placed: it keeps no height. Switched
///   back on, it is placed at once;
/// - an item switched off while the app runs stays where it was, or moves elsewhere in the menu bar, and still
///   reports itself visible. That case can't be told apart from a usable icon.
/// So an icon counts as usable only once it lies inside a screen's menu bar, clear of the notch. Until
/// `settleTimeout`, it may still be on its way there.
enum StatusItemAnchor {
    static let settleTimeout = TimeInterval(1)

    enum Readiness: Equatable {
        case ready
        case settling
        case unavailable
    }

    struct Screen {
        let frame: CGRect
        /// The strip between the two halves of the menu bar on a screen with a camera housing.
        let notch: CGRect?

        init(frame: CGRect, notch: CGRect? = nil) {
            self.frame = frame
            self.notch = notch
        }

        init(_ screen: NSScreen) {
            frame = screen.frame
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, right.minX > left.maxX else {
                notch = nil
                return
            }
            notch = CGRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
        }
    }

    static func readiness(isHidden: Bool, windowVisible: Bool, windowFrame: CGRect, bounds: CGRect, visibleRect: CGRect,
                          screens: [Screen], deadlinePassed: Bool) -> Readiness {
        if isHidden { return .unavailable }
        if windowVisible && !windowFrame.isEmpty && !bounds.intersection(visibleRect).isEmpty
            && screens.contains(where: { isInMenuBar(windowFrame, $0) }) {
            return .ready
        }
        return deadlinePassed ? .unavailable : .settling
    }

    private static func isInMenuBar(_ frame: CGRect, _ screen: Screen) -> Bool {
        screen.frame.contains(frame) && frame.maxY >= screen.frame.maxY - 1
            && (screen.notch.map { frame.intersection($0).isEmpty } ?? true)
    }
}
