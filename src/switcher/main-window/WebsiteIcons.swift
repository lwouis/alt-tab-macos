import Cocoa

/// Shows the displayed website's icon on browser windows. Works with any browser that exposes the standard accessibility
/// URL attributes; there is no browser-specific code. State and layer updates stay on the main thread.
final class WebsiteIcons {
    private struct Cached {
        weak var window: Window?
        let url: URL?
        let image: CGImage?
        let title: String
        let hasWebArea: Bool
        let expires: Date
        let confirmed: Date
    }
    private struct Lookup {
        let document: URL?
        let hasWebArea: Bool
    }
    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "website-icons"
        queue.maxConcurrentOperationCount = 4
        queue.qualityOfService = .utility
        return queue
    }()
    private static var cache: [ObjectIdentifier: Cached] = [:]
    private static var pending: [ObjectIdentifier: String] = [:]
    private static var navigatedWhilePending = Set<ObjectIdentifier>()
    private static var generation = 0
    static var enabled: Bool { Preferences.showWebsiteIcons }

    static func reset() {
        generation += 1
        cache.removeAll()
        pending.removeAll()
        navigatedWhilePending.removeAll()
        WebsiteIconResolver.reset()
        for view in TilesView.recycledViews {
            if let window = view.window_ { view.updateDisplayedAppIcon(window.icon) }
        }
    }

    /// Returns the last known icon immediately and refreshes it in the background; the tile updates when it arrives.
    /// Called on every tile refresh, so a title change (navigation) while the switcher is open triggers a new lookup.
    static func icon(for window: Window, retryBudget: Int = 4, force: Bool = false) -> CGImage? {
        // In-process AX calls re-enter AppKit, which must not happen off the main thread.
        guard enabled, window.application.pid != ProcessInfo.processInfo.processIdentifier,
              window.axUiElement != nil || window.cgWindowId != nil else { return nil }
        let key = ObjectIdentifier(window)
        let old = cache[key]?.window === window ? cache[key] : nil
        let title = window.title
        if let requestedTitle = pending[key] {
            if requestedTitle != title { navigatedWhilePending.insert(key) }
            return old?.image
        }
        guard pending.count < 32 else { return old?.image }
        // A fresh result stands until its title changes (navigation). Windows without a web area (terminals, settings)
        // ignore title changes, so a spinner in their title doesn't trigger lookups.
        if !force, let old, old.expires > Date(), !old.hasWebArea || old.title == title { return old.image }
        pending[key] = title
        let epoch = generation
        // A window that appears while the switcher is open can be listed before AltTab has its AX element.
        let element = window.axUiElement, wid = window.cgWindowId, pid = window.application.pid
        queue.addOperation {
            let resolved = element ?? wid.flatMap { WindowElementAcquisition.element(for: $0, pid: pid, route: .currentSpaceViaApplicationWindows) }
            guard let resolved else {
                DispatchQueue.main.async { withoutHomepage(window, key, Lookup(document: nil, hasWebArea: true), old, retryBudget, epoch) }
                return
            }
            lookUp(window, resolved, key, old, retryBudget, epoch)
        }
        return old?.image
    }

    private static func lookUp(_ window: Window, _ element: AXUIElement, _ key: ObjectIdentifier, _ old: Cached?, _ retryBudget: Int, _ epoch: Int) {
        let lookup = documentURL(element)
        guard let url = lookup.document.flatMap(WebsiteIconResolver.homepage(for:)) else {
            DispatchQueue.main.async { withoutHomepage(window, key, lookup, old, retryBudget, epoch) }
            return
        }
        if old?.url == url, let old, old.expires > Date() {
            DispatchQueue.main.async {
                guard epoch == generation else { return }
                finish(window, key, url, old.image, expires: old.expires)
            }
            return
        }
        WebsiteIconResolver.resolve(url) { image in
            queue.addOperation {
                let current = documentURL(element).document.flatMap(WebsiteIconResolver.homepage(for:))
                DispatchQueue.main.async {
                    guard epoch == generation, enabled else { return }
                    guard current == url else {
                        pending.removeValue(forKey: key)
                        retry(window, retryBudget, epoch)
                        return
                    }
                    finish(window, key, url, image ?? WebsiteIconRenderer.placeholder)
                }
            }
        }
    }

    /// A web area without a URL yet is a page still loading: retry shortly instead of waiting for the next summon. While
    /// navigating, browsers also briefly expose no URL, so a recent icon is kept. A web page with no public homepage gets
    /// the globe; other windows (settings, new tab pages) keep the browser's icon.
    private static func withoutHomepage(_ window: Window, _ key: ObjectIdentifier, _ lookup: Lookup, _ old: Cached?, _ retryBudget: Int, _ epoch: Int) {
        guard epoch == generation, enabled else { return }
        let recentIcon = old?.image != nil && Date().timeIntervalSince(old!.confirmed) < 8
        // A brand-new browser window has no web area for a moment, so a missing one is retried before it's trusted.
        if lookup.document == nil, lookup.hasWebArea || recentIcon || retryBudget > 0 {
            let expires = Date().addingTimeInterval(retryBudget > 0 ? 4 : 1)
            finish(window, key, nil, recentIcon ? old?.image : nil, hasWebArea: lookup.hasWebArea || recentIcon, expires: expires, refresh: false)
            retry(window, retryBudget, epoch)
            return
        }
        finish(window, key, nil, ["http", "https"].contains(lookup.document?.scheme ?? "") ? WebsiteIconRenderer.placeholder : nil, hasWebArea: lookup.hasWebArea)
    }

    /// Bounded backoff (0.25, 0.5, 1 and 2 seconds) while the switcher is open; no timer runs otherwise.
    private static func retry(_ window: Window, _ budget: Int, _ epoch: Int) {
        guard budget > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * pow(2, Double(max(0, 4 - budget)))) {
            guard epoch == generation, SwitcherSession.isActive, Windows.list.contains(where: { $0 === window }) else { return }
            _ = icon(for: window, retryBudget: budget - 1, force: true)
        }
    }

    /// Safari exposes `AXDocument` on some windows; WebKit, Chromium and Firefox all expose `AXURL` on the tab's
    /// `AXWebArea`. The search stops at the first web area and never enters page content: at most 128 elements, depth 8,
    /// 1 second, 100ms per call. Chromium enables basic web accessibility for its process once a client reaches its web
    /// contents; on a page mutating 50 DOM nodes every 100ms this measured about 3 to 5% more Chrome CPU and no memory change.
    private static func documentURL(_ root: AXUIElement) -> Lookup {
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.1)
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
            return value
        }
        // A new browser window reports `about:blank` here while loading, so only web documents end the search early.
        if let text = attribute(root, kAXDocumentAttribute) as? String, let url = URL(string: text), ["http", "https"].contains(url.scheme ?? "") {
            return Lookup(document: url, hasWebArea: true)
        }
        var remaining = [(root, 0)]
        let deadline = Date().addingTimeInterval(1)
        var visited = 0
        while let (element, depth) = remaining.popLast(), visited < 128, Date() < deadline {
            visited += 1
            if attribute(element, kAXRoleAttribute) as? String == "AXWebArea" {
                if let url = attribute(element, kAXURLAttribute) as? URL { return Lookup(document: url, hasWebArea: true) }
                if let text = attribute(element, kAXURLAttribute) as? String, let url = URL(string: text) { return Lookup(document: url, hasWebArea: true) }
                return Lookup(document: nil, hasWebArea: true)
            }
            if depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                remaining.append(contentsOf: children.prefix(128 - visited).reversed().map { ($0, depth + 1) })
            }
        }
        return Lookup(document: nil, hasWebArea: false)
    }

    /// Records the result for the title the lookup started with. If the title changed meanwhile, the result may describe
    /// the previous page, so another lookup starts right away.
    private static func finish(_ window: Window, _ key: ObjectIdentifier, _ url: URL?, _ image: CGImage?, hasWebArea: Bool = true, expires: Date? = nil, refresh: Bool = true) {
        let title = pending.removeValue(forKey: key) ?? window.title
        cache = cache.filter { $0.value.window != nil }
        guard Windows.list.contains(where: { $0 === window }) else { cache.removeValue(forKey: key); return }
        if cache.count >= 128, let oldest = cache.min(by: { $0.value.confirmed < $1.value.confirmed }) { cache.removeValue(forKey: oldest.key) }
        let lifetime: TimeInterval = !hasWebArea ? 30 : url == nil ? 1 : (image === WebsiteIconRenderer.placeholder ? 5 : 30)
        cache[key] = Cached(window: window, url: url, image: image, title: title, hasWebArea: hasWebArea,
                            expires: expires ?? Date().addingTimeInterval(lifetime), confirmed: Date())
        guard SwitcherSession.isActive else { return }
        if refresh || image != nil {
            for view in TilesView.recycledViews where view.window_ === window {
                view.updateDisplayedAppIcon(image ?? window.icon)
            }
        }
        if navigatedWhilePending.remove(key) != nil || hasWebArea && title != (window.title) {
            DispatchQueue.main.async { _ = icon(for: window, force: true) }
        }
    }
}
