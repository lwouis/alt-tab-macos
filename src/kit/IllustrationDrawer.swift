import Cocoa
import CoreText

final class IllustrationDrawer {
    struct Archive: Decodable {
        let version: Int
        let nodes: [Node]
        let paths: [[[CGFloat]]]
        let gradients: [Gradient]
        let scenes: [String: Scene]
    }
    struct Scene: Decodable {
        let root: Int
        let size: [CGFloat]
    }
    struct Shape: Decodable {
        var path: Int?
        var rect: [CGFloat]?
        var ellipse: [CGFloat]?
    }
    struct Node: Decodable {
        var transforms: [[CGFloat]]?
        var rtlTransforms: [[CGFloat]]?
        var clip: Shape?
        var opacity: CGFloat?
        var children: [Int]?
        var path: Int?
        var rect: [CGFloat]?
        var ellipse: [CGFloat]?
        var image: String?
        var text: String?
        var x: CGFloat?
        var y: CGFloat?
        var font: String?
        var fontSize: CGFloat?
        var bold: Bool?
        var anchor: String?
        var localization: String?
        var darkFill: [CGFloat]?
        var maxWidth: CGFloat?
        var minimumSize: CGFloat?
        var highlightQuery: String?
        var highlightLocalization: String?
        var highlightFill: [CGFloat]?
        var highlightTextFill: [CGFloat]?
        var highlightLayout: [CGFloat]?
        var fill: [CGFloat]?
        var gradient: Int?
        var fillAlpha: CGFloat?
        var stroke: [CGFloat]?
        var strokeWidth: CGFloat?
        var roundCap: Bool?
        var roundJoin: Bool?
    }
    struct Gradient: Decodable {
        let stops: [[CGFloat]]
        let radial: Bool
        let points: [CGFloat]
    }
    let archive: Archive
    let directory: URL
    private let paths: [CGPath]
    private let gradients: [CGGradient]
    private var shapes = [CGPath?]()
    private var clips = [CGPath?]()
    private var bitmaps = [String: CGImage]()
    private let space = CGColorSpaceCreateDeviceRGB()

    init(directory: URL) throws {
        self.directory = directory
        archive = try PropertyListDecoder().decode(Archive.self, from: Data(contentsOf: directory.appendingPathComponent("scenes.plist")))
        guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        paths = archive.paths.map { commands in
            let path = CGMutablePath()
            for c in commands {
                switch c[0] {
                case 0: path.move(to: CGPoint(x: c[1], y: c[2]))
                case 1: path.addLine(to: CGPoint(x: c[1], y: c[2]))
                case 2: path.addCurve(to: CGPoint(x: c[5], y: c[6]), control1: CGPoint(x: c[1], y: c[2]), control2: CGPoint(x: c[3], y: c[4]))
                default: path.closeSubpath()
                }
            }
            return path
        }
        gradients = archive.gradients.map { gradient in
            CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: gradient.stops.flatMap { Array($0.dropFirst()) }, locations: gradient.stops.map { $0[0] }, count: gradient.stops.count)!
        }
        shapes = archive.nodes.map { node in
            node.image == nil && (node.path != nil || node.rect != nil || node.ellipse != nil)
                ? shape(Shape(path: node.path, rect: node.rect, ellipse: node.ellipse)) : nil
        }
        clips = archive.nodes.map { $0.clip.map(shape) }
        for node in archive.nodes {
            guard let name = node.image, bitmaps[name] == nil else { continue }
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            guard let provider = CGDataProvider(data: data as CFData),
                let bitmap = CGImage(jpegDataProviderSource: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { throw CocoaError(.fileReadCorruptFile) }
            bitmaps[name] = bitmap
        }
    }

    private struct PreparedText {
        let line: CTLine
        let position: CGPoint
        let highlights: [CGRect]
        let highlightFill: CGColor?
        let highlightRadius: CGFloat
    }

