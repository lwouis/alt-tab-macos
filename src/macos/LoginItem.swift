import Cocoa

/// Owns the `startAtLogin` preference's side effect: writing / removing the app's launchd plist
/// under `~/Library/LaunchAgents`. Extracted from `PreferencesEvents` so launchd-plist plumbing
/// isn't mixed with menubar/Sparkle/trackpad side effects.
///
/// docs: https://developer.apple.com/library/archive/technotes/tn2083/_index.html#//apple_ref/doc/uid/DTS10003794-CH1-SECTION23
/// docs: man launchd.plist
enum LoginItem {
    private static let launchAgentPlist: NSDictionary = [
        "Label": App.bundleIdentifier,
        "Program": Bundle.main.executablePath ?? "/Applications/\(App.name).app/Contents/MacOS/\(App.name)",
        "RunAtLoad": true,
        "LimitLoadToSessionType": "Aqua",
        // starting from macOS 13, AssociatedBundleIdentifiers is required, otherwise the UI in
        // System Settings > General > Login Items, will show "Louis Pontoise" instead of "AltTab.app"
        "AssociatedBundleIdentifiers": App.bundleIdentifier,
        // "ProcessType: If left unspecified, the system will apply light resource limits to the job,
        //               throttling its CPU usage and I/O bandwidth"
        "ProcessType": "Interactive",
        // "LegacyTimers": If this key is set to true, timers created by the job will opt into less
        //                 efficient but more precise behavior and not be coalesced with other timers.
        "LegacyTimers": true,
    ]

    /// Reconcile the launchd plist on disk with `Preferences.startAtLogin`. Writes the plist when
    /// enabled; removes it when disabled. Also migrates the legacy `LSSharedFileList` login item.
    static func applyCurrentPreference() {
        var preferenceEnabled = Preferences.startAtLogin
        if (LoginItem.self as AvoidDeprecationWarnings.Type).removeLoginItemIfPresent() && !preferenceEnabled {
            preferenceEnabled = true
            Preferences.set("startAtLogin", "true", false)
        }
        do {
            try writePlistToDisk(preferenceEnabled)
        } catch let error {
            Logger.error { "Failed to write plist file to disk. error:\(error)" }
        }
    }

    private static func writePlistToDisk(_ enabled: Bool) throws {
        var launchAgentsPath = (try? FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) ?? URL(fileURLWithPath: "~/Library", isDirectory: true)
        launchAgentsPath.appendPathComponent("LaunchAgents", isDirectory: true)
        if !FileManager.default.fileExists(atPath: launchAgentsPath.path) {
            try FileManager.default.createDirectory(at: launchAgentsPath, withIntermediateDirectories: false)
            Logger.debug { launchAgentsPath.absoluteString + " created" }
        }
        launchAgentsPath.appendPathComponent("\(App.bundleIdentifier).plist", isDirectory: false)
        if enabled {
            let data = try PropertyListSerialization.data(fromPropertyList: launchAgentPlist, format: .xml, options: 0)
            try data.write(to: launchAgentsPath, options: [.atomic])
            Logger.debug { launchAgentsPath.absoluteString + " written" }
        } else if FileManager.default.fileExists(atPath: launchAgentsPath.path) {
            try FileManager.default.removeItem(at: launchAgentsPath)
            Logger.debug { launchAgentsPath.absoluteString + " removed" }
        }
    }

    @available(OSX, deprecated: 10.11)
    fileprivate static func removeLoginItemIfPresent() -> Bool {
        var removed = false
        if let loginItems = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue(),
           let loginItemsSnapshot = LSSharedFileListCopySnapshot(loginItems, nil)?.takeRetainedValue() as? [LSSharedFileListItem] {
            let appUrl = URL(fileURLWithPath: Bundle.main.bundlePath)
            // resolve without mounting: a login item's bookmark can point to an SMB share, and the
            // default flags (0) mount it synchronously, freezing the main thread on a dead/stale
            // server (#5773). We only read lastPathComponent below, which needs no mount.
            let flags = LSSharedFileListResolutionFlags(kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes)
            for item in loginItemsSnapshot {
                let itemUrl = LSSharedFileListItemCopyResolvedURL(item, flags, nil)?.takeRetainedValue() as? URL
                if itemUrl?.lastPathComponent == appUrl.lastPathComponent {
                    LSSharedFileListItemRemove(loginItems, item)
                    removed = true
                }
            }
        }
        return removed
    }
}

fileprivate protocol AvoidDeprecationWarnings {
    static func removeLoginItemIfPresent() -> Bool
}

extension LoginItem: AvoidDeprecationWarnings {}
