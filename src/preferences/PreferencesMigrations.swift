import Cocoa

class PreferencesMigrations {
    /// Injectable so tests can run migrations against an isolated `UserDefaults` suite.
    /// Production keeps `.standard`; behavior is unchanged.
    static var defaults = UserDefaults.standard

    static func removeCorruptedPreferences() {
        // from v5.1.0+, there are crash reports of users somehow having their hold shortcuts set to ""
        ["holdShortcut", "holdShortcut2", "holdShortcut3", "holdShortcut4", "holdShortcut5"].forEach {
            if let s = Self.defaults.string(forKey: $0), s == "" {
                Self.defaults.removeObject(forKey: $0)
            }
        }
    }

    static func migratePreferences() {
        let preferencesKey = "preferencesVersion"
        let existingVersion = Self.defaults.string(forKey: preferencesKey)
        ProTransitionState.markFreshInstallIfUnknown(existingVersion == nil)
        if let versionInPlist = existingVersion {
            if versionInPlist != "#VERSION#" && versionInPlist.compare(App.version, options: .numeric) != .orderedDescending {
                updateToNewPreferences(versionInPlist)
            }
        }
        Self.defaults.set(App.version, forKey: preferencesKey)
    }

    static func updateToNewPreferences(_ versionInPlist: String) {
        Logger.debug { "App-version:\(App.version), Plist-version:\(versionInPlist)" }
        for (version, migration) in [
            ("10.13.0", migrateGroupingToPerShortcut),
            ("10.12.0", migrateExceptionsTitleArray),
            ("10.12.0", migrateLanguagePreferenceIndex),
            ("10.2.0", migrateBlacklistToExceptions),
            ("9.0.0", migrateShortcutIndexes),
            ("7.27.0", migrateCursorFollowFocus),
            ("7.26.0", migrateShowWindowlessApps),
            ("7.25.0", migrateHideWindowlessApps),
            ("7.13.1", migrateGestures),
            ("7.8.0", migrateMenubarIconWithNewShownToggle),
            ("7.0.0", migratePreferencesIndexes),
            ("6.43.0", migrateExceptions),
            ("6.28.1", migrateMinMaxWindowsWidthInRow),
            // "Start at login" new implem doesn't use Login Items; we remove the entry from previous versions
            ("6.27.1", { (PreferencesMigrations.self as AvoidDeprecationWarnings.Type).migrateLoginItem() }),
            // "Show windows from:" got the "Active Space" option removed
            ("6.23.0", migrateShowWindowsFrom),
            // nextWindowShortcut used to be able to have modifiers already present in holdShortcut; we remove these
            ("6.18.1", migrateNextWindowShortcuts),
            // dropdowns preferences used to store English text; now they store indexes
            ("6.18.1", migrateDropdownsFromTextToIndexes),
            // the "Hide menubar icon" checkbox was replaced with a dropdown of: icon1, icon2, hidden
            ("6.18.1", migrateMenubarIconFromCheckboxToDropdown),
            // "Show minimized/hidden/fullscreen windows" checkboxes were replaced with dropdowns
            ("6.18.1", migrateShowWindowsCheckboxToDropdown),
            // "Max size on screen" was split into max width and max height
            ("6.18.1", migrateMaxSizeOnScreenToWidthAndHeight),
        ] {
            if shouldRun(versionInPlist, version) {
                migration()
            }
        }
    }

    static func shouldRun(_ versionInPlist: String, _ versionThreshold: String) -> Bool {
        // x.compare(y) is .orderedDescending if x > y
        versionInPlist.compare(versionThreshold, options: .numeric) != .orderedDescending
    }

    // showAppsOrWindows + showTabsAsWindows moved from global to per-shortcut. Copy the previous
    // global value into every indexed key so the user's chosen grouping behaviour survives the
    // upgrade. `showTabsAsWindows` also changed type from `Bool` to `GroupTabsPreference` so we
    // map "true" → "1" (separateWindows) and "false" → "0" (singleWindow) — for both the old
    // global key being copied and any pre-existing per-shortcut keys that landed as Bool strings
    // before this migration was wired up.
    static func migrateGroupingToPerShortcut() {
        if let old = Self.defaults.string(forKey: "showAppsOrWindows") {
            for i in 0...Preferences.maxShortcutCount {
                let key = Preferences.indexToName("showAppsOrWindows", i)
                if Self.defaults.string(forKey: key) == nil {
                    Self.defaults.set(old, forKey: key)
                }
            }
            Self.defaults.removeObject(forKey: "showAppsOrWindows")
        }
        let oldGlobal = Self.defaults.string(forKey: "showTabsAsWindows")
        let convertedGlobal = oldGlobal.map { ($0 == "true") ? "1" : "0" }
        for i in 0...Preferences.maxShortcutCount {
            let key = Preferences.indexToName("showTabsAsWindows", i)
            if let existing = Self.defaults.string(forKey: key) {
                if existing == "true" || existing == "false" {
                    Self.defaults.set(existing == "true" ? "1" : "0", forKey: key)
                }
            } else if let convertedGlobal {
                Self.defaults.set(convertedGlobal, forKey: key)
            }
        }
        if oldGlobal != nil {
            Self.defaults.removeObject(forKey: "showTabsAsWindows")
        }
    }

