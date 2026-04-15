import Foundation
import CoreGraphics

final class WindowCaptureRequestCoordinator {
    static let shared = WindowCaptureRequestCoordinator()

    struct Activation: Equatable {
        let generation: Int
        let source: RefreshCausedBy
    }

    private struct Entry {
        var latestRequestedGeneration = 0
        var activeGeneration: Int?
        var latestSource: RefreshCausedBy
        init(source: RefreshCausedBy) { self.latestSource = source }
    }

    private let lock = NSLock()
    private var entries = [CGWindowID: Entry]()

    func request(_ wid: CGWindowID, source: RefreshCausedBy) -> Activation? {
        lock.lock()
        defer { lock.unlock() }
        var entry = entries[wid] ?? Entry(source: source)
        entry.latestRequestedGeneration += 1
        entry.latestSource = source
        defer { entries[wid] = entry }
        guard entry.activeGeneration == nil else { return nil }
        entry.activeGeneration = entry.latestRequestedGeneration
        return Activation(generation: entry.activeGeneration!, source: source)
    }

    func shouldApplyResult(for wid: CGWindowID, generation: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[wid]?.latestRequestedGeneration == generation
    }

    func finish(_ wid: CGWindowID, generation: Int) -> Activation? {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[wid], entry.activeGeneration == generation else { return nil }
        guard entry.latestRequestedGeneration != generation else {
            entry.activeGeneration = nil
            entries[wid] = entry
            return nil
        }
        entry.activeGeneration = entry.latestRequestedGeneration
        let activation = Activation(generation: entry.activeGeneration!, source: entry.latestSource)
        entries[wid] = entry
        return activation
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
