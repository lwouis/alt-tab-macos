import Cocoa

extension CGFloat {
    // add CGFloat constructor from String
    init?(_ string: String) {
        guard let number = NumberFormatter().number(from: string) else {
            return nil
        }
        self.init(number.floatValue)
    }
}

extension Optional {
    // add throw-on-nil method on Optional
    func orThrow() throws -> Wrapped {
        switch self {
            case .some(let value):
                return value
            case .none:
                Thread.callStackSymbols.forEach { print($0) }
                throw NSError.make(domain: "Optional", message: "Optional contained nil")
        }
    }
}

extension String {
    // add String constructor from CGFloat that round up at 1 decimal
    init?(_ cgFloat: CGFloat) {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        guard let string = formatter.string(from: cgFloat as NSNumber) else {
            return nil
        }
        self.init(string)
    }
}

extension NSView {
    // add recursive lookup in subviews for specific type
    func findNestedViews<T: NSView>(subclassOf: T.Type) -> [T] {
        return recursiveSubviews.compactMap { $0 as? T }
    }

    var recursiveSubviews: [NSView] {
        return subviews + subviews.flatMap { $0.recursiveSubviews }
    }
}

extension NSError {
    // add convenience to NSError
    class func make(domain: String, message: String, code: Int = 9999) -> NSError {
        return NSError(
                domain: domain,
                code: code,
                userInfo: [NSLocalizedDescriptionKey: message, NSLocalizedFailureReasonErrorKey: message]
        )
    }
}

extension Collection {
    // recursive flatMap
    func joined() -> [Any] {
        return flatMap { ($0 as? [Any])?.joined() ?? [$0] }
    }
}

// removing an objc KVO observer if there is none throws an exception
extension NSObject {
    func safeRemoveObserver(_ observer: NSObject, _ key: String) {
        guard observationInfo != nil else { return }
        removeObserver(observer, forKeyPath: key)
    }
}

extension Array where Element == Window {
    func firstIndexThatMatches(_ element: AXUIElement) -> Self.Index? {
        // `CFEqual` is safer than comparing `CGWindowID` because it will succeed even if the window is deallocated
        // by the OS, in which case the `CGWindowID` will be `-1`
        return firstIndex(where: { CFEqual($0.axUiElement, element) })
    }

    func firstWindowThatMatches(_ element: AXUIElement) -> Window? {
        guard let index = firstIndexThatMatches(element) else { return nil }
        return self[index]
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

extension NSGridView {
    // set height for all rows
    func setRowsHeight(_ height: CGFloat) {
        for i in 0..<numberOfRows {
            row(at: i).height = height
        }
    }
}

extension Array {
    // forEach with each iteration run concurrently on the global queue
    func forEachAsync(fn: @escaping (Element) -> Void) {
        let group = DispatchGroup()
        for element in self {
            group.enter()
            DispatchQueue.global(qos: .userInteractive).async(group: group) {
                fn(element)
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