    func image(_ name: String, dark: Bool = false, rightToLeft: Bool = false,
               localize: (String, String) -> String = { _, english in english }) -> NSImage? {
        guard let scene = archive.scenes[name] else { return nil }
        let size = NSSize(width: scene.size[0], height: scene.size[1])
        var text = [Int: PreparedText]()
        var pending = [scene.root]
        var visited = Set<Int>()
        while let index = pending.popLast() {
            guard visited.insert(index).inserted else { continue }
            let node = archive.nodes[index]
            pending.append(contentsOf: node.children ?? [])
            guard let english = node.text else { continue }
            let value = node.localization.map { localize($0, english) } ?? english
            let query = node.highlightQuery.map { localize(node.highlightLocalization!, $0) }
            text[index] = prepareText(node, value: value, query: query, dark: dark)
        }
        let prepared = text
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.saveGState()
            context.translateBy(x: rect.minX, y: rect.minY)
            context.scaleBy(x: rect.width / size.width, y: rect.height / size.height)
            self.draw(scene.root, in: context, rtl: rightToLeft, text: prepared)
            context.restoreGState()
            return true
        }
        return image
    }

    private func shape(_ shape: Shape) -> CGPath {
        if let index = shape.path { return paths[index] }
        if let r = shape.ellipse { return CGPath(ellipseIn: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]), transform: nil) }
        let r = shape.rect!
        let rect = CGRect(x: r[0], y: r[1], width: r[2], height: r[3])
        return CGPath(roundedRect: rect, cornerWidth: min(r[4], r[2] / 2), cornerHeight: min(r[5], r[3] / 2), transform: nil)
    }

    private func draw(_ index: Int, in context: CGContext, rtl: Bool, text: [Int: PreparedText]) {
        let node = archive.nodes[index]
        context.saveGState()
        for t in (rtl ? node.rtlTransforms ?? node.transforms : node.transforms) ?? [] {
            context.concatenate(CGAffineTransform(a: t[0], b: t[1], c: t[2], d: t[3], tx: t[4], ty: t[5]))
        }
        if let clip = clips[index] { context.addPath(clip); context.clip() }
        if let alpha = node.opacity { context.setAlpha(alpha); context.beginTransparencyLayer(auxiliaryInfo: nil) }
        if let children = node.children {
            for child in children { draw(child, in: context, rtl: rtl, text: text) }
        } else if let bitmap = node.image.flatMap({ bitmaps[$0] }), let r = node.rect {
            context.translateBy(x: r[0], y: r[1] + r[3])
            context.scaleBy(x: 1, y: -1)
            context.interpolationQuality = .high
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: r[2], height: r[3]))
        } else if let prepared = text[index] {
            context.translateBy(x: prepared.position.x, y: prepared.position.y)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            if let fill = prepared.highlightFill {
                context.setFillColor(fill)
                for rect in prepared.highlights {
                    context.addPath(CGPath(roundedRect: rect, cornerWidth: prepared.highlightRadius,
                        cornerHeight: prepared.highlightRadius, transform: nil))
                    context.fillPath()
                }
            }
            CTLineDraw(prepared.line, context)
        } else if let path = shapes[index] {
            if let index = node.gradient {
                context.saveGState()
                context.addPath(path)
                context.clip()
                let bounds = path.boundingBoxOfPath
                context.translateBy(x: bounds.minX, y: bounds.minY)
                context.scaleBy(x: bounds.width, y: bounds.height)
                context.setAlpha(node.fillAlpha ?? 1)
                let gradient = archive.gradients[index]
                let p = gradient.points
                if gradient.radial {
                    context.drawRadialGradient(gradients[index], startCenter: CGPoint(x: p[0], y: p[1]), startRadius: 0, endCenter: CGPoint(x: p[0], y: p[1]), endRadius: p[2], options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                } else {
                    context.drawLinearGradient(gradients[index], start: CGPoint(x: p[0], y: p[1]), end: CGPoint(x: p[2], y: p[3]), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                context.restoreGState()
            } else if let fill = node.fill, fill.count == 4 {
                context.setFillColor(CGColor(colorSpace: space, components: fill)!)
                context.addPath(path)
                context.fillPath()
            }
            if let stroke = node.stroke, stroke.count == 4 {
                context.setStrokeColor(CGColor(colorSpace: space, components: stroke)!)
                context.setLineWidth(node.strokeWidth ?? 1)
                context.setLineCap(node.roundCap == true ? .round : .butt)
                context.setLineJoin(node.roundJoin == true ? .round : .miter)
                context.addPath(path)
                context.strokePath()
            }
        }
        if node.opacity != nil { context.endTransparencyLayer() }
        context.restoreGState()
    }

    private func prepareText(_ node: Node, value: String, query: String?, dark: Bool) -> PreparedText {
        let fitted = Self.fit(value, size: node.fontSize!, minimum: node.minimumSize,
            maximum: node.maxWidth, bold: node.bold == true)
        let fill = (dark ? node.darkFill ?? node.fill : node.fill) ?? [0, 0, 0, 1]
        let color = NSColor(cgColor: CGColor(colorSpace: space, components: fill)!)!
        let attributed = NSMutableAttributedString(string: fitted.text,
            attributes: [.font: Self.font(fitted.size, bold: node.bold == true), .kern: 0, .foregroundColor: color])
        let range = query.map { (fitted.text as NSString).range(of: $0) } ?? NSRange(location: NSNotFound, length: 0)
        if range.location != NSNotFound, let fill = node.highlightTextFill {
            attributed.addAttribute(.foregroundColor, value: NSColor(cgColor: CGColor(colorSpace: space, components: fill)!)!, range: range)
        }
        let line = CTLineCreateWithAttributedString(attributed)
        // Match the approved SVG captures: no kerning, and glyph-outline anchor offsets
        // truncated to whole scene units. Typographic advances shift centered labels.
        let width = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).width
        let offset = node.anchor == "middle" ? floor(width / 2) : node.anchor == "end" ? floor(width) : 0
        let scale = fitted.size / node.fontSize!
        let layout = node.highlightLayout ?? [0, 0, 0, 0]
        let highlights = Self.highlightBounds(line, range: range).map {
            CGRect(x: $0.minX - layout[2] * scale, y: -(layout[0] + layout[1]) * scale,
                width: $0.width + 2 * layout[2] * scale, height: layout[1] * scale)
        }
        return PreparedText(line: line, position: CGPoint(x: node.x! - offset, y: node.y!), highlights: highlights,
            highlightFill: node.highlightFill.flatMap { CGColor(colorSpace: space, components: $0) }, highlightRadius: layout[3] * scale)
    }

    /// Glyph bounds follow the shaped run, including RTL order and zero-width combining marks.
    static func highlightBounds(_ line: CTLine, range: NSRange) -> [CGRect] {
        guard range.location != NSNotFound, range.length > 0 else { return [] }
        var bounds = [CGRect]()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
            var rect = CGRect.null
            for index in indices.indices where NSLocationInRange(indices[index], range) {
                rect = rect.union(CTRunGetImageBounds(run, nil, CFRange(location: index, length: 1)))
            }
            if !rect.isNull { bounds.append(rect) }
        }
        return bounds
    }

    static func font(_ size: CGFloat, bold: Bool) -> NSFont {
        let regular = NSFont(name: "Helvetica Neue", size: size) ?? .systemFont(ofSize: size)
        return bold ? NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask) : regular
    }

    static func fit(_ value: String, size: CGFloat, minimum: CGFloat?, maximum: CGFloat?, bold: Bool) -> (text: String, size: CGFloat) {
        guard let maximum else { return (value, size) }
        let available = max(1, maximum - 2)
        func measure(_ text: String, _ size: CGFloat) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font(size, bold: bold)]).width
        }
        var fittedSize = max(minimum ?? size, min(size, size * available / max(1, measure(value, size))))
        // Small fonts can have rounded metrics; proportional scaling alone can still overflow.
        if let minimum, measure(value, fittedSize) > available, measure(value, minimum) <= available {
            var lower = minimum
            var upper = fittedSize
            for _ in 0..<10 {
                let middle = (lower + upper) / 2
                if measure(value, middle) <= available { lower = middle } else { upper = middle }
            }
            fittedSize = lower
        }
        guard measure(value, fittedSize) > available else { return (value, fittedSize) }
        var text = value
        while !text.isEmpty && measure(text + "…", fittedSize) > available { text.removeLast() }
        return (text + "…", fittedSize)
    }
}
