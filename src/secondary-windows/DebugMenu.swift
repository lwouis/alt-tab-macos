#if DEBUG
import Cocoa
import CoreText

final class DebugMenu: NSPanel {
    static let width = CGFloat(400)
    static let height = CGFloat(200)
    static var shared: DebugMenu?

    private let graphView = QueueGraphView()
    private var timer: DispatchSourceTimer?
    private let samplers: [Sampler]

    struct Sampler {
        let label: String
        let read: () -> Double
    }

    // Single entry point, driven by the QAMenu "Live queue graph" checkbox (and restored on launch
    // when previously left on). `on` creates+shows+starts; `off` stops all sampling and hides.
    static func setEnabled(_ on: Bool) {
        if on {
            if shared == nil { shared = DebugMenu(makeSamplers()) }
            shared?.orderFront(nil)
            shared?.start()
        } else {
            shared?.stop()
            shared?.orderOut(nil)
        }
    }

    // Queue depths only — each spikes with work and falls back to 0 when idle. cgsCall is the WindowServer
    // read lane (discovery + per-window state + Space topology); a sustained backlog there is the signal a
    // slow WindowServer query is starving reads. The AX pools (firstTry/scan/retry) carry the remaining
    // on-demand AX reads + element acquires.
    private static func makeSamplers() -> [Sampler] {
        let scheduler = AXCallScheduler.shared
        let queues: [LabeledOperationQueue] = [
            BackgroundWork.screenshotsQueue,
            BackgroundWork.accessibilityCommandsQueue,
            scheduler.axQueryFirstTryQueue,
            scheduler.axQueryScanQueue,
            scheduler.axQueryRetryQueue,
            CGSCallScheduler.debugQueue,
            ProcessCallScheduler.debugQueue,
        ]
        return queues.map { queue in
            Sampler(label: queue.strongUnderlyingQueue.label) { Double(queue.operationCount) }
        }
    }

    init(_ samplers: [Sampler]) {
        self.samplers = samplers

        let screenHeight = NSScreen.main!.frame.height
        let frame = NSRect(x: 0, y: screenHeight - DebugMenu.height, width: DebugMenu.width, height: DebugMenu.height)
        super.init(contentRect: frame, styleMask: [.nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        isOpaque = false
        backgroundColor = NSColor.darkGray
        hasShadow = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = graphView
    }

    // A cancelable timer source (not a hand-rolled Thread+sleep): `stop()` cancels it and no handler can
    // fire afterward, so "toggled off → stops all computation" holds, and a fast off→on can't leave a
    // zombie sampler running.
    func start() {
        guard timer == nil else { return }
        graphView.reset()
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "debugMenuSampler", qos: .utility))
        // Sample depth often so short-lived spikes register (off-main, just atomic reads), but coalesce into
        // a graph frame only ~every 32ms: point count + main-thread redraw scale with the DRAW rate, not the
        // sample rate, so this stays cheap. We graph the PEAK depth seen since the last frame. ~1ms is the
        // practical sampling floor — a DispatchSourceTimer can't fire reliably below it and faster just burns
        // power. Stamp the frame at sample time, not when the main-thread draw runs, so a spike lands at its
        // true X even if the main thread is briefly busy (otherwise late draws bunch every spike at the edge).
        let sampleMs = 1, drawEveryNTicks = 32 // 1ms × 32 ≈ 32ms ≈ 30fps draw
        var peak: [String: Double] = [:]
        var ticksSinceDraw = 0
        t.schedule(deadline: .now(), repeating: .milliseconds(sampleMs))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for s in self.samplers { peak[s.label] = max(peak[s.label] ?? 0, s.read()) }
            ticksSinceDraw += 1
            guard ticksSinceDraw >= drawEveryNTicks else { return }
            let frame = peak, sampledAt = Date()
            peak.removeAll(keepingCapacity: true)
            ticksSinceDraw = 0
            DispatchQueue.main.async { self.graphView.addData(frame, at: sampledAt) }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }
}

// MARK: - Graph View

