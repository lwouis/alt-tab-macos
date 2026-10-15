/// Usage counters, stored as a list of unix-second timestamps per key.
///
/// The timestamps are the storage format, not an implementation detail: `count(_:since:)` and the trial
/// evidence slice them by a date window, so nothing here may round, bucket or de-duplicate them.
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
    private static var malformed = Set<String>()
    private static var knownHistory = Set<String>()
    private static var flushScheduled = false
    #if DEBUG
    /// Set by the QA menu's history controls. Replaces the trial history the Pro journey reads.
    static var qaEvidence: ProJourneyEvidence?
    /// Set by `QaSurfaces`, so the counts the About window and the Pro prompts quote are the same on every run.
    /// Read in place of what is stored; recording still goes to the real arrays.
    static var qaPinned: [String: [Int]]?
    #endif

    static func recordTrigger(_ shortcutIndex: Int) {
        let timestamp = Int(Date().timeIntervalSince1970)
        if case .trial = LicenseManager.shared.state, !LicenseManager.shared.isMocked {
            DispatchQueue.main.async { rememberTrialShortcut(shortcutIndex) }
        }
        record("triggers", at: timestamp)
        if shortcutIndex > 0 && shortcutIndex < Preferences.maxShortcutCount {
            record("triggersExtraShortcuts", at: timestamp)
            SearchDiscoveryHint.shared.extraShortcutWasUsed()
        }
        let style = Preferences.effectiveAppearanceStyle(shortcutIndex)
        if style == .appIcons { record("triggersAppIcons", at: timestamp) }
        if style == .titles { record("triggersTitles", at: timestamp) }
        if Preferences.effectiveAppearanceSize(shortcutIndex) == .auto { record("triggersAutoSize", at: timestamp) }
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

    /// Every write is a message to cfprefsd, and most summons repeat the last shortcut.
    private static func rememberTrialShortcut(_ index: Int) {
        let key = "proJourney.lastTrialShortcut"
        guard ProTransitionState.defaults.object(forKey: key) as? Int != index else { return }
        ProTransitionState.defaults.set(index, forKey: key)
    }

    static func loadPreviousExtraShortcut(_ completion: @escaping (Bool?) -> Void) {
        writeQueue.async {
            let raw = defaults.object(forKey: "triggersExtraShortcuts")
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

    static func formatCount(_ n: Int) -> String { UsageStatsTestable.formatCount(n) }

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

    private static func record(_ key: String, at timestamp: Int = Int(Date().timeIntervalSince1970)) {
        writeQueue.async {
            ensureLoadedOnQueue(key)
            // `subscript(_:default:)` mutates in place; appending with array concatenation would copy the
            // whole year of timestamps on every summon.
            cache[key, default: []].append(timestamp)
            knownHistory.insert(key)
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
        let raw = defaults.object(forKey: key)
        if raw != nil && !(raw is [Int]) {
            malformed.insert(key)
        }
        if raw is [Int] { knownHistory.insert(key) }
        cache[key] = raw as? [Int] ?? []
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

extension UsageStats {
    static func loadTrialEvidence(_ completion: @escaping (ProJourneyEvidence) -> Void) {
        guard LicenseManager.shared.state != .proExpired else { completion(ProJourneyEvidence()); return }
        #if DEBUG
        if let qaEvidence { completion(qaEvidence); return }
        if LicenseManager.shared.isMocked {
            completion(ProJourneyEvidence(searches: qaPinned?["searches"]?.count,
                extraShortcuts: qaPinned?["triggersExtraShortcuts"]?.count))
            return
        }
        #endif
        let start = LicenseManager.shared.trialStartDate
        let end = start?.addingTimeInterval(14 * 86400)
        let now = LicenseManager.shared.clock.now
        let style = ProTransitionState.defaults.object(forKey: "proJourney.adoptedStyle") as? Int
        let auto = ProTransitionState.defaults.object(forKey: "proJourney.usedAuto") as? Bool
        writeQueue.async {
            func count(_ key: String) -> Int? {
                let saved = "proJourney.trialCount.\(key)"
                if let count = ProTransitionState.defaults.object(forKey: saved) as? Int {
                    return count
                }
                guard !malformed.contains(key) else { return nil }
                let raw = knownHistory.contains(key) ? cache[key] : defaults.object(forKey: key) as? [Int]
                let count = ProJourneyEvidence.count(raw, start: start, end: end, now: now)
                if let end, now >= end, let count {
                    ProTransitionState.defaults.set(count, forKey: saved)
                }
                return count
            }
            let evidence = ProJourneyEvidence(
                searches: count("searches"),
                extraShortcuts: count("triggersExtraShortcuts"),
                adoptedStyle: style,
                usedAuto: auto
            )
            DispatchQueue.main.async { completion(evidence) }
        }
    }
}
