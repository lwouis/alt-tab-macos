import Foundation
import Darwin

struct StartupRecoveryRecord: Codable, Equatable {
    var failures: Int
    var generation: UUID

    var retryDelay: TimeInterval? {
        switch failures {
        case 1: return 1
        case 2: return 3
        default: return nil
        }
    }
}

/// One record for all mandatory-input failures. A different failing control cannot reset the budget.
/// The separate lock file survives atomic replacement of the record, including across processes.
final class StartupRecoveryStore {
    let directory: URL
    private var recordURL: URL { directory.appendingPathComponent("startup-recovery.json") }

    init(directory: URL) { self.directory = directory }

    func recordFailure() throws -> StartupRecoveryRecord {
        try locked {
            let previous = try readUnlocked()
            let record = StartupRecoveryRecord(failures: min(3, (previous?.failures ?? 0) + 1), generation: UUID())
            try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
            return record
        }
    }

    func read() throws -> StartupRecoveryRecord? { try locked { try readUnlocked() } }

    /// An older healthy instance must not erase a failure recorded by a newer instance.
    func clear(ifUnchanged generation: UUID) throws {
        try locked {
            guard try readUnlocked()?.generation == generation else { return }
            try FileManager.default.removeItem(at: recordURL)
        }
    }

    func retryManually() throws {
        try locked {
            if FileManager.default.fileExists(atPath: recordURL.path) { try FileManager.default.removeItem(at: recordURL) }
        }
    }

    private func readUnlocked() throws -> StartupRecoveryRecord? {
        guard FileManager.default.fileExists(atPath: recordURL.path) else { return nil }
        let record = try JSONDecoder().decode(StartupRecoveryRecord.self, from: Data(contentsOf: recordURL))
        guard (1...3).contains(record.failures) else { throw CocoaError(.fileReadCorruptFile) }
        return record
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("startup-recovery.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(.EIO) }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

struct StartupRecoveryPolicy {
    static let stableInterval: TimeInterval = 60
    private(set) var failed = false
    private var readySince: TimeInterval?

    mutating func beginFailure() -> Bool {
        guard !failed else { return false }
        failed = true
        readySince = nil
        return true
    }

    mutating func becameReady(at uptime: TimeInterval) { if !failed { readySince = uptime } }

    func canClear(at uptime: TimeInterval) -> Bool {
        guard !failed, let readySince else { return false }
        return uptime - readySince >= Self.stableInterval
    }
}
