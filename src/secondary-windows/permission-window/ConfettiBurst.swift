import Cocoa

/// One burst of confetti out of a circle on screen, flying up then raining down. It plays in a
/// click-through window of its own, attached above `parent`, so the pieces can fly past the parent's
/// edges. The window goes away once the pieces have faded.
enum ConfettiBurst {
    private static let colors: [NSColor] = [.systemPink, .systemOrange, .systemYellow, .systemGreen, .systemTeal, .systemBlue, .systemPurple]
    private static let emissionDuration = 0.14
    private static let lifetime = Float(1.8)
    /// Room around the circle for the pieces to fly into. Only the fastest reach its edges, and by
    /// then they have mostly faded.
    private static let reach = NSSize(width: 640, height: 600)

    static func fire(around circle: NSRect, above parent: NSWindow) {
        guard let screen = parent.screen else { return }
        let window = makeWindow(NSRect(x: circle.midX - reach.width, y: circle.midY - reach.height,
            width: 2 * reach.width, height: reach.height + screen.frame.maxY - circle.midY))
        let emitter = makeEmitter(around: circle.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY))
        window.contentView!.layer!.addSublayer(emitter)
        emitter.add(fadeOut(), forKey: nil)
        window.level = parent.level
        parent.addChildWindow(window, ordered: .above)
        DispatchQueue.main.asyncAfter(deadline: .now() + emissionDuration) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(lifetime)) {
            parent.removeChildWindow(window)
            window.orderOut(nil)
        }
    }

    private static func makeWindow(_ frame: NSRect) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        window.contentView!.wantsLayer = true
        return window
    }

    private static func makeEmitter(around circle: NSRect) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.emitterPosition = CGPoint(x: circle.midX, y: circle.midY)
        emitter.emitterSize = circle.insetBy(dx: -circle.width * 0.15, dy: -circle.height * 0.15).size
        emitter.beginTime = CACurrentMediaTime()
        let shapes = [piece(NSSize(width: 8, height: 4), oval: false), piece(NSSize(width: 5, height: 5), oval: true), piece(NSSize(width: 10, height: 3), oval: false)]
        emitter.emitterCells = colors.flatMap { color in shapes.map { cell($0, color) } }
        return emitter
    }

    /// On the whole layer rather than per piece: they are all thrown at once, and per-piece fading
    /// would start at birth.
    private static func fadeOut() -> CAAnimation {
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0]
        fade.keyTimes = [0, 0.5, 1]
        fade.duration = CFTimeInterval(lifetime)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        return fade
    }

    private static func cell(_ shape: CGImage, _ color: NSColor) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = shape
        cell.color = color.cgColor
        cell.birthRate = 16
        cell.lifetime = lifetime
        cell.velocity = 300
        cell.velocityRange = 105
        cell.yAcceleration = -480
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = .pi * 0.55
        cell.spin = 3
        cell.spinRange = 6
        cell.scaleRange = 0.3
        return cell
    }

    private static func piece(_ size: NSSize, oval: Bool) -> CGImage {
        let image = NSImage(size: size, flipped: false) {
            NSColor.white.setFill()
            (oval ? NSBezierPath(ovalIn: $0) : NSBezierPath(roundedRect: $0, xRadius: 1, yRadius: 1)).fill()
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
