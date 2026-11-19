import Foundation
import CommonCrypto

/// Local assignment and exposure bookkeeping. Only the arm's opaque value may leave the Mac.
final class LateReminderExperiment {
    enum Arm: String { case treatment = "t", control = "c" }

    private static let prefix = "lateReminder."
    private let defaults: UserDefaults
    private let fingerprint: () -> String
    private let scheduleCheckoutTimeout: (DispatchWorkItem) -> Void
    private var armCompletions = [(Arm) -> Void]()

    struct Context {
        var now: Date
        var trialStart: Date?
        var isFree: Bool
        var optedOut: Bool
        var lastMessage: Date?
        var calendar = Calendar.current

        var inPopulation: Bool {
            guard isFree, !optedOut, let trialStart else { return false }
            return now.timeIntervalSince(trialStart) >= 63 * 86400
        }

        var quietForSevenDays: Bool {
            lastMessage.map { now.timeIntervalSince($0) >= 7 * 86400 } ?? true
        }
    }

    init(defaults: UserDefaults, fingerprint: @escaping () -> String = {
        MachineFingerprint.get(keychain: SystemKeychain(service: LicenseManager.keychainService))
    }, scheduleCheckoutTimeout: @escaping (DispatchWorkItem) -> Void = {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: $0)
    }) {
        self.defaults = defaults
        self.fingerprint = fingerprint
        self.scheduleCheckoutTimeout = scheduleCheckoutTimeout
    }

    /// SHA-256 of the UTF-8 salt, a NUL separator and the unchanged machine fingerprint; first (high) bit.
    /// The salt is a permanent experiment identifier, including its date-shaped suffix.
    static func assign(_ fingerprint: String) -> Arm {
        let data = Data(("AltTab.late-reminder.2026-12-07.v1\0" + fingerprint).utf8)
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return digest[0] & 0x80 == 0 ? .treatment : .control
    }

    /// Keychain fallback can block, so fingerprint acquisition never runs on the switching or UI thread.
    func loadArm(_ completion: @escaping (Arm) -> Void) {
        if let arm = defaults.string(forKey: Self.prefix + "arm").flatMap(Arm.init(rawValue:)) {
            completion(arm)
            return
        }
        armCompletions.append(completion)
        guard armCompletions.count == 1 else { return }
        DispatchQueue.global(qos: .utility).async { [fingerprint] in
            let arm = Self.assign(fingerprint())
            DispatchQueue.main.async { [self] in
                defaults.set(arm.rawValue, forKey: Self.prefix + "arm")
                let completions = armCompletions
                armCompletions.removeAll()
                completions.forEach { $0(arm) }
            }
        }
    }

    func recordActivity(_ context: Context) {
        guard !usedToday(context) else { return }
        defaults.set(context.now, forKey: Self.prefix + "lastUseAt")
    }

    private func usedToday(_ context: Context) -> Bool {
        guard let last = defaults.object(forKey: Self.prefix + "lastUseAt") as? Date, last <= context.now else { return false }
        return context.calendar.isDate(last, inSameDayAs: context.now)
    }

    func canOffer(_ context: Context) -> Bool {
        context.inPopulation && usedToday(context) && context.quietForSevenDays &&
            defaults.object(forKey: Self.prefix + "opportunityAt") == nil
    }

    func canAttribute(_ context: Context) -> Bool {
        // Once admitted, the reminder itself must not remove attribution through its message cooldown.
        context.inPopulation && usedToday(context) &&
            (defaults.object(forKey: Self.prefix + "enrolledAt") != nil || context.quietForSevenDays)
    }

    func enroll(at now: Date) {
        guard defaults.object(forKey: Self.prefix + "enrolledAt") == nil else { return }
        defaults.set(now, forKey: Self.prefix + "enrolledAt")
    }

    func checkoutArm(context: @escaping () -> Context, completion: @escaping (Arm?) -> Void) {
        guard canAttribute(context()) else { completion(nil); return }
        var pending: ((Arm?) -> Void)? = completion
        let finish: (Arm?) -> Void = { [self] arm in
            guard let callback = pending else { return }
            pending = nil
            let current = context()
            guard let arm, canAttribute(current) else { callback(nil); return }
            enroll(at: current.now)
            callback(arm)
        }
        // Assignment may outlive the checkout; only the first completion can open or enroll it.
        let timeout = DispatchWorkItem { finish(nil) }
        loadArm { arm in
            timeout.cancel()
            finish(arm)
        }
        if pending != nil { scheduleCheckoutTimeout(timeout) }
    }

    /// Called only for an acknowledged visible reminder or the silent control opportunity.
    func consume(at now: Date) {
        enroll(at: now)
        guard defaults.object(forKey: Self.prefix + "opportunityAt") == nil else { return }
        defaults.set(now, forKey: Self.prefix + "opportunityAt")
    }

    struct Usage {
        let months: Int
        let count: Int?

        /// Rounded 30-day months, capped at 360 days so the entire quoted window fits retained history.
        static func months(since start: Date, now: Date) -> Int {
            min(12, max(2, Int((now.timeIntervalSince(start) / (30 * 86400)).rounded())))
        }

        static func count(_ timestamps: [Int]?, months: Int, now: Date) -> Int? {
            guard let timestamps, timestamps.allSatisfy({ $0 >= 0 }) else { return nil }
            let start = now.addingTimeInterval(-Double(months) * 30 * 86400).timeIntervalSince1970
            return timestamps.filter { Double($0) >= start && Double($0) <= now.timeIntervalSince1970 }.count
        }
    }
}
