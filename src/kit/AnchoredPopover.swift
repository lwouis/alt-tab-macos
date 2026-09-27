import Cocoa

/// A status item can have a frame before its window and visible rect are ready. NSPopover.show
/// silently does nothing in that state. Keep the request until layout makes it usable, or cancel it.
class AnchoredPopover: NSPopover {
    var isWaitingForAnchor: Bool { pending != nil }
    private var generation = UInt64(0)
    private var pending: (() -> Bool)?
    private var scheduled = false
    private var showingGeneration: UInt64?
    private var viewObservations = [NSKeyValueObservation]()
    private var windowObservations = [NSKeyValueObservation]()
    private var updateObserver: NSObjectProtocol?
    private var shownObserver: NSObjectProtocol?
    private var closedObserver: NSObjectProtocol?

    func present(_ content: NSView, from anchor: NSView, onShown: (() -> Void)? = nil) {
        cancelPresentation()
        let request = generation
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
            guard let self, let anchor, self.canShow(from: anchor) else { return false }
            let controller = NSViewController()
            controller.view = content
            self.contentViewController = controller
            self.showingGeneration = request
            return self.showImmediately(from: anchor)
        }
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

    func canShow(from anchor: NSView) -> Bool {
        guard let window = anchor.window else { return false }
        return Self.anchorIsReady(windowVisible: window.isVisible, windowFrame: window.frame,
            bounds: anchor.bounds, visibleRect: anchor.visibleRect)
    }

    static func anchorIsReady(windowVisible: Bool, windowFrame: NSRect, bounds: NSRect, visibleRect: NSRect) -> Bool {
        windowVisible && !windowFrame.isEmpty && !bounds.intersection(visibleRect).isEmpty
    }

    func showImmediately(from anchor: NSView) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        if isShown { contentViewController?.view.window?.makeKey() }
        return isShown
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
    }
}
