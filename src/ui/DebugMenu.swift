import Cocoa

final class DebugMenu: NSPanel {
    static let width = CGFloat(400)
    static let height = CGFloat(200)
    private let graphView = QueueGraphView()
    private var monitorThread: Thread?
    private var running = false

    private var queues: [LabeledOperationQueue] = []

    init(_ queues: [LabeledOperationQueue]) {
        self.queues = queues

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

    func start() {
        graphView.reset()
        running = true

        monitorThread = Thread { [weak self] in
            guard let self else { return }
            while self.running {
                var sample: [String: Double] = [:]
                for queue in self.queues {
                    sample[queue.strongUnderlyingQueue.label] = Double(queue.operationCount + queue.activeCallbacks)
                }
                DispatchQueue.main.async { self.graphView.addData(sample) }
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
        monitorThread?.start()
    }

    func stop() {
        running = false
        monitorThread = nil
    }
}

// MARK: - Graph View

private final class QueueGraphView: NSView {
    private var history: [(timestamp: Date, data: [String: Double])] = []
    private let maxDuration: TimeInterval = 60
    private let padding: CGFloat = 20

    func reset() { history.removeAll(); needsDisplay = true }

    func addData(_ data: [String: Double]) {
        let now = Date()
        history.append((now, data))
        history = history.filter { now.timeIntervalSince($0.timestamp) <= maxDuration }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        drawAxes(in: ctx)
        drawCurves(in: ctx)
        drawLegend(in: ctx)
    }

    private func drawAxes(in ctx: CGContext) {
        let width = bounds.width - 2*padding
        let height = DebugMenu.height - 2*padding
        let maxY = (history.flatMap { $0.data.values }.max() ?? 1) * 1.1

        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)

        // Y grid
        for i in 0...5 {
            let y = bounds.height - DebugMenu.height + padding + CGFloat(i)/5 * height
            // if i == 0 {
            //     ctx.move(to: CGPoint(x: padding, y: y))
            //     ctx.addLine(to: CGPoint(x: bounds.width - padding, y: y))
            //     ctx.strokePath()
            // }
            let val = Int(Double(i)/5 * maxY)
            NSString(string: "\(val)").draw(at: CGPoint(x: DebugMenu.width - padding + 4, y: y - 6),
                                            withAttributes: [.font: NSFont.systemFont(ofSize: 8),
                                                             .foregroundColor: NSColor.white])
        }

        // X grid reversed
        for i in 0...3 {
            let x = bounds.width - padding - CGFloat(i)/3 * width
            let yBase = bounds.height - DebugMenu.height + padding
            // if i == 0 {
            //     ctx.move(to: CGPoint(x: x, y: yBase))
            //     ctx.addLine(to: CGPoint(x: x, y: yBase + height))
            //     ctx.strokePath()
            // }
            let sec = Int(Double(i) * 20)
            NSString(string: "\(sec)s").draw(at: CGPoint(x: x - 10, y: yBase - 12),
                                             withAttributes: [.font: NSFont.systemFont(ofSize: 8),
                                                              .foregroundColor: NSColor.white])
        }
    }

    private func drawCurves(in ctx: CGContext) {
        guard !history.isEmpty else { return }
        let width = bounds.width - 2*padding
        let height = DebugMenu.height - 2*padding
        let now = Date()
        let maxY = max(1.0, (history.flatMap { $0.data.values }.max() ?? 1)) * 1.1

        let ordered = orderedQueues()
        let colors = distinctColors(count: ordered.count)

        for (i, name) in ordered.enumerated() {
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
        guard let latest = history.last?.data else { return }
        let ordered = orderedQueues()
        let colors = distinctColors(count: ordered.count)
        let rowHeight: CGFloat = 15
        let rowsPerColumn = Int(floor((DebugMenu.height - 2*padding) / rowHeight))
        let columnWidth: CGFloat = (bounds.width - 2*padding) /
            CGFloat(max(1, (ordered.count + rowsPerColumn - 1) / rowsPerColumn))
        let legendBottom = padding

        for (i, name) in ordered.enumerated() {
            let col = CGFloat(i / rowsPerColumn)
            let row = CGFloat(i % rowsPerColumn)
            let x = padding / 2 + col * columnWidth
            let y = legendBottom + (DebugMenu.height - 2*padding) - rowHeight*(row + 1)
            let color = colors[i]
            let count = Int(latest[name] ?? 0)

            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: x, y: y, width: 10, height: 10))
            NSString(string: "\(name): \(count)").draw(at: CGPoint(x: x + 15, y: y - 2),
                                                        withAttributes: [.font: NSFont.systemFont(ofSize: 8),
                                                                         .foregroundColor: NSColor.white])
        }
    }

    private func orderedQueues() -> [String] {
        guard let keys = history.last?.data.keys else { return [] }
        return keys.sorted()
    }

    private func distinctColors(count: Int) -> [NSColor] {
        guard count > 0 else { return [] }
        return (0..<count).map {
            NSColor(hue: CGFloat($0)/CGFloat(count), saturation: 0.75, brightness: 0.95, alpha: 1)
        }
    }
}
