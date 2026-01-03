import AppKit
import Metal
import QuartzCore
import ScreenCaptureKit

final class MetalThumbnailsView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func makeBackingLayer() -> CALayer { metalLayer }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let metalLayer: CAMetalLayer
    private let pipelineState: MTLRenderPipelineState
    private var thumbnails = ConcurrentMap<CGWindowID, ThumbnailFrame>()
    private var thumbnailsToPaint = ConcurrentMap<CGWindowID, Bool>()
    var thumbnailRects = [CGWindowID: NSRect]()

    // we use AnyObject to avoid compiler warning about CADisplayLink being only for macOS >= 14.0
    private var displayLink: AnyObject?

    private var isDrawing = false

    init() {
        device = MTLCreateSystemDefaultDevice()!
        commandQueue = device.makeCommandQueue()!
        metalLayer = CAMetalLayer()
        pipelineState = MetalThumbnailsView.makePipelineState(device, metalLayer)
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.actions = [
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull()
        ]
        if #available(macOS 14.0, *) {
            setupDisplayLink()
        }
    }

    @available(macOS 14.0, *)
    func setupDisplayLink() {
        displayLink = displayLink(target: self, selector: #selector(frameTick))
        displayLink!.add(to: .main, forMode: .common)
    }

    @objc private func frameTick() {
        guard !isDrawing else { return }
        isDrawing = true
        let start = nowNs()
        drawFrame()
        let end = nowNs()
        let durationNs = toNs(end - start)
        Logger.error { Double(durationNs) / 1_000_000.0 }
        isDrawing = false
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    override func layout() {
        super.layout()
        metalLayer.frame = bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )
    }

    private static func makePipelineState(_ device: MTLDevice, _ metalLayer: CAMetalLayer) -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()!
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "thumbnailVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "thumbnailFragment")
        descriptor.colorAttachments[0].pixelFormat = metalLayer.pixelFormat
        let attachment = descriptor.colorAttachments[0]!
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            Logger.error { error }
            fatalError("\(error)")
        }
    }

    private func makePlaneTexture(_ pixelBuffer: CVPixelBuffer, plane: Int, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = [.shaderRead]
        return device.makeTexture(descriptor: desc, iosurface: surface, plane: plane)
    }

    func enqueue(_ pixelBuffer: CVPixelBuffer, _ pts: CMTime, for id: CGWindowID) {
        guard let yTex = makePlaneTexture(pixelBuffer, plane: 0, pixelFormat: .r8Unorm),
              let cbcrTex = makePlaneTexture(pixelBuffer, plane: 1, pixelFormat: .rg8Unorm)
        else { return }
        let frame = ThumbnailFrame(yTex: yTex, cbcrTex: cbcrTex, pts: pts)
        thumbnails.withLock { t in
            t[id] = frame
        }
        thumbnailsToPaint.withLock { t in
            t[id] = true
            let x = t.filter { $0.value }.count
            Logger.error { x }
        }
        Logger.error { (Windows.list.first {$0.cgWindowId == id }?.title) }
    }

    func drawFrame() {
        let t0 = nowNs()
        let drawable = metalLayer.nextDrawable()
        let t1 = nowNs()
        Logger.error { "nextDrawable() took \((t1 - t0)/1_000_000) ms" }
        guard
            let drawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = drawable.texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return }
        encoder.setRenderPipelineState(pipelineState)
        let thumbnailsToPaintIds = thumbnailsToPaint.withLock { ($0.filter { t in t.value }).keys }
        Logger.error { thumbnailsToPaintIds.count }
        for id in thumbnailsToPaintIds {
            guard let rect = thumbnailRects[id] else { continue }
            guard let frame = (thumbnails.withLock { $0[id] }) else { continue }
            drawThumbnail(frame: frame, in: rect, encoder: encoder)
            thumbnailsToPaint.withLock { $0[id] = false }
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        // BackgroundWork.screenshotsQueue.strongUnderlyingQueue.async(flags: .barrier) {
        //     self?.thumbnails = nil
        //     self?.thumbnailRects = nil
        // }
    }

    private func drawThumbnail(frame: ThumbnailFrame, in rect: CGRect, encoder: MTLRenderCommandEncoder) {
        let viewSize = bounds.size
        // Convert AppKit rect → NDC
        let x0 = Float((rect.minX / viewSize.width) * 2 - 1)
        let x1 = Float((rect.maxX / viewSize.width) * 2 - 1)
        let y0 = Float((rect.minY / viewSize.height) * 2 - 1)
        let y1 = Float((rect.maxY / viewSize.height) * 2 - 1)
        let vertices: [Float] = [x0, y0, 0, 1, x1, y0, 1, 1, x0, y1, 0, 0, x1, y1, 1, 0]
        encoder.setVertexBytes(vertices, length: vertices.count * MemoryLayout<Float>.size, index: 0)
        encoder.setFragmentTexture(frame.yTex, index: 0)
        encoder.setFragmentTexture(frame.cbcrTex, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}

struct ThumbnailFrame {
    let yTex: MTLTexture
    let cbcrTex: MTLTexture
    let pts: CMTime
}

import MachO

@inline(__always)
func nowNs() -> UInt64 {
    mach_continuous_time()
}

let timebase: mach_timebase_info = {
    var info = mach_timebase_info()
    mach_timebase_info(&info)
    return info
}()

@inline(__always)
func toNs(_ t: UInt64) -> UInt64 {
    t * UInt64(timebase.numer) / UInt64(timebase.denom)
}