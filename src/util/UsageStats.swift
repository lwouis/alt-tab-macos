/// Usage counters, stored as a list of unix-second timestamps per key.
///
/// The timestamps are the storage format, not an implementation detail: `count(_:since:)` slices them by a
/// date window, and `UsageStatsTestable.proFeatureSessionCount` identifies a SESSION by its trigger timestamp
/// and intersects the feature keys against it. Two features recorded in the same `recordTrigger` call share
/// one timestamp by construction, which is what makes that intersect work — so nothing here may round,
/// bucket or de-duplicate them.
///
/// The arrays live in memory and are written back on a debounce: reading the whole array out of `UserDefaults`
/// (an `as? [Int]` conditional cast, per element) and writing it back on every summon showed up on a 51s
/// Instruments trace, against an array that grows all year. The cache is owned by `writeQueue`; reads hop onto it.
struct UsageStats {
    private static let defaults = UserDefaults(suiteName: "\(App.bundleIdentifier).usage")!
    private static let writeQueue = DispatchQueue(label: "UsageStats.writeQueue", qos: .utility)
    private static let maxAge: TimeInterval = 365 * 24 * 3600
    private static let allKeys = ["triggers", "searches", "triggersAppIcons", "triggersTitles", "triggersAutoSize", "triggersExtraShortcuts"]
    /// A summon burst (hold-to-cycle) records repeatedly; coalescing costs at most this much unflushed data
    /// if the app is killed rather than quit, which for usage counters is a better trade than one full array
    /// write per summon. `flushNow` covers the normal quit.
    private static let flushDelay: TimeInterval = 2
    private(set) static var searchRecordedThisSession = false

    /// `writeQueue`-owned. Nil value = not loaded from `UserDefaults` yet.
    private static var cache = [String: [Int]]()
    private static var dirty = Set<String>()
    private static var flushScheduled = false
    #if DEBUG
    /// Set by `QaSurfaces`, so the counts the About window and the Pro prompts quote are the same on every run.
    /// Read in place of what is stored; recording still goes to the real arrays.
    static var qaPinned: [String: [Int]]?
    #endif

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
        SearchDiscoveryHint.shared.searchWasUsed()
        record("searches")
    }

    /// Read once off-main; malformed stored data remains unknown instead of advertising unused Search.
    static func loadPreviousSearch(_ completion: @escaping (Bool?) -> Void) {
        writeQueue.async {
            let raw = defaults.object(forKey: "searches")
            let used = raw == nil ? false : (raw as? [Int]).map { !$0.isEmpty }
            DispatchQueue.main.async { completion(used) }
        }
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
        // One hop for all five keys: this runs on the main thread from the Pro windows and the About tab.
        let keys = ["triggers", "triggersAppIcons", "triggersTitles", "triggersExtraShortcuts", "searches"]
        let t = writeQueue.sync { keys.map { loadOnQueue($0) } }
        return UsageStatsTestable.proFeatureSessionCount(
            triggers: t[0], appIcons: t[1], titles: t[2], extraShortcuts: t[3], searches: t[4])
    }

    static func formatCount(_ n: Int) -> String { UsageStatsTestable.formatCount(n) }

    static func usedProFeatureNames() -> [String] {
        UsageStatsTestable.proFeatureNames().compactMap {
            count($0.key, since: Date.distantPast) > 0 ? $0.name : nil
        }
    }

    static func prune() {
        let cutoff = Int(Date().timeIntervalSince1970 - maxAge)
        writeQueue.async {
            for key in allKeys {
                let timestamps = loadOnQueue(key)
                guard !timestamps.isEmpty else { continue }
                let pruned = timestamps.filter { $0 >= cutoff }
                guard pruned.count != timestamps.count else { continue }
                cache[key] = pruned
                dirty.insert(key)
            }
            flushOnQueue()
        }
    }

    /// Write any pending appends synchronously. Called from `applicationWillTerminate`; a SIGTERM/crash skips
    /// it and loses at most `flushDelay` worth of counters.
    static func flushNow() {
        writeQueue.sync { flushOnQueue() }
    }

    private static func record(_ key: String) {
        let now = Int(Date().timeIntervalSince1970)
        writeQueue.async {
            ensureLoadedOnQueue(key)
            // `subscript(_:default:)` mutates in place; `cache[key] = cache[key]! + [now]` would copy the
            // whole year of timestamps on every summon.
            cache[key, default: []].append(now)
            dirty.insert(key)
            scheduleFlushOnQueue()
        }
    }

    private static func getTimestamps(_ key: String) -> [Int] {
        writeQueue.sync { loadOnQueue(key) }
    }

    // MARK: - writeQueue-only

    private static func ensureLoadedOnQueue(_ key: String) {
        guard cache[key] == nil else { return }
        cache[key] = defaults.array(forKey: key) as? [Int] ?? []
    }

    private static func loadOnQueue(_ key: String) -> [Int] {
        #if DEBUG
        if let qaPinned { return qaPinned[key] ?? [] }
        #endif
        ensureLoadedOnQueue(key)
        return cache[key]!
    }

    private static func scheduleFlushOnQueue() {
        guard !flushScheduled else { return }
        flushScheduled = true
        writeQueue.asyncAfter(deadline: .now() + flushDelay) { flushOnQueue() }
    }

    private static func flushOnQueue() {
        flushScheduled = false
        guard !dirty.isEmpty else { return }
        for key in dirty {
            guard let timestamps = cache[key] else { continue }
            defaults.set(timestamps, forKey: key)
        }
        dirty.removeAll()
    }
}
