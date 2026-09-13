import Cocoa
import ImageIO

/// Capability-based website icons. State and layer updates belong to the main thread.
final class NativeBrowserIconPrototype {
    private struct Cached {
        weak var window: Window?
        let url: URL?
        let image: CGImage?
        let expires: Date
        let confirmed: Date
    }
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "local.native-browser-icons"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()
    private static var cache: [ObjectIdentifier: Cached] = [:]
    private static var pending = Set<ObjectIdentifier>()
    private static var generation = 0
    private static let globe: CGImage? = {
        guard let png = IconRenderer.websitePlaceholder(), let data = Data(base64Encoded: png) else { return nil }
        return FixtureIconResolver.image(data)
    }()
    static var enabled: Bool { FixtureIconResolver.laboratory || Preferences.showWebsiteIcons }
    static func reset() {
        generation += 1
        cache.removeAll()
        pending.removeAll()
        FixtureIconResolver.reset()
        for view in TilesView.recycledViews {
            if let window = view.window_ { view.updateDisplayedAppIcon(window.icon) }
        }
    }
    static func icon(for window: Window, retryBudget: Int = 2) -> CGImage? {
        // In-process AX can enter AppKit directly; never inspect our own UI off-main.
        guard enabled, window.application.pid != ProcessInfo.processInfo.processIdentifier,
              let element = window.axUiElement else { return nil }
        let key = ObjectIdentifier(window)
        let old = cache[key]?.window === window ? cache[key] : nil
        guard !pending.contains(key), pending.count < 32 else { return old?.image }
        if old?.url == nil, let expires = old?.expires, expires > Date() { return old?.image }
        pending.insert(key)
        let epoch = generation
        queue.addOperation {
            let document = documentURL(element)
            let url = document.flatMap(FixtureIconResolver.pageForDocument)
            guard let url else {
                DispatchQueue.main.async {
                    guard epoch == generation, enabled else { return }
                    let retained = document == nil && old?.image != nil && Date().timeIntervalSince(old!.confirmed) < 8
                    if retained {
                        pending.remove(key)
                        retry(window, retryBudget, epoch)
                    } else {
                        let isWebpage = ["http", "https"].contains(document?.scheme ?? "")
                        finish(window, key, nil, isWebpage ? globe : nil)
                    }
                }
                return
            }
            if old?.url == url, let expires = old?.expires, expires > Date() {
                DispatchQueue.main.async {
                    guard epoch == generation else { return }
                    pending.remove(key)
                    if let old { cache[key] = Cached(window: window, url: url, image: old.image, expires: old.expires, confirmed: Date()) }
                }
                return
            }
            DispatchQueue.main.async {
                guard epoch == generation, enabled else { return }
                FixtureIconResolver.resolveArtwork(url) { artwork in
                    queue.addOperation {
                        let current = documentURL(element).flatMap(FixtureIconResolver.pageForDocument)
                        DispatchQueue.main.async {
                            guard epoch == generation, enabled else { return }
                            guard current == url else {
                                pending.remove(key)
                                retry(window, retryBudget, epoch)
                                return
                            }
                            finish(window, key, url, artwork?.image ?? globe)
                        }
                    }
                }
            }
        }
        return old?.image
    }
    private static func retry(_ window: Window, _ budget: Int, _ epoch: Int) {
        guard budget > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard epoch == generation, SwitcherSession.isActive, Windows.list.contains(where: { $0 === window }) else { return }
            _ = icon(for: window, retryBudget: budget - 1)
        }
    }
    /// Some browsers expose AXDocument on the window, others AXURL on the web area.
    private static func documentURL(_ root: AXUIElement) -> URL? {
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.1)
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return value
        }
        if let text = attribute(root, kAXDocumentAttribute) as? String, let url = URL(string: text) { return url }
        var remaining = [(root, 0)]
        let deadline = Date().addingTimeInterval(1)
        var visited = 0
        while let (element, depth) = remaining.popLast(), visited < 128, Date() < deadline {
            visited += 1
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                if let url = attribute(element, kAXURLAttribute) as? URL { return url }
                if let text = attribute(element, kAXURLAttribute) as? String { return URL(string: text) }
                continue // Never traverse page content.
            }
            if depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                remaining.append(contentsOf: children.prefix(128 - visited).reversed().map { ($0, depth + 1) })
            }
        }
        return nil
    }
    private static func finish(_ window: Window, _ key: ObjectIdentifier, _ url: URL?, _ image: CGImage?) {
        pending.remove(key)
        cache = cache.filter { $0.value.window != nil }
        guard Windows.list.contains(where: { $0 === window }) else { cache.removeValue(forKey: key); return }
        if cache.count >= 128, let oldest = cache.min(by: { $0.value.confirmed < $1.value.confirmed }) { cache.removeValue(forKey: oldest.key) }
        cache[key] = Cached(window: window, url: url, image: image,
            expires: Date().addingTimeInterval(url == nil ? 1 : (image === globe ? 5 : 30)), confirmed: Date())
        guard SwitcherSession.isActive else { return }
        for view in TilesView.recycledViews where view.window_ === window {
            view.updateDisplayedAppIcon(image ?? window.icon)
        }
    }
}