    static func migrateBlacklistToExceptions() {
        let oldKey = "blacklist"
        let newKey = "exceptions"
        guard let oldValue = Self.defaults.string(forKey: oldKey) else { return }
        if Self.defaults.string(forKey: newKey) == nil {
            Self.defaults.set(oldValue, forKey: newKey)
        }
        Self.defaults.removeObject(forKey: oldKey)
    }

    // LanguagePreference enum dropped from 59 to 21 cases; stored indexes need remapping.
    // Removed languages map to systemDefault (0). Map below uses the pre-trim enum order.
    static func migrateLanguagePreferenceIndex() {
        let oldToNew: [Int: Int] = [
            0: 0, 1: 1, 5: 2, 7: 3, 8: 4, 9: 5, 13: 6, 19: 7, 23: 8, 25: 9,
            30: 10, 31: 11, 32: 12, 38: 13, 42: 14, 44: 15, 52: 16, 54: 17,
            55: 18, 56: 19, 57: 20, 58: 21,
        ]
        guard let stored = Self.defaults.string(forKey: "language"), let oldIndex = Int(stored) else { return }
        let newIndex = oldToNew[oldIndex] ?? 0
        Self.defaults.set(String(newIndex), forKey: "language")
    }

    // gesture index moved from 3 (suffix "4") to 9 (suffix "10"); set shortcutCount for users who had a 3rd shortcut
    static func migrateShortcutIndexes() {
        let gesturePrefs = [
            "nextWindowGesture", "appsToShow", "spacesToShow", "screensToShow",
            "showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows",
            "showWindowlessApps", "windowOrder", "shortcutStyle",
        ]
        for baseName in gesturePrefs {
            if let old = Self.defaults.string(forKey: baseName + "4") {
                Self.defaults.set(old, forKey: baseName + "10")
                Self.defaults.removeObject(forKey: baseName + "4")
            }
        }
        let allPerShortcutPrefs = gesturePrefs + ["holdShortcut", "nextWindowShortcut"]
        let hasThirdShortcut = allPerShortcutPrefs.contains {
            Self.defaults.string(forKey: $0 + "3") != nil
        }
        if hasThirdShortcut {
            Self.defaults.set("3", forKey: "shortcutCount")
        }
    }

    // cursorFollowFocus was a toggle. It's now a dropdown
    // before: cursorFollowFocusEnabled: true/false
    // after: cursorFollowFocus: 0 (never), 1 (always), 2 (differentScreen)
    static func migrateCursorFollowFocus() {
        if let old = Self.defaults.string(forKey: "cursorFollowFocusEnabled") {
            Self.defaults.set(old == "true" ? 1 : 0, forKey: "cursorFollowFocus")
        }
    }

    // allow showWindowlessApps to have the third value `show`, in addition to `hide` and `showAtTheEnd`
    // before: showAtTheEnd: 0, hide: 1
    // after: show: 0, hide: 1, showAtTheEnd: 2
    static func migrateShowWindowlessApps() {
        for index in ["", "2", "3", "4"] {
            if let old = Self.defaults.string(forKey: "showWindowlessApps" + index) {
                Self.defaults.set(old == "0" ? 2 : 1, forKey: "showWindowlessApps" + index)
            }
        }
    }

    // we moved from global to per-shortcut
    static func migrateHideWindowlessApps() {
        if let old = Self.defaults.string(forKey: "hideWindowlessApps") {
            for index in ["", "2", "3", "4"] {
                Self.defaults.set(old == "true" ? 1 : 0, forKey: "showWindowlessApps" + index)
            }
        }
    }

    // we split gestures from disabled, 3-finger, 4-finger to: disabled, 3-finger-horizontal, 3-finger-vertical, 4-finger-horizontal, 4-finger-vertical
    // no need to map 0 -> 0 (disabled -> disabled)
    // no need to map 1 -> 1 (3-finger -> 3-finger-horizontal)
    // we need to map 2 -> 3 (4-finger -> 4-finger-horizontal)
    static func migrateGestures() {
        if let old = Self.defaults.string(forKey: "nextWindowGesture") {
            if old == "2" { // 2 (4-finger) -> 3 (4-finger-horizontal)
                Self.defaults.set("3", forKey: "nextWindowGesture")
            }
        }
    }

