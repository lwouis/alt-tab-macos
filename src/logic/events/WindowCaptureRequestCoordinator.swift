import Foundation
import CoreGraphics

final class WindowCaptureRequestCoordinator {
    static let shared = WindowCaptureRequestCoordinator()

    private struct Entry {
        var latestRequestedGeneration = 0
        var activeGeneration: Int?
    }

    private let lock = NSLock()
    private var entries = [CGWindowID: Entry]()

    func request(_ wid: CGWindowID) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[wid] ?? Entry()
        entry.latestRequestedGeneration += 1
        defer { entries[wid] = entry }
        guard entry.activeGeneration == nil else { return nil }
        entry.activeGeneration = entry.latestRequestedGeneration
        return entry.activeGeneration
    }

    func shouldApplyResult(for wid: CGWindowID, generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[wid]?.latestRequestedGeneration == generation
    }

    func finish(_ wid: CGWindowID, generation: Int) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[wid], entry.activeGeneration == generation else { return nil }
        guard entry.latestRequestedGeneration != generation else {
            entry.activeGeneration = nil
            entries[wid] = entry
            return nil
        }
        entry.activeGeneration = entry.latestRequestedGeneration
        entries[wid] = entry
        return entry.activeGeneration
    }

    func cancel(_ wid: CGWindowID) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[wid] else { return }
        entry.latestRequestedGeneration += 1
        entry.activeGeneration = nil
        entries[wid] = entry
    }
}
