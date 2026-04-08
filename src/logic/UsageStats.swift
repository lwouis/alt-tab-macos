struct UsageStats {
    private static let defaults = UserDefaults(suiteName: "\(App.bundleIdentifier).usage")!
    private static let maxAge: TimeInterval = 365 * 24 * 3600
    private static let allKeys = ["triggers", "searches", "triggersAppIcons", "triggersTitles", "triggersAutoSize"]
    private(set) static var searchRecordedThisSession = false

    static func recordTrigger() {
        record("triggers")
        if Preferences.appearanceStyle == .appIcons { record("triggersAppIcons") }
        if Preferences.appearanceStyle == .titles { record("triggersTitles") }
        if Preferences.appearanceSize == .auto { record("triggersAutoSize") }
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

    static func prune() {
        let cutoff = Int(Date().timeIntervalSince1970 - maxAge)
        for key in allKeys {
            let timestamps = getTimestamps(key)
            guard !timestamps.isEmpty else { continue }
            let pruned = timestamps.filter { $0 >= cutoff }
            defaults.set(pruned, forKey: key)
        }
    }

    private static func record(_ key: String) {
        var timestamps = getTimestamps(key)
        timestamps.append(Int(Date().timeIntervalSince1970))
        defaults.set(timestamps, forKey: key)
    }

    private static func getTimestamps(_ key: String) -> [Int] {
        defaults.array(forKey: key) as? [Int] ?? []
    }
}
