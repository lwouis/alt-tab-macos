import Cocoa

/// Main-thread coordinator: failure suspends startup; only a fresh process retries initialization.
enum StartupRecovery {
    private static var policy = StartupRecoveryPolicy()
    private static var window: StartupRecoveryWindow?
    private(set) static var failureCount = 0
    private(set) static var retryDelay: TimeInterval?
    static var isRecovering: Bool { policy.failed }
    static var directory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(App.bundleIdentifier)
        #if DEBUG
        if let session = QaLifecycle.session { return root.appendingPathComponent("qa/" + session) }
        #endif
        return root
    }
    private static var store: StartupRecoveryStore { StartupRecoveryStore(directory: directory) }

    static func failed(_ reason: String) {
        precondition(Thread.isMainThread)
        guard policy.beginFailure() else { return }
        Logger.error { "Mandatory input unavailable: \(reason)" }
        ProTransitionManager.shared.suspendForRecovery()
        App.hideUi()
        KeyboardEvents.stopForRecovery()
        CursorEvents.stopForRecovery()
        TrackpadEvents.stopForRecovery()
        ScrollwheelEvents.stopForRecovery()
        #if DEBUG
        QaLifecycle.finishedLaunching = false
        #endif
        do {
            let record = try store.recordFailure()
            failureCount = record.failures
            retryDelay = record.retryDelay
        } catch {
            Logger.error { "Cannot persist recovery budget: \(error)" }
            retryDelay = nil
        }
        guard let delay = retryDelay else { DispatchQueue.main.async { showWindow() }; return }
        Logger.warning { "Input recovery attempt \(failureCount)/3; restart in \(delay)s" }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard !App.isTerminating else { return }
            App.restart()
        }
    }

    static func becameReady() {
        precondition(Thread.isMainThread)
        policy.becameReady(at: ProcessInfo.processInfo.systemUptime)
        guard let record = try? store.read() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + StartupRecoveryPolicy.stableInterval) {
            guard !App.isTerminating, policy.canClear(at: ProcessInfo.processInfo.systemUptime) else { return }
            do { try store.clear(ifUnchanged: record.generation) }
            catch { Logger.warning { "Cannot clear recovery budget: \(error)" } }
        }
    }

    static func retryManually() {
        do {
            try store.retryManually()
            window?.close()
            App.restart()
        } catch {
            Logger.error { "Cannot reset recovery budget: \(error)" }
            showWindow()
        }
    }

    private static func showWindow() {
        guard !App.isTerminating else { return }
        if window == nil { window = StartupRecoveryWindow() }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG
    static var recordedFailuresForQa: Int { (try? store.read()?.failures) ?? 0 }

    static func configureForQa(control: String, recoverAfter: Int?) throws {
        guard QaLifecycle.enabled else { return }
        try store.retryManually()
        let defaults = UserDefaults(suiteName: QaLifecycle.licenseSuite)!
        defaults.set(control, forKey: "qa.inputFailure")
        defaults.set(recoverAfter, forKey: "qa.inputRecoveryAfter")
        guard defaults.synchronize() else { throw CocoaError(.fileWriteUnknown) }
    }

    static func shouldFail(_ control: String) -> Bool {
        guard QaLifecycle.enabled else { return false }
        let defaults = UserDefaults(suiteName: QaLifecycle.licenseSuite)!
        guard defaults.string(forKey: "qa.inputFailure") == control else { return false }
        let count = (try? store.read()?.failures) ?? 0
        let recoverAfter = defaults.object(forKey: "qa.inputRecoveryAfter") as? Int
        return recoverAfter.map { count < $0 } ?? true
    }
    #endif
}

final class StartupRecoveryWindow: NSWindow {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 220), styleMask: [.titled], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        title = "AltTab"
        let title = NSTextField(wrappingLabelWithString: NSLocalizedString("AltTab couldn’t start.", comment: ""))
        title.font = .boldSystemFont(ofSize: 15)
        let message = NSTextField(wrappingLabelWithString: NSLocalizedString("AltTab couldn’t access the keyboard or mouse. You can try again or quit AltTab.", comment: ""))
        let retry = NSButton(title: NSLocalizedString("Try again", comment: ""), target: self, action: #selector(retryClicked))
        retry.bezelStyle = .rounded
        retry.keyEquivalent = "\r"
        let quit = NSButton(title: String(format: NSLocalizedString("Quit %@", comment: ""), "AltTab"), target: NSApp, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [quit, retry])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [title, message, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView!.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: contentView!.bottomAnchor, constant: -24),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    @objc private func retryClicked() { StartupRecovery.retryManually() }
}
