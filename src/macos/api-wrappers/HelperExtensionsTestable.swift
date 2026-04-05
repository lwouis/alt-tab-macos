import Cocoa

// allow using a closure for NSControl action, instead of selector
class SelectorWrapper<T> {
    let selector: Selector
    let closure: (T) -> Void

    init(withClosure closure: @escaping (T) -> Void) {
        selector = #selector(callClosure)
        self.closure = closure
    }

    @objc
    private func callClosure(sender: AnyObject) {
        closure(sender as! T)
    }
}

fileprivate var handle: Int = 0

typealias ActionClosure = (NSControl) -> Void

extension NSControl {
    var onAction: ActionClosure? {
        get {
            return (objc_getAssociatedObject(self, &handle) as? SelectorWrapper<NSControl>)?.closure
        }
        set {
            if let newValue {
                let selectorWrapper = SelectorWrapper<NSControl>(withClosure: newValue)
                objc_setAssociatedObject(self, &handle, selectorWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = selectorWrapper.selector
                target = selectorWrapper
            } else {
                objc_setAssociatedObject(self, &handle, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = nil
                target = nil
            }
        }
    }
}

extension CGImage {
    func resizedCopyWithCoreGraphics(_ newSize: NSSize, _ fixBitmapInfo: Bool) -> CGImage {
        let finalBitmapInfo = fixBitmapInfo
            ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little)
            : bitmapInfo
        let context = CGContext(data: nil,
            width: Int(newSize.width),
            height: Int(newSize.height),
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: finalBitmapInfo.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(origin: .zero, size: newSize))
        return context.makeImage()!
    }
}
