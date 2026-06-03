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

    // Queue depths only — each spikes with work and falls back to 0 when idle. focusOrder is the
    // serial queue behind the #5665 fix; a backlog there is the regression signal.
    private static func makeSamplers() -> [Sampler] {
        let scheduler = AXCallScheduler.shared
        let queues: [LabeledOperationQueue] = [
            BackgroundWork.screenshotsQueue,
            BackgroundWork.accessibilityCommandsQueue,
            BackgroundWork.focusOrderQueue,
            scheduler.axQueryFirstTryQueue,
            scheduler.axQueryScanQueue,
            scheduler.axQueryRetryQueue,
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
        t.schedule(deadline: .now(), repeating: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            var sample: [String: Double] = [:]
            for s in self.samplers { sample[s.label] = s.read() }
            DispatchQueue.main.async { self.graphView.addData(sample) }
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

    func addData(_ data: [String: Double]) {
        let now = Date()
        history.append((now, data))
        trimHistory(now)
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
        let rowsPerColumn = Int(floor((DebugMenu.height - 2*padding) / legendRowHeight))
        let columnWidth: CGFloat = (bounds.width - 2*padding) /
            CGFloat(max(1, (orderedQueues.count + rowsPerColumn - 1) / rowsPerColumn))
        let legendBottom = padding
        for (i, _) in orderedQueues.enumerated() {
            let col = CGFloat(i / rowsPerColumn)
            let row = CGFloat(i % rowsPerColumn)
            let x = padding / 2 + col * columnWidth
            let y = legendBottom + (DebugMenu.height - 2*padding) - legendRowHeight*(row + 1)
            let color = colors[i]
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 10, height: 10))
            ctx.textPosition = CGPoint(x: x + 15, y: y - 2)
            CTLineDraw(legendLines[i], ctx)
        }
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
            for value in entry.data.values where value > maxY { maxY = value }
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
