import AppKit

/// Launch-time guard that warns when macOS isn't persisting AltTab's preferences to disk (issue #5790).
///
/// It gathers, off the main thread, the filesystem state of every `UserDefaults` suite AltTab writes, asks
/// the pure `PreferencesPersistenceProbe` for a verdict, and — only on unambiguous evidence — shows a dialog
/// on the main thread explaining the cause and the fix. It re-checks on every launch, so the dialog keeps
/// appearing until the user resolves the underlying problem; there is no "don't show again" (a suppression
/// flag couldn't persist anyway, since persistence is exactly what's broken).
enum PreferencesPersistenceCheck {
    /// Every suite AltTab persists to. `UserDefaults.standard` is keyed by the bundle id; the others are
    /// explicit suites (license/Pro-transition state, usage stats). System suites we only read (e.g.
    /// `com.apple.Finder`) are out of scope.
    static func suiteNames() -> [String] {
        [App.bundleIdentifier, LicenseManager.defaultsSuiteName, "\(App.bundleIdentifier).usage"]
    }

    /// Entry point, called early from `applicationDidFinishLaunching`. Probes off-main; the (rare) alert
    /// hops back to main.
    static func runInBackground() {
        DispatchQueue.global(qos: .utility).async {
            let facts = suiteNames().map(gatherFacts)
            guard case let .broken(symlinkedPaths, unwritablePaths) = PreferencesPersistenceProbe.verdict(facts) else { return }
            Logger.warning { "preferences not persisting — symlinked:\(symlinkedPaths) unwritable:\(unwritablePaths)" }
            DispatchQueue.main.async { showDialog(symlinkedPaths: symlinkedPaths, unwritablePaths: unwritablePaths) }
        }
    }

    private static func preferencesDirectory() -> String {
        NSHomeDirectory() + "/Library/Preferences"
    }

    /// `FileManager.attributesOfItem(atPath:)` has `lstat` semantics (it does NOT follow a symlink), so it
    /// reports the link node itself — exactly what we need to spot a Mackup-style symlinked plist, even when
    /// the link dangles. `isWritableFile` is only consulted for a real regular file and runs as the same user
    /// as the per-user cfprefsd, so it's a valid proxy for whether cfprefsd can rewrite the file.
    static func gatherFacts(_ suiteName: String) -> PreferencesPersistenceProbe.SuiteFacts {
        let fm = FileManager.default
        let path = "\(preferencesDirectory())/\(suiteName).plist"
        let attributes = try? fm.attributesOfItem(atPath: path)
        let exists = attributes != nil
        let isSymlink = (attributes?[.type] as? FileAttributeType) == .typeSymbolicLink
        let isWritable = (exists && !isSymlink) ? fm.isWritableFile(atPath: path) : true
        return PreferencesPersistenceProbe.SuiteFacts(suiteName: suiteName, plistPath: path, exists: exists, isSymlink: isSymlink, isWritable: isWritable)
    }

    private static func showDialog(symlinkedPaths: [String], unwritablePaths: [String]) {
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        let (message, paths) = dialogContent(symlinkedPaths: symlinkedPaths, unwritablePaths: unwritablePaths)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = NSLocalizedString("Your settings reset every time AltTab restarts.", comment: "")
        alert.informativeText = message
        // The path goes in a non-wrapping accessory label so it stays on one line; NSAlert widens to fit it.
        alert.accessoryView = pathLabel(paths)
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        // The single OK button only responds to Return by default; also dismiss on Escape.
        let escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.charactersIgnoringModifiers == "\u{1b}" {
                NSApp.stopModal()
                return nil
            }
            return event
        }
        alert.runModal()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
    }

    /// The explanation sentence and the offending path(s). When a suite is both symlinked and unwritable,
    /// only the symlink is reported — it's the one to fix first, and ownership of the regular file that
    /// replaces it is then under the user's control anyway.
    private static func dialogContent(symlinkedPaths: [String], unwritablePaths: [String]) -> (message: String, paths: [String]) {
        if !symlinkedPaths.isEmpty {
            return (NSLocalizedString("AltTab preferences file is a symlink. macOS doesn’t support symlink for preferences. Please use a valid file instead of a symlink here:", comment: ""), symlinkedPaths)
        }
        return (NSLocalizedString("AltTab preferences file isn’t writable by your account. Please fix ownership and permissions of the file here:", comment: ""), unwritablePaths)
    }

    /// A selectable, non-wrapping label (one line per path) used as the alert's accessory, so a long path
    /// doesn't wrap. `sizeToFit` makes it as wide as the longest path, and NSAlert grows to match.
    private static func pathLabel(_ paths: [String]) -> NSTextField {
        let label = NSTextField(labelWithString: paths.map(abbreviateHome).joined(separator: "\n"))
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 0
        label.isSelectable = true
        label.sizeToFit()
        return label
    }

    /// Collapse the home directory to `~` for a shorter, cleaner path in the dialog.
    private static func abbreviateHome(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + String(path.dropFirst(home.count)) : path
    }

    #if DEBUG
    /// QA hook (wired into `QAMenu`): show either dialog variant on demand, using the real
    /// preferences-plist path, without having to actually symlink or lock a file.
    static func debugShowDialog(symlinked: Bool) {
        let path = "\(preferencesDirectory())/\(App.bundleIdentifier).plist"
        showDialog(symlinkedPaths: symlinked ? [path] : [], unwritablePaths: symlinked ? [] : [path])
    }
    #endif
}
