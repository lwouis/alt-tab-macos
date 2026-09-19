import Foundation

/// What every provider, decision and repair in the tracking pipeline reports about itself, as one value.
///
/// Two consumers, one schema: `--qa-state` reads `summary` (the current health of each provider), and
/// `--qa-telemetry` drains `ring` for the timeline that explains a visible outcome. The record is FLAT and
/// its fields are a closed set — a wid, a pid, a generation, a reason code, a count. There is deliberately
/// no field a window title, a keystroke or a document name could be written into; `TrackingTelemetryTests`
/// pins the encoded key set so a later field cannot smuggle one in.
///
/// Nothing here decides anything. It is written by the shell after a decision has already been made, so
/// switching telemetry off can never change what AltTab does.
struct TrackingTelemetryState: Equatable {
    static let schemaVersion = 1

    var trackingGeneration: UInt64 = 0
    var lastAttention: AttentionTelemetry?
    var sessionTap = SessionTapTelemetry()
    var axByPid = [Int32: AxProviderTelemetry]()
    var ring = TelemetryRing()
    private var nextSequence: UInt64 = 1

    mutating func bumpTrackingGeneration() {
        trackingGeneration += 1
    }

    /// One committed attention decision, whoever made it. `source` is the provider that named the window and
    /// `reason` the code that lets a disagreement be attributed to a specific rule rather than to "focus".
    mutating func recordAttention(pid: Int32, wid: UInt32?, processGeneration: UInt64?, source: TrackingProvider,
                                  reason: String, status: String, at: TimeInterval) {
        lastAttention = AttentionTelemetry(pid: pid, wid: wid, processGeneration: processGeneration,
            source: source.telemetryName, reason: reason, sourceTimestamp: at, status: status)
        append(kind: .attention, at: at) {
            $0.source = source.telemetryName
            $0.reason = reason
            $0.pid = pid
            $0.wid = wid
            $0.generation = processGeneration
            $0.status = status
        }
    }

    /// A provider named a window and the rules declined it. Recorded as its own event rather than through
    /// `recordAttention`, because `lastAttention` must keep reporting the last COMMITTED decision: a reader
    /// asking "where does the model think the user is" is not helped by the answer it just refused.
    mutating func recordAttentionRefused(pid: Int32, wid: UInt32, source: TrackingProvider, reason: String,
                                         at: TimeInterval) {
        append(kind: .attention, at: at) {
            $0.source = source.telemetryName
            $0.reason = reason
            $0.pid = pid
            $0.wid = wid
            $0.status = "refused"
        }
    }

    /// A per-process AX observer changed state. An observer generation change is a REBUILD, so its attempt
    /// count and last error start again: carrying them across would report a fresh observer as already sick.
    mutating func recordAxProvider(pid: Int32, state: AxProviderLifecycle, observerGeneration: UInt64,
                                   attempts: Int, capabilities: [AxNotificationCapability],
                                   lastError: AxObserverError?, at: TimeInterval) {
        let previous = axByPid[pid]
        let rebuilt = previous != nil && previous!.observerGeneration != observerGeneration
        axByPid[pid] = AxProviderTelemetry(providerState: state.telemetryName,
            observerGeneration: observerGeneration, attempts: rebuilt ? 0 : attempts,
            capabilities: capabilities.map { $0.telemetryName }.sorted(),
            lastError: rebuilt ? nil : lastError?.telemetryName,
            lastNotificationAt: previous?.lastNotificationAt)
        append(kind: .provider, at: at) {
            $0.source = TrackingProvider.accessibility.telemetryName
            $0.pid = pid
            $0.generation = observerGeneration
            $0.status = state.telemetryName
            $0.count = attempts
            $0.reason = lastError?.telemetryName
        }
    }

    mutating func recordAxNotification(pid: Int32, at: TimeInterval) {
        guard var entry = axByPid[pid] else { return }
        entry.lastNotificationAt = at
        axByPid[pid] = entry
    }

    mutating func recordSessionTapLifecycle(installed: Bool, enabled: Bool, at: TimeInterval) {
        sessionTap.installed = installed
        sessionTap.enabled = enabled
        append(kind: .sessionTap, at: at) {
            $0.source = TrackingProvider.annotatedSession.telemetryName
            $0.status = enabled ? "enabled" : (installed ? "disabled" : "uninstalled")
        }
    }

    /// A type-13 event the tap decoded, or refused to. An undecodable event is counted, never guessed at: the
    /// field layout is private, so an unknown one means the OS changed under us and the provider must fail
    /// closed rather than stamp a wid it inferred.
    mutating func recordSessionTapEvent(subtype: Int?, pid: Int32?, wid: UInt32?, decoded: Bool,
                                        at: TimeInterval) {
        if decoded { sessionTap.decodedCount += 1 } else { sessionTap.invalidCount += 1 }
        sessionTap.lastEventAt = at
        sessionTap.lastSubtype = subtype
        append(kind: .sessionTap, at: at) {
            $0.source = TrackingProvider.annotatedSession.telemetryName
            $0.pid = pid
            $0.wid = wid
            $0.subtype = subtype
            $0.status = decoded ? "decoded" : "invalid"
        }
    }

