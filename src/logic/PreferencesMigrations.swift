class PreferencesMigrations {
    static func removeCorruptedPreferences() {
        // from v5.1.0+, there are crash reports of users somehow having their hold shortcuts set to ""
        ["holdShortcut", "holdShortcut2", "holdShortcut3", "holdShortcut4", "holdShortcut5"].forEach {
            if let s = UserDefaults.standard.string(forKey: $0), s == "" {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }
    }

    static func migratePreferences() {
        let preferencesKey = "preferencesVersion"
        if let versionInPlist = UserDefaults.standard.string(forKey: preferencesKey) {
            if versionInPlist != "#VERSION#" && versionInPlist.compare(App.version, options: .numeric) != .orderedDescending {
                updateToNewPreferences(versionInPlist)
            }
        }
        UserDefaults.standard.set(App.version, forKey: preferencesKey)
    }

    private static func updateToNewPreferences(_ versionInPlist: String) {
        Logger.debug { "App-version:\(App.version), Plist-version:\(versionInPlist)" }
        // x.compare(y) is .orderedDescending if x > y
        if versionInPlist.compare("7.27.0", options: .numeric) != .orderedDescending {
            migrateCursorFollowFocus()
            if versionInPlist.compare("7.26.0", options: .numeric) != .orderedDescending {
                migrateShowWindowlessApps()
                if versionInPlist.compare("7.25.0", options: .numeric) != .orderedDescending {
                    migrateHideWindowlessApps()
                    if versionInPlist.compare("7.13.1", options: .numeric) != .orderedDescending {
                        migrateGestures()
                        if versionInPlist.compare("7.8.0", options: .numeric) != .orderedDescending {
                            migrateMenubarIconWithNewShownToggle()
                            if versionInPlist.compare("7.0.0", options: .numeric) != .orderedDescending {
                                migratePreferencesIndexes()
                                if versionInPlist.compare("6.43.0", options: .numeric) != .orderedDescending {
                                    migrateBlacklists()
                                    if versionInPlist.compare("6.28.1", options: .numeric) != .orderedDescending {
                                        migrateMinMaxWindowsWidthInRow()
                                        if versionInPlist.compare("6.27.1", options: .numeric) != .orderedDescending {
                                            // "Start at login" new implem doesn't use Login Items; we remove the entry from previous versions
                                            (PreferencesMigrations.self as AvoidDeprecationWarnings.Type).migrateLoginItem()
                                            if versionInPlist.compare("6.23.0", options: .numeric) != .orderedDescending {
                                                // "Show windows from:" got the "Active Space" option removed
                                                migrateShowWindowsFrom()
                                                if versionInPlist.compare("6.18.1", options: .numeric) != .orderedDescending {
                                                    // nextWindowShortcut used to be able to have modifiers already present in holdShortcut; we remove these
                                                    migrateNextWindowShortcuts()
                                                    // dropdowns preferences used to store English text; now they store indexes
                                                    migrateDropdownsFromTextToIndexes()
                                                    // the "Hide menubar icon" checkbox was replaced with a dropdown of: icon1, icon2, hidden
                                                    migrateMenubarIconFromCheckboxToDropdown()
                                                    // "Show minimized/hidden/fullscreen windows" checkboxes were replaced with dropdowns
                                                    migrateShowWindowsCheckboxToDropdown()
                                                    // "Max size on screen" was split into max width and max height
                                                    migrateMaxSizeOnScreenToWidthAndHeight()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // cursorFollowFocus was a toggle. It's now a dropdown
    // before: cursorFollowFocusEnabled: true/false
    // after: cursorFollowFocus: 0 (never), 1 (always), 2 (differentScreen)
    private static func migrateCursorFollowFocus() {
        if let old = UserDefaults.standard.string(forKey: "cursorFollowFocusEnabled") {
            UserDefaults.standard.set(old == "true" ? 1 : 0, forKey: "cursorFollowFocus")
        }
    }

    // allow showWindowlessApps to have the third value `show`, in addition to `hide` and `showAtTheEnd`
    // before: showAtTheEnd: 0, hide: 1
    // after: show: 0, hide: 1, showAtTheEnd: 2
    private static func migrateShowWindowlessApps() {
        for index in ["", "2", "3", "4"] {
            if let old = UserDefaults.standard.string(forKey: "showWindowlessApps" + index) {
                UserDefaults.standard.set(old == "0" ? 2 : 1, forKey: "showWindowlessApps" + index)
            }
        }
    }

    // we moved from global to per-shortcut
    private static func migrateHideWindowlessApps() {
        if let old = UserDefaults.standard.string(forKey: "hideWindowlessApps") {
            for index in ["", "2", "3", "4"] {
                UserDefaults.standard.set(old == "true" ? 1 : 0, forKey: "showWindowlessApps" + index)
            }
        }
    }

    // we split gestures from disabled, 3-finger, 4-finger to: disabled, 3-finger-horizontal, 3-finger-vertical, 4-finger-horizontal, 4-finger-vertical
    // no need to map 0 -> 0 (disabled -> disabled)
    // no need to map 1 -> 1 (3-finger -> 3-finger-horizontal)
    // we need to map 2 -> 3 (4-finger -> 4-finger-horizontal)
    private static func migrateGestures() {
        if let old = UserDefaults.standard.string(forKey: "nextWindowGesture") {
            if old == "2" { // 2 (4-finger) -> 3 (4-finger-horizontal)
                UserDefaults.standard.set("3", forKey: "nextWindowGesture")
            }
        }
    }

    /// we added the new menubarIconShown toggle. It replaces menubarIcon having value "3" which would hide the icon
    /// there are now 2 preferences : menubarIconShown is a boolean, and menubarIcon has values 0, 1, 2
    private static func migrateMenubarIconWithNewShownToggle() {
        if let old = UserDefaults.standard.string(forKey: "menubarIcon") {
            if old == "3" {
                UserDefaults.standard.set("0", forKey: "menubarIcon")
                UserDefaults.standard.set("false", forKey: "menubarIconShown")
            }
        }
    }

    // we want to rely on preferences numbers to match the enum indexes. This migration realigns existing desyncs
    private static func migratePreferencesIndexes() {
        // migrate spacesToShow from 1 to 2. 1 was removed a while ago. 1=active => 2=>visible
        ["", "2", "3", "4", "5"].forEach { suffix in
            if let spacesToShow = UserDefaults.standard.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "1" {
                    UserDefaults.standard.set("2", forKey: "spacesToShow" + suffix)
                }
            }
        }
        // migrate spacesToShow from 0 to 2 and 2 to 0. 0 used to be end, 2 used to be start; they got switch for the UI order
        ["", "2", "3", "4", "5"].forEach { suffix in
            if let spacesToShow = UserDefaults.standard.string(forKey: "titleTruncation" + suffix) {
                if spacesToShow == "0" {
                    UserDefaults.standard.set("2", forKey: "titleTruncation" + suffix)
                }
                if spacesToShow == "2" {
                    UserDefaults.standard.set("0", forKey: "titleTruncation" + suffix)
                }
            }
        }
    }

    private static func migrateBlacklists() {
        var entries = [BlacklistEntry]()
        if let old = UserDefaults.standard.string(forKey: "dontShowBlacklist") {
            entries.append(contentsOf: oldBlacklistEntriesToNewOnes(old, .always, .none))
        }
        if let old = UserDefaults.standard.string(forKey: "disableShortcutsBlacklist") {
            let onlyFullscreen = UserDefaults.standard.bool(forKey: "disableShortcutsBlacklistOnlyFullscreen")
            entries.append(contentsOf: oldBlacklistEntriesToNewOnes(old, .none, onlyFullscreen ? .whenFullscreen : .always))
        }
        if entries.count > 0 {
            UserDefaults.standard.set(Preferences.jsonEncode(entries), forKey: "blacklist")
            ["dontShowBlacklist", "disableShortcutsBlacklist", "disableShortcutsBlacklistOnlyFullscreen"].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }
    }

    private static func oldBlacklistEntriesToNewOnes(_ old: String, _ hide: BlacklistHidePreference, _ ignore: BlacklistIgnorePreference) -> [BlacklistEntry] {
        old.split(separator: "\n").compactMap { (e) -> BlacklistEntry? in
            let line = e.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                return nil
            }
            return BlacklistEntry(bundleIdentifier: line, hide: hide, ignore: ignore)
        }
    }

    private static func migrateMinMaxWindowsWidthInRow() {
        ["windowMinWidthInRow", "windowMaxWidthInRow"].forEach {
            if let old = UserDefaults.standard.string(forKey: $0) {
                if old == "0" {
                    UserDefaults.standard.set("1", forKey: $0)
                }
            }
        }
    }

    @available(OSX, deprecated: 10.11)
    static func migrateLoginItem() {
        do {
            if let loginItemsWrapped = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil) {
                let loginItems = loginItemsWrapped.takeRetainedValue()
                if let loginItemsSnapshotWrapped = LSSharedFileListCopySnapshot(loginItems, nil) {
                    let loginItemsSnapshot = loginItemsSnapshotWrapped.takeRetainedValue() as! [LSSharedFileListItem]
                    let itemName = Bundle.main.bundleURL.lastPathComponent as CFString
                    let itemUrl = URL(fileURLWithPath: Bundle.main.bundlePath) as CFURL
                    loginItemsSnapshot.forEach {
                        if (LSSharedFileListItemCopyDisplayName($0).takeRetainedValue() == itemName) ||
                               (LSSharedFileListItemCopyResolvedURL($0, 0, nil)?.takeRetainedValue() == itemUrl) {
                            LSSharedFileListItemRemove(loginItems, $0)
                        }
                    }
                }
            }
            throw AxError.runtimeError // remove compiler warning
        } catch {
            // the LSSharedFile API is deprecated, and has a runtime crash on M1 Monterey
            // we catch any exception to void the app crashing
        }
    }

    private static func migrateShowWindowsFrom() {
        ["", "2"].forEach { suffix in
            if let spacesToShow = UserDefaults.standard.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "2" {
                    UserDefaults.standard.set("1", forKey: "screensToShow" + suffix)
                    UserDefaults.standard.set("1", forKey: "spacesToShow" + suffix)
                } else if spacesToShow == "1" {
                    UserDefaults.standard.set("1", forKey: "screensToShow" + suffix)
                }
            }
        }
    }

    private static func migrateNextWindowShortcuts() {
        ["", "2"].forEach { suffix in
            if let oldHoldShortcut = UserDefaults.standard.string(forKey: "holdShortcut" + suffix),
               let oldNextWindowShortcut = UserDefaults.standard.string(forKey: "nextWindowShortcut" + suffix) {
                let nextWindowShortcutCleanedUp = oldHoldShortcut.reduce(oldNextWindowShortcut, { $0.replacingOccurrences(of: String($1), with: "") })
                if oldNextWindowShortcut != nextWindowShortcutCleanedUp {
                    UserDefaults.standard.set(nextWindowShortcutCleanedUp, forKey: "nextWindowShortcut" + suffix)
                }
            }
        }
    }

    private static func migrateMaxSizeOnScreenToWidthAndHeight() {
        if let old = UserDefaults.standard.string(forKey: "maxScreenUsage") {
            UserDefaults.standard.set(old, forKey: "maxWidthOnScreen")
            UserDefaults.standard.set(old, forKey: "maxHeightOnScreen")
        }
    }

    private static func migrateShowWindowsCheckboxToDropdown() {
        ["showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows"]
            .flatMap { [$0, $0 + "2"] }
            .forEach {
                if let old = UserDefaults.standard.string(forKey: $0) {
                    if old == "true" {
                        UserDefaults.standard.set(ShowHowPreference.show.indexAsString, forKey: $0)
                    } else if old == "false" {
                        UserDefaults.standard.set(ShowHowPreference.hide.indexAsString, forKey: $0)
                    }
                }
            }
    }

    private static func migrateDropdownsFromTextToIndexes() {
        migratePreferenceValue("theme", [" macOS": "0", "❖ Windows 10": "1"])
        // "Main screen" was renamed to "Active screen"
        migratePreferenceValue("showOnScreen", ["Main screen": "0", "Active screen": "0", "Screen including mouse": "1"])
        migratePreferenceValue("alignThumbnails", ["Left": "0", "Center": "1"])
        migratePreferenceValue("appsToShow", ["All apps": "0", "Active app": "1"])
        migratePreferenceValue("spacesToShow", ["All spaces": "0", "Active space": "1"])
        migratePreferenceValue("screensToShow", ["All screens": "0", "Screen showing AltTab": "1"])
    }

    private static func migrateMenubarIconFromCheckboxToDropdown() {
        if let old = UserDefaults.standard.string(forKey: "hideMenubarIcon") {
            if old == "true" {
                UserDefaults.standard.set("3", forKey: "menubarIcon")
            }
        }
    }

    private static func migratePreferenceValue(_ preference: String, _ oldAndNew: [String: String]) {
        if let old = UserDefaults.standard.string(forKey: preference),
           let new = oldAndNew[old] {
            UserDefaults.standard.set(new, forKey: preference)
        }
    }
}

/// workaround to silence compiler warning
private protocol AvoidDeprecationWarnings {
    static func migrateLoginItem()
}

extension PreferencesMigrations: AvoidDeprecationWarnings {}
