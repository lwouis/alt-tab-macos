import Cocoa
import SwiftUI

final class FireworksOverlayView: NSView {

    private let burstCount = 6
    private let colors: [CGColor] = [
        NSColor.systemRed.cgColor,
        NSColor.systemOrange.cgColor,
        NSColor.systemYellow.cgColor,
        NSColor.systemGreen.cgColor,
        NSColor.systemBlue.cgColor,
        NSColor.systemPurple.cgColor,
        NSColor.systemPink.cgColor,
        NSColor.white.cgColor,
    ]

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        guard superview != nil else { return }
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        startFireworks()
    }

    private func startFireworks() {
        guard let bounds = superview?.bounds else { return }
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = .zero
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.renderMode = .additive
        emitter.beginTime = CACurrentMediaTime()
        emitter.lifetime = 0
        layer?.addSublayer(emitter)
        self.emitterLayer = emitter

        let baseDelay = CACurrentMediaTime()
        for i in 0..<burstCount {
            let x = CGFloat.random(in: bounds.width * 0.2 ... bounds.width * 0.8)
            let y = CGFloat.random(in: bounds.height * 0.15 ... bounds.height * 0.55)
            let delay: CFTimeInterval = Double(i) * 0.3
            scheduleBurst(at: CGPoint(x: x, y: y), delay: delay, baseTime: baseDelay, on: emitter)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.removeFromSuperview()
        }
    }

    private func scheduleBurst(at position: CGPoint, delay: CFTimeInterval, baseTime: CFTimeInterval, on emitter: CAEmitterLayer) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let cell = self.makeFireworkCell()
            let subEmitter = CAEmitterLayer()
            subEmitter.emitterPosition = position
            subEmitter.emitterShape = .point
            subEmitter.emitterMode = .points
            subEmitter.renderMode = .additive
            subEmitter.beginTime = baseTime + delay
            subEmitter.birthRate = 1
            subEmitter.lifetime = 1
            subEmitter.emitterCells = [cell]
            emitter.addSublayer(subEmitter)
        }
    }

    private static let particleImage: CGImage = {
        let size = 10
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: size, height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor.white)
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }()

    private func makeFireworkCell() -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = 300
        cell.lifetime = 2.0
        cell.lifetimeRange = 0.5
        cell.velocity = 180
        cell.velocityRange = 60
        cell.emissionRange = .pi * 2
        cell.yAcceleration = -80
        cell.scale = 0.06
        cell.scaleRange = 0.03
        cell.scaleSpeed = -0.015
        cell.alphaSpeed = -0.45
        cell.spin = .pi * 2
        cell.spinRange = .pi * 2
        cell.color = colors.randomElement() ?? NSColor.white.cgColor
        cell.contents = Self.particleImage
        return cell
    }

    private var emitterLayer: CAEmitterLayer?
}

@available(macOS 13.0, *)
struct FireworksOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> FireworksOverlayView {
        FireworksOverlayView()
    }

    func updateNSView(_ nsView: FireworksOverlayView, context: Context) {}
}