    /// we added the new menubarIconShown toggle. It replaces menubarIcon having value "3" which would hide the icon
    /// there are now 2 preferences : menubarIconShown is a boolean, and menubarIcon has values 0, 1, 2
    static func migrateMenubarIconWithNewShownToggle() {
        if let old = Self.defaults.string(forKey: "menubarIcon") {
            if old == "3" {
                Self.defaults.set("0", forKey: "menubarIcon")
                Self.defaults.set("false", forKey: "menubarIconShown")
            }
        }
    }

    // we want to rely on preferences numbers to match the enum indexes. This migration realigns existing desyncs
    static func migratePreferencesIndexes() {
        // migrate spacesToShow from 1 to 2. 1 was removed a while ago. 1=active => 2=>visible
        ["", "2", "3", "4", "5"].forEach { suffix in
            if let spacesToShow = Self.defaults.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "1" {
                    Self.defaults.set("2", forKey: "spacesToShow" + suffix)
                }
            }
        }
        // migrate spacesToShow from 0 to 2 and 2 to 0. 0 used to be end, 2 used to be start; they got switch for the UI order
        ["", "2", "3", "4", "5"].forEach { suffix in
            if let spacesToShow = Self.defaults.string(forKey: "titleTruncation" + suffix) {
                if spacesToShow == "0" {
                    Self.defaults.set("2", forKey: "titleTruncation" + suffix)
                }
                if spacesToShow == "2" {
                    Self.defaults.set("0", forKey: "titleTruncation" + suffix)
                }
            }
        }
    }

    static func migrateExceptions() {
        var entries = [ExceptionEntry]()
        if let old = Self.defaults.string(forKey: "dontShowBlacklist") {
            entries.append(contentsOf: oldExceptionEntriesToNewOnes(old, .always, .none))
        }
        if let old = Self.defaults.string(forKey: "disableShortcutsBlacklist") {
            let onlyFullscreen = Self.defaults.bool(forKey: "disableShortcutsBlacklistOnlyFullscreen")
            entries.append(contentsOf: oldExceptionEntriesToNewOnes(old, .none, onlyFullscreen ? .whenFullscreen : .always))
        }
        if entries.count > 0 {
            Self.defaults.set(Preferences.jsonEncode(entries), forKey: "exceptions")
            ["dontShowBlacklist", "disableShortcutsBlacklist", "disableShortcutsBlacklistOnlyFullscreen"].forEach {
                Self.defaults.removeObject(forKey: $0)
            }
        }
    }

    static func oldExceptionEntriesToNewOnes(_ old: String, _ hide: ExceptionHidePreference, _ ignore: ExceptionIgnorePreference) -> [ExceptionEntry] {
        old.split(separator: "\n").compactMap { (e) -> ExceptionEntry? in
            let line = e.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                return nil
            }
            return ExceptionEntry(bundleIdentifier: line, hide: hide, ignore: ignore)
        }
    }

    // windowTitleContains went from String? to [String]? to support multiple title patterns per app.
    // Idempotent: when the data is already in array form, decoding into LegacyExceptionEntry fails and we early-return.
    static func migrateExceptionsTitleArray() {
        struct LegacyExceptionEntry: Codable {
            var bundleIdentifier: String
            var hide: ExceptionHidePreference
            var ignore: ExceptionIgnorePreference
            var windowTitleContains: String?
        }
        guard let raw = Self.defaults.string(forKey: "exceptions"),
              let data = raw.data(using: .utf8),
              let legacy = try? JSONDecoder().decode([LegacyExceptionEntry].self, from: data) else {
            return
        }
        let migrated = legacy.map { old -> ExceptionEntry in
            let patterns: [String]?
            if let s = old.windowTitleContains, !s.isEmpty {
                patterns = [s]
            } else {
                patterns = nil
            }
            return ExceptionEntry(bundleIdentifier: old.bundleIdentifier, hide: old.hide, ignore: old.ignore, windowTitleContains: patterns)
        }
        Self.defaults.set(Preferences.jsonEncode(migrated), forKey: "exceptions")
    }

    static func migrateMinMaxWindowsWidthInRow() {
        ["windowMinWidthInRow", "windowMaxWidthInRow"].forEach {
            if let old = Self.defaults.string(forKey: $0) {
                if old == "0" {
                    Self.defaults.set("1", forKey: $0)
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
                    // resolve without mounting so a login item bookmark pointing to a dead SMB share
                    // can't freeze the main thread mounting it synchronously (#5773)
                    let flags = LSSharedFileListResolutionFlags(kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes)
                    loginItemsSnapshot.forEach {
                        if (LSSharedFileListItemCopyDisplayName($0).takeRetainedValue() == itemName) ||
                               (LSSharedFileListItemCopyResolvedURL($0, flags, nil)?.takeRetainedValue() == itemUrl) {
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

    static func migrateShowWindowsFrom() {
        ["", "2"].forEach { suffix in
            if let spacesToShow = Self.defaults.string(forKey: "spacesToShow" + suffix) {
                if spacesToShow == "2" {
                    Self.defaults.set("1", forKey: "screensToShow" + suffix)
                    Self.defaults.set("1", forKey: "spacesToShow" + suffix)
                } else if spacesToShow == "1" {
                    Self.defaults.set("1", forKey: "screensToShow" + suffix)
                }
            }
        }
    }

    static func migrateNextWindowShortcuts() {
        ["", "2"].forEach { suffix in
            if let oldHoldShortcut = Self.defaults.string(forKey: "holdShortcut" + suffix),
               let oldNextWindowShortcut = Self.defaults.string(forKey: "nextWindowShortcut" + suffix) {
                let nextWindowShortcutCleanedUp = oldHoldShortcut.reduce(oldNextWindowShortcut, { $0.replacingOccurrences(of: String($1), with: "") })
                if oldNextWindowShortcut != nextWindowShortcutCleanedUp {
                    Self.defaults.set(nextWindowShortcutCleanedUp, forKey: "nextWindowShortcut" + suffix)
                }
            }
        }
    }

    static func migrateMaxSizeOnScreenToWidthAndHeight() {
        if let old = Self.defaults.string(forKey: "maxScreenUsage") {
            Self.defaults.set(old, forKey: "maxWidthOnScreen")
            Self.defaults.set(old, forKey: "maxHeightOnScreen")
        }
    }

    static func migrateShowWindowsCheckboxToDropdown() {
        ["showMinimizedWindows", "showHiddenWindows", "showFullscreenWindows"]
            .flatMap { [$0, $0 + "2"] }
            .forEach {
                if let old = Self.defaults.string(forKey: $0) {
                    if old == "true" {
                        Self.defaults.set(ShowHowPreference.show.indexAsString, forKey: $0)
                    } else if old == "false" {
                        Self.defaults.set(ShowHowPreference.hide.indexAsString, forKey: $0)
                    }
                }
            }
    }

    static func migrateDropdownsFromTextToIndexes() {
        migratePreferenceValue("theme", [" macOS": "0", "❖ Windows 10": "1"])
        // "Main screen" was renamed to "Active screen"
        migratePreferenceValue("showOnScreen", ["Main screen": "0", "Active screen": "0", "Screen including mouse": "1"])
        migratePreferenceValue("appsToShow", ["All apps": "0", "Active app": "1"])
        migratePreferenceValue("spacesToShow", ["All spaces": "0", "Active space": "1"])
        migratePreferenceValue("screensToShow", ["All screens": "0", "Screen showing AltTab": "1"])
    }

    static func migrateMenubarIconFromCheckboxToDropdown() {
        if let old = Self.defaults.string(forKey: "hideMenubarIcon") {
            if old == "true" {
                Self.defaults.set("3", forKey: "menubarIcon")
            }
        }
    }

    static func migratePreferenceValue(_ preference: String, _ oldAndNew: [String: String]) {
        if let old = Self.defaults.string(forKey: preference),
           let new = oldAndNew[old] {
            Self.defaults.set(new, forKey: preference)
        }
    }

    static func migrateShortcutPreferencesToSecureCoding() {
        Preferences.allShortcutPreferenceKeys.forEach {
            let key = $0
            guard let oldValue = Self.defaults.object(forKey: key) else { return }
            if let oldStorage = oldValue as? [String: Any] {
                let (isValid, shortcut) = Preferences.decodeShortcutStorage(oldStorage)
                guard isValid else {
                    Self.defaults.removeObject(forKey: key)
                    return
                }
                Self.defaults.set(Preferences.shortcutStorage(shortcut, oldStorage["string"] as? String), forKey: key)
                return
            }
            if let oldDataValue = oldValue as? Data {
                let (isValid, shortcut) = Preferences.unarchiveShortcut(oldDataValue)
                guard isValid else {
                    Self.defaults.removeObject(forKey: key)
                    return
                }
                Self.defaults.set(Preferences.shortcutStorage(shortcut, nil), forKey: key)
                return
            }
            guard let oldStringValue = oldValue as? String else {
                Self.defaults.removeObject(forKey: key)
                return
            }
            if oldStringValue.isEmpty {
                Self.defaults.set(Preferences.shortcutStorage(nil, ""), forKey: key)
                return
            }
            guard let migratedShortcut = Preferences.shortcutFromKeyEquivalent(oldStringValue) else {
                Self.defaults.removeObject(forKey: key)
                return
            }
            Self.defaults.set(Preferences.shortcutStorage(migratedShortcut, oldStringValue), forKey: key)
        }
    }
}

/// workaround to silence compiler warning
private protocol AvoidDeprecationWarnings {
    static func migrateLoginItem()
}

extension PreferencesMigrations: AvoidDeprecationWarnings {}
