struct UsageStats {
    private static let defaults = UserDefaults(suiteName: "\(App.bundleIdentifier).usage")!
    private static let writeQueue = DispatchQueue(label: "UsageStats.writeQueue", qos: .utility)
    private static let maxAge: TimeInterval = 365 * 24 * 3600
    private static let allKeys = ["triggers", "searches", "triggersAppIcons", "triggersTitles", "triggersAutoSize", "triggersExtraShortcuts"]
    private(set) static var searchRecordedThisSession = false

    static func recordTrigger(_ shortcutIndex: Int) {
        record("triggers")
        if shortcutIndex > 0 && shortcutIndex < Preferences.maxShortcutCount { record("triggersExtraShortcuts") }
        let style = Preferences.effectiveAppearanceStyle(shortcutIndex)
        if style == .appIcons { record("triggersAppIcons") }
        if style == .titles { record("triggersTitles") }
        if Preferences.effectiveAppearanceSize(shortcutIndex) == .auto { record("triggersAutoSize") }
    }

    static func recordSearchIfFirst() {
        guard !searchRecordedThisSession else { return }
        searchRecordedThisSession = true
        record("searches")
    }

    static func resetSession() {
        searchRecordedThisSession = false
    }

    static func count(_ key: String, since date: Date) -> Int {
        let threshold = Int(date.timeIntervalSince1970)
        return getTimestamps(key).count { $0 >= threshold }
    }

    static var triggerCount: Int { count("triggers", since: Date.distantPast) }

    static var usedProFeaturesSessionCount: Int {
        UsageStatsTestable.proFeatureSessionCount(
            triggers: getTimestamps("triggers"),
            appIcons: getTimestamps("triggersAppIcons"),
            titles: getTimestamps("triggersTitles"),
            extraShortcuts: getTimestamps("triggersExtraShortcuts"),
            searches: getTimestamps("searches"))
    }

    static func formatCount(_ n: Int) -> String { UsageStatsTestable.formatCount(n) }

    static func usedProFeatureNames() -> [String] {
        UsageStatsTestable.proFeatureNames().compactMap {
            count($0.key, since: Date.distantPast) > 0 ? $0.name : nil
        }
    }

    static func usedAppIconsOrTitles() -> Bool {
        count("triggersAppIcons", since: Date.distantPast) > 0 || count("triggersTitles", since: Date.distantPast) > 0
    }

    static func usedSearch() -> Bool { count("searches", since: Date.distantPast) > 0 }
    static func usedAutoSize() -> Bool { count("triggersAutoSize", since: Date.distantPast) > 0 }
    static func usedExtraShortcuts() -> Bool { count("triggersExtraShortcuts", since: Date.distantPast) > 0 }

    static func prune() {
        let cutoff = Int(Date().timeIntervalSince1970 - maxAge)
        writeQueue.async {
            for key in allKeys {
                let timestamps = getTimestamps(key)
                guard !timestamps.isEmpty else { continue }
                let pruned = timestamps.filter { $0 >= cutoff }
                defaults.set(pruned, forKey: key)
            }
        }
    }

    private static func record(_ key: String) {
        let now = Int(Date().timeIntervalSince1970)
        writeQueue.async {
            var timestamps = getTimestamps(key)
            timestamps.append(now)
            defaults.set(timestamps, forKey: key)
        }
    }

    private static func getTimestamps(_ key: String) -> [Int] {
        defaults.array(forKey: key) as? [Int] ?? []
    }
}