    mutating func drainRecords() -> [TelemetryRecord] {
        ring.drain()
    }

    func summary() -> TrackingTelemetrySummary {
        TrackingTelemetrySummary(v: Self.schemaVersion, trackingGeneration: trackingGeneration,
            lastAttention: lastAttention, sessionTap: sessionTap,
            axByPid: Dictionary(uniqueKeysWithValues: axByPid.map { (String($0.key), $0.value) }),
            recordsBuffered: ring.records.count, recordsDropped: ring.droppedCount)
    }

    @discardableResult
    private mutating func append(kind: TelemetryEventKind, at: TimeInterval,
                                 _ fill: (inout TelemetryRecord) -> Void) -> TelemetryRecord {
        var record = TelemetryRecord(v: Self.schemaVersion, seq: nextSequence, at: at, kind: kind.rawValue)
        nextSequence += 1
        fill(&record)
        ring.append(record)
        return record
    }
}

/// One NDJSON line. Every field beyond `v`/`seq`/`at`/`kind` is optional and omitted when unset, so a record
/// carries only what its own kind observed.
struct TelemetryRecord: Codable, Equatable {
    let v: Int
    let seq: UInt64
    let at: TimeInterval
    let kind: String
    var source: String?
    var reason: String?
    var pid: Int32?
    var wid: UInt32?
    var generation: UInt64?
    var status: String?
    var subtype: Int?
    var count: Int?
}

enum TelemetryEventKind: String {
    case attention
    case provider
    case sessionTap
}

/// A bounded FIFO of records `--qa-telemetry` drains between tests. Bounded because a burst of WindowServer
/// events must not grow memory when nobody is draining; `droppedCount` makes a gap in the timeline visible
/// instead of silent.
struct TelemetryRing: Equatable {
    static let defaultCapacity = 512

    private(set) var records = [TelemetryRecord]()
    private(set) var droppedCount = 0
    var capacity = TelemetryRing.defaultCapacity

    mutating func append(_ record: TelemetryRecord) {
        records.append(record)
        guard records.count > capacity else { return }
        let overflow = records.count - capacity
        records.removeFirst(overflow)
        droppedCount += overflow
    }

    mutating func drain() -> [TelemetryRecord] {
        defer { records.removeAll(keepingCapacity: true) }
        return records
    }
}

struct AttentionTelemetry: Codable, Equatable {
    var pid: Int32
    var wid: UInt32?
    var processGeneration: UInt64?
    var source: String
    var reason: String
    var sourceTimestamp: TimeInterval
    var status: String
}

struct SessionTapTelemetry: Codable, Equatable {
    var installed = false
    var enabled = false
    var decodedCount = 0
    var invalidCount = 0
    var lastEventAt: TimeInterval?
    var lastSubtype: Int?
}

struct AxProviderTelemetry: Codable, Equatable {
    var providerState: String
    var observerGeneration: UInt64
    var attempts: Int
    var capabilities: [String]
    var lastError: String?
    var lastNotificationAt: TimeInterval?
}

struct TrackingTelemetrySummary: Codable, Equatable {
    var v: Int
    var trackingGeneration: UInt64
    var lastAttention: AttentionTelemetry?
    var sessionTap: SessionTapTelemetry
    /// keyed by pid as a string: JSON object keys cannot be integers
    var axByPid: [String: AxProviderTelemetry]
    var recordsBuffered: Int
    var recordsDropped: Int
}

extension TrackingProvider {
    var telemetryName: String {
        switch self {
        case .windowServer: return "ws"
        case .workspace: return "workspace"
        case .accessibility: return "ax"
        case .annotatedSession: return "type13"
        }
    }
}

extension AxProviderLifecycle {
    var telemetryName: String {
        switch self {
        case .unregistered: return "unregistered"
        case .registering: return "registering"
        case .healthy: return "healthy"
        case .degraded: return "degraded"
        case .unresponsive: return "unresponsive"
        case .recovering: return "recovering"
        case .globalPermissionFailure: return "globalPermissionFailure"
        }
    }
}

extension AxNotificationCapability {
    var telemetryName: String {
        switch self {
        case .focusedWindowChanged: return "focusedWindow"
        case .mainWindowChanged: return "mainWindow"
        case .titleChanged: return "titleChanged"
        case .focusedTabChanged: return "focusedTab"
        case .windowCreated: return "windowCreated"
        case .elementDestroyed: return "elementDestroyed"
        }
    }
}

extension AxObserverError {
    var telemetryName: String {
        switch self {
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .cannotComplete: return "cannotComplete"
        case .invalidUIElement: return "invalidUIElement"
        case .apiDisabled: return "apiDisabled"
        case .invalidObserver: return "invalidObserver"
        case .invalidArgument: return "invalidArgument"
        case .genericFailure: return "genericFailure"
        }
    }
}
