import XCTest

final class TrackingTelemetryTests: XCTestCase {
    /// Every key the record schema is allowed to encode. A field a title or a keystroke could be written into
    /// has to be added here first, which is the point: the review is forced, not hoped for.
    private static let allowedKeys: Set<String> = [
        "v", "seq", "at", "kind", "source", "reason", "pid", "wid", "generation", "status",
        "subtype", "count",
    ]

    private func record(_ state: TrackingTelemetryState) -> TelemetryRecord {
        state.ring.records.last!
    }

    /// The same `Codable` path `--qa-telemetry` encodes its drain through, one record at a time so a test can
    /// read the key set of a single line. Sorted keys make a failure diff cleanly.
    private func encoded(_ record: TelemetryRecord) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try! encoder.encode(record), encoding: .utf8)!
    }

    // MARK: record schema

    /// Records carry a monotonic sequence that survives a drain, so batches stitch together.
    func testSequenceIsMonotonicAcrossDrains() {
        var state = TrackingTelemetryState()
        state.recordSessionTapEvent(subtype: 9, pid: 1, wid: 2, decoded: true, at: 1)
        XCTAssertEqual(state.drainRecords().map { $0.seq }, [1])
        state.recordSessionTapEvent(subtype: 9, pid: 1, wid: 2, decoded: true, at: 2)
        state.recordSessionTapEvent(subtype: 9, pid: 1, wid: 2, decoded: true, at: 3)
        XCTAssertEqual(state.drainRecords().map { $0.seq }, [2, 3])
    }

    /// Unset fields are omitted from the encoding, so a record carries only what its own kind observed. A
    /// type-13 event that failed to decode names no window, and the record must not carry an empty or
    /// invented one.
    func testUnsetFieldsAreOmittedFromTheEncoding() {
        var state = TrackingTelemetryState()
        state.recordSessionTapEvent(subtype: nil, pid: nil, wid: nil, decoded: false, at: 7)
        let json = String(decoding: try! JSONEncoder().encode(record(state)), as: UTF8.self)
        XCTAssertFalse(json.contains("\"wid\""))
        XCTAssertFalse(json.contains("\"pid\""))
        XCTAssertTrue(json.contains("\"kind\":\"sessionTap\""))
    }

    /// The encoded key set is closed: no title, no keystroke, no document name can ride along.
    func testEncodedKeysStayWithinTheAllowList() {
        var state = TrackingTelemetryState()
        state.recordAttention(pid: 4, wid: 5, processGeneration: 2, source: .accessibility, reason: "axFocusedRead", status: "committed", at: 1)
        state.recordAttentionRefused(pid: 4, wid: 6, source: .annotatedSession, reason: "ineligible", at: 2)
        state.recordAxProvider(pid: 4, state: .healthy, observerGeneration: 1, attempts: 2,
            capabilities: [.mainWindowChanged], lastError: .cannotComplete, at: 3)
        state.recordSessionTapEvent(subtype: 9, pid: 4, wid: 5, decoded: true, at: 4)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for line in state.drainRecords().map({ String(decoding: try! encoder.encode($0), as: UTF8.self) }) {
            let keys = Set(line.split(separator: ",").compactMap { chunk -> String? in
                guard let colon = chunk.firstIndex(of: ":") else { return nil }
                return String(chunk[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "{\" ")).replacingOccurrences(of: "\"", with: "")
            })
            XCTAssertTrue(keys.isSubset(of: Self.allowedKeys), "unexpected keys \(keys.subtracting(Self.allowedKeys))")
        }
    }

    // MARK: ring buffer

    /// The ring is bounded: a burst nobody drains must not grow memory.
    func testRingDropsOldestBeyondCapacity() {
        var state = TrackingTelemetryState()
        state.ring.capacity = 3
        for i in 1...5 {
            state.recordSessionTapEvent(subtype: 9, pid: 1, wid: UInt32(i), decoded: true, at: TimeInterval(i))
        }
        XCTAssertEqual(state.ring.records.map { $0.seq }, [3, 4, 5])
        XCTAssertEqual(state.ring.droppedCount, 2)
    }

    func testDrainEmptiesTheRing() {
        var state = TrackingTelemetryState()
        state.recordSessionTapEvent(subtype: 9, pid: 1, wid: 2, decoded: true, at: 1)
        XCTAssertEqual(state.drainRecords().count, 1)
        XCTAssertTrue(state.drainRecords().isEmpty)
    }

    // MARK: attention

    func testAttentionUpdatesLastAttention() {
        var state = TrackingTelemetryState()
        state.recordAttention(pid: 7, wid: 11, processGeneration: 3, source: .annotatedSession, reason: "click", status: "committed", at: 12)
        XCTAssertEqual(state.lastAttention, AttentionTelemetry(pid: 7, wid: 11, processGeneration: 3,
            source: "type13", reason: "click", sourceTimestamp: 12, status: "committed"))
    }

    /// A refused result is recorded, but `lastAttention` keeps the last committed one.
    func testRefusedAttentionDoesNotOverwriteLastAttention() {
        var state = TrackingTelemetryState()
        state.recordAttention(pid: 1, wid: 2, processGeneration: 1, source: .workspace, reason: "activation", status: "committed", at: 1)
        state.recordAttentionRefused(pid: 1, wid: 9, source: .accessibility, reason: "ignored.inactiveProcess",
            at: 2)
        XCTAssertEqual(state.lastAttention?.wid, 2)
        XCTAssertEqual(record(state).status, "refused")
        XCTAssertEqual(record(state).wid, 9)
    }

    // MARK: AX provider health

    func testProviderHealthIsKeptPerPid() {
        var state = TrackingTelemetryState()
        state.recordAxProvider(pid: 1, state: .healthy, observerGeneration: 1, attempts: 1,
            capabilities: [.focusedWindowChanged], lastError: nil, at: 1)
        state.recordAxProvider(pid: 2, state: .unresponsive, observerGeneration: 1, attempts: 5,
            capabilities: [], lastError: .cannotComplete, at: 2)
        XCTAssertEqual(state.axByPid[1]?.providerState, "healthy")
        XCTAssertEqual(state.axByPid[2]?.lastError, "cannotComplete")
    }

    /// A rebuilt observer starts clean, or a fresh one would be reported as already sick.
    func testObserverRebuildResetsAttemptsAndError() {
        var state = TrackingTelemetryState()
        state.recordAxProvider(pid: 1, state: .unresponsive, observerGeneration: 1, attempts: 4,
            capabilities: [], lastError: .cannotComplete, at: 1)
        state.recordAxProvider(pid: 1, state: .registering, observerGeneration: 2, attempts: 4,
            capabilities: [], lastError: .cannotComplete, at: 2)
        XCTAssertEqual(state.axByPid[1]?.attempts, 0)
        XCTAssertNil(state.axByPid[1]?.lastError)
    }

    func testCapabilitiesAreReportedSorted() {
        var state = TrackingTelemetryState()
        state.recordAxProvider(pid: 1, state: .healthy, observerGeneration: 1, attempts: 1,
            capabilities: [.titleChanged, .focusedWindowChanged], lastError: nil, at: 1)
        XCTAssertEqual(state.axByPid[1]?.capabilities, ["focusedWindow", "titleChanged"])
    }

    // MARK: session tap

    func testTapCountsDecodedAndInvalidSeparately() {
        var state = TrackingTelemetryState()
        state.recordSessionTapEvent(subtype: 9, pid: 1, wid: 2, decoded: true, at: 1)
        state.recordSessionTapEvent(subtype: nil, pid: nil, wid: nil, decoded: false, at: 2)
        XCTAssertEqual(state.sessionTap.decodedCount, 1)
        XCTAssertEqual(state.sessionTap.invalidCount, 1)
        XCTAssertEqual(state.sessionTap.lastEventAt, 2)
    }


    // MARK: summary

    func testSummaryKeysPidsAsStrings() {
        var state = TrackingTelemetryState()
        state.recordAxProvider(pid: 42, state: .healthy, observerGeneration: 1, attempts: 0,
            capabilities: [], lastError: nil, at: 1)
        XCTAssertEqual(state.summary().axByPid.keys.sorted(), ["42"])
        XCTAssertEqual(state.summary().v, TrackingTelemetryState.schemaVersion)
    }
}