private final class QueueGraphView: NSView {
    private var history: [(timestamp: Date, data: [String: Double])] = []
    private var latestCounts: [String: Int] = [:]
    private var orderedQueues: [String] = []
    private var hiddenSeries: Set<String> = [] // series toggled off by clicking their legend entry
    private var colors: [NSColor] = []
    private var axisYLines: [CTLine] = []
    private var axisYValues: [Int] = []
    private var legendLines: [CTLine] = []
    private var cachedMaxY = 1.0
    private let maxDuration: TimeInterval = 60
    private let padding: CGFloat = 20
    private let textFont = NSFont.systemFont(ofSize: 8)
    private lazy var axisTextAttributes: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.white]
    private lazy var legendTextAttributes: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.white]
    private lazy var axisXLines: [CTLine] = (0...3).map { makeLine("\(Int(Double($0) * 20))s", attributes: axisTextAttributes) }
    private let legendRowHeight: CGFloat = 15

    func reset() {
        history.removeAll()
        latestCounts.removeAll()
        orderedQueues.removeAll()
        colors.removeAll()
        axisYLines.removeAll()
        axisYValues.removeAll()
        legendLines.removeAll()
        cachedMaxY = 1.0
        needsDisplay = true
    }

    func addData(_ data: [String: Double], at timestamp: Date) {
        history.append((timestamp, data))
        trimHistory(timestamp)
        updateCaches(data)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.textMatrix = .identity
        drawAxes(in: ctx)
        drawCurves(in: ctx)
        drawLegend(in: ctx)
    }

    private func drawAxes(in ctx: CGContext) {
        updateAxisLines()
        let width = bounds.width - 2*padding
        let height = DebugMenu.height - 2*padding
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        for i in 0..<axisYLines.count {
            let y = bounds.height - DebugMenu.height + padding + CGFloat(i)/5 * height
            ctx.textPosition = CGPoint(x: DebugMenu.width - padding + 4, y: y - 6)
            CTLineDraw(axisYLines[i], ctx)
        }
        for i in 0..<axisXLines.count {
            let x = bounds.width - padding - CGFloat(i)/3 * width
            let yBase = bounds.height - DebugMenu.height + padding
            ctx.textPosition = CGPoint(x: x - 10, y: yBase - 12)
            CTLineDraw(axisXLines[i], ctx)
        }
    }

    private func drawCurves(in ctx: CGContext) {
        guard !history.isEmpty else { return }
        let width = bounds.width - 2*padding
        let height = DebugMenu.height - 2*padding
        let now = Date()
        let maxY = max(1.0, cachedMaxY)
        for (i, name) in orderedQueues.enumerated() {
            guard i < colors.count else { break }
            if hiddenSeries.contains(name) { continue }
            ctx.setStrokeColor(colors[i].cgColor)
            ctx.setLineWidth(1)
            var first = true
            for entry in history {
                let elapsed = now.timeIntervalSince(entry.timestamp)
                let frac = CGFloat((maxDuration - elapsed)/maxDuration)
                let x = padding + frac * width
                let yBase = bounds.height - DebugMenu.height + padding
                let yVal = yBase + CGFloat(entry.data[name] ?? 0)/CGFloat(maxY)*height
                let pt = CGPoint(x: x, y: yVal)
                if first { ctx.move(to: pt); first = false } else { ctx.addLine(to: pt) }
            }
            ctx.strokePath()
        }
    }

    private func drawLegend(in ctx: CGContext) {
        guard !orderedQueues.isEmpty, orderedQueues.count == legendLines.count else { return }
        for (i, name) in orderedQueues.enumerated() {
            let rect = legendItemRect(i)
            ctx.saveGState()
            if hiddenSeries.contains(name) { ctx.setAlpha(0.3) } // toggled-off series: dim its legend entry
            ctx.setFillColor(colors[i].cgColor)
            ctx.fill(CGRect(x: rect.minX, y: rect.minY + 2, width: 10, height: 10))
            ctx.textPosition = CGPoint(x: rect.minX + 15, y: rect.minY)
            CTLineDraw(legendLines[i], ctx)
            ctx.restoreGState()
        }
    }

    // The clickable band for a legend entry (swatch + label), in the view's bottom-left coords; used both to
    // lay the legend out and to hit-test clicks. Width is clamped to the label so clicks on the graph area
    // (which drag the panel) aren't swallowed.
    private func legendItemRect(_ i: Int) -> CGRect {
        let rowsPerColumn = max(1, Int(floor((DebugMenu.height - 2*padding) / legendRowHeight)))
        let columns = max(1, (orderedQueues.count + rowsPerColumn - 1) / rowsPerColumn)
        let columnWidth = (bounds.width - 2*padding) / CGFloat(columns)
        let col = CGFloat(i / rowsPerColumn), row = CGFloat(i % rowsPerColumn)
        let x = padding / 2 + col * columnWidth
        let y = padding + (DebugMenu.height - 2*padding) - legendRowHeight*(row + 1)
        let labelWidth = i < legendLines.count ? CGFloat(CTLineGetTypographicBounds(legendLines[i], nil, nil, nil)) : 60
        return CGRect(x: x, y: y - 2, width: min(columnWidth, 15 + labelWidth + 6), height: legendRowHeight)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Click a legend entry to toggle that series; clicks elsewhere keep dragging the panel as before.
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for i in orderedQueues.indices where legendItemRect(i).contains(p) {
            hiddenSeries.formSymmetricDifference([orderedQueues[i]])
            updateMaxY()
            needsDisplay = true
            return
        }
        window?.performDrag(with: event)
    }

    private func distinctColors(count: Int) -> [NSColor] {
        guard count > 0 else { return [] }
        return (0..<count).map {
            NSColor(hue: CGFloat($0)/CGFloat(count), saturation: 0.75, brightness: 0.95, alpha: 1)
        }
    }

    private func trimHistory(_ now: Date) {
        let cutoff = now.addingTimeInterval(-maxDuration)
        history.removeAll { $0.timestamp < cutoff }
    }

    private func updateCaches(_ data: [String: Double]) {
        updateMaxY()
        updateQueues(data)
        updateLegend(data)
    }

    private func updateMaxY() {
        var maxY = 1.0
        for entry in history {
            for (key, value) in entry.data where !hiddenSeries.contains(key) && value > maxY { maxY = value }
        }
        let next = maxY * 1.1
        if next == cachedMaxY { return }
        cachedMaxY = next
        axisYValues.removeAll()
    }

    private func updateQueues(_ data: [String: Double]) {
        let next = data.keys.sorted()
        if next == orderedQueues { return }
        orderedQueues = next
        colors = distinctColors(count: orderedQueues.count)
        legendLines.removeAll()
    }

    private func updateLegend(_ data: [String: Double]) {
        var counts: [String: Int] = [:]
        for (key, value) in data { counts[key] = Int(value) }
        if counts == latestCounts, !legendLines.isEmpty { return }
        latestCounts = counts
        legendLines = orderedQueues.map { makeLine("\($0): \(latestCounts[$0] ?? 0)", attributes: legendTextAttributes) }
    }

    private func updateAxisLines() {
        let values = (0...5).map { Int(Double($0)/5 * cachedMaxY) }
        if values == axisYValues, !axisYLines.isEmpty { return }
        axisYValues = values
        axisYLines = values.map { makeLine("\($0)", attributes: axisTextAttributes) }
    }

    private func makeLine(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
#endif
