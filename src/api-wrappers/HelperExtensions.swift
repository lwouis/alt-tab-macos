import Cocoa

extension Collection {
    // recursive flatMap
    func joined() -> [Any] {
        return flatMap { ($0 as? [Any])?.joined() ?? [$0] }
    }
}

extension Array where Element == Window {
    func firstIndexThatMatches(_ element: AXUIElement, _ wid: CGWindowID?) -> Self.Index? {
        // the window can be deallocated by the OS, in which case its `CGWindowID` will be `-1`
        // we check for equality both on the AXUIElement, and the CGWindowID, in order to catch all scenarios
        return firstIndex { $0.axUiElement == element || ($0.cgWindowId != -1 && $0.cgWindowId == wid) }
    }

    mutating func insertAndScaleRecycledPool(_ elements: [Element], at i: Int) {
        insert(contentsOf: elements, at: i)
        let neededRecycledViews = count - ThumbnailsView.recycledViews.count
        if neededRecycledViews > 0 {
            (1...neededRecycledViews).forEach { _ in ThumbnailsView.recycledViews.append(ThumbnailView()) }
        }
    }

    mutating func insertAndScaleRecycledPool(_ element: Element, at i: Int) {
        insertAndScaleRecycledPool([element], at: i)
    }
}

extension NSView {
    // constrain size to fittingSize
    func fit() {
        widthAnchor.constraint(equalToConstant: fittingSize.width).isActive = true
        heightAnchor.constraint(equalToConstant: fittingSize.height).isActive = true
    }

    // constrain size to provided width and height
    func fit(_ width: CGFloat, _ height: CGFloat) {
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: height).isActive = true
    }
}

extension Array {
    // forEach with each iteration run concurrently on the global queue
    func forEachAsync(fn: @escaping (Element) -> Void) {
        let group = DispatchGroup()
        for element in self {
            BackgroundWork.globalSemaphore.wait()
            BackgroundWork.mainQueueConcurrentWorkQueue.async(group: group) {
                group.enter()
                fn(element)
                BackgroundWork.globalSemaphore.signal()
                group.leave()
            }
        }
        group.wait()
    }
}

// allow using a closure for NSControl action, instead of selector
class SelectorWrapper<T> {
    let selector: Selector
    let closure: (T) -> Void

    init(withClosure closure: @escaping (T) -> Void) {
        self.selector = #selector(callClosure)
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
            return nil
        }
        set {
            if let newValue = newValue {
                let selectorWrapper = SelectorWrapper<NSControl>(withClosure: newValue)
                objc_setAssociatedObject(self, &handle, selectorWrapper, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                action = selectorWrapper.selector
                target = selectorWrapper
            } else {
                action = nil
                target = nil
            }
        }
    }
}

// only assign if different; useful for performance
func assignIfDifferent<T: Equatable>(_ a: UnsafeMutablePointer<T>, _ b: T) {
    if a.pointee != b {
        a.pointee = b
    }
}

extension DispatchQoS {
    func toQualityOfService() -> QualityOfService {
        switch self {
            case .userInteractive: return .userInteractive
            case .userInitiated: return .userInitiated
            case .utility: return .utility
            case .background: return .background
            default: return .default
        }
    }
}

extension NSGridColumn {
    func width(_ skipCell: Int? = nil) -> CGFloat {
        var maxWidth = CGFloat(0)
        for i in (0..<numberOfCells) {
            if let skipCell = skipCell, i == skipCell { continue }
            maxWidth = max(maxWidth, cell(at: i).contentView!.fittingSize.width)
        }
        return maxWidth
    }
}

extension NSViewController {
    func setView(_ subview: NSView) {
        view = NSView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.subviews = [subview]
        subview.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
    }
}

extension NSImage {
    // NSImage(named) caches/reuses NSImage objects; we force separate instances of images by using copy()
    static func initCopy(_ name: String) -> NSImage {
        return NSImage(named: name)!.copy() as! NSImage
    }

    static func initTemplateCopy(_ name: String) -> NSImage {
        let image = initCopy(name)
        image.isTemplate = true
        return image
    }

    // copy and resize an image using high quality interpolation
    static func initResizedCopy(_ name: String, _ width: CGFloat, _ height: CGFloat) -> NSImage {
        let original = initCopy(name)
        let img = NSImage(size: CGSize(width: width, height: height))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        original.draw(in: NSMakeRect(0, 0, width, height), from: NSMakeRect(0, 0, original.size.width, original.size.height), operation: .copy, fraction: 1)
        img.unlockFocus()
        return img
    }
}
