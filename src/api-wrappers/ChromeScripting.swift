import AppKit
import ScriptingBridge

// MARK: - Chrome/Chromium Browser Protocols

@objc public protocol ChromiumBrowserApplication {
    @objc optional func windows() -> SBElementArray
    @objc optional var name: String { get }
    @objc optional var frontmost: Bool { get }
    @objc optional var version: String { get }
    @objc optional var isRunning: Bool { get }
    @objc optional func activate()
}

@objc public protocol ChromiumBrowserWindow {
    @objc optional func tabs() -> SBElementArray
    @objc optional var name: String { get }
    @objc optional func id() -> Int
    @objc optional var index: Int { get }
    @objc optional var bounds: NSRect { get }
    @objc optional var minimized: Bool { get }
    @objc optional var visible: Bool { get }
    @objc optional var activeTab: ChromiumBrowserTab { get }
    @objc optional var activeTabIndex: Int { get }
    @objc optional var mode: String { get }
    @objc optional func setActiveTabIndex(_ activeTabIndex: Int)
}

@objc public protocol ChromiumBrowserTab {
    @objc optional func id() -> Int
    @objc optional var title: String { get }
    @objc optional var URL: String { get }
    @objc optional var loading: Bool { get }
}

extension SBApplication: ChromiumBrowserApplication {}
extension SBObject: ChromiumBrowserWindow, ChromiumBrowserTab {}

// MARK: - Browser Tab Info

struct BrowserTabInfo {
    let windowIndex: Int
    let tabIndex: Int
    let title: String
    let url: String
    let isActive: Bool
    let isIncognito: Bool
    let bundleIdentifier: String
    
    var displayTitle: String {
        if !title.isEmpty {
            return title
        }
        return url.isEmpty ? "Untitled" : url
    }
    
    var faviconUrls: [URL] {
        guard let tabUrl = URL(string: url),
              let host = tabUrl.host,
              !host.isEmpty else { return [] }
        var urls: [URL] = []
        if let ddg = URL(string: "https://icons.duckduckgo.com/ip3/\(host).ico") {
            urls.append(ddg)
        }
        if let google = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=128") {
            urls.append(google)
        }
        return urls
    }
    
    var faviconUrl: URL? {
        return faviconUrls.first
    }
}

struct CachedTabPreview {
    let screenshot: CGImage
    let position: CGPoint
    let size: CGSize
    let timestamp: Date
}

// MARK: - Browser Tab Manager

class BrowserTabManager {
    
    static let supportedBrowsers: [String] = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "com.google.Chrome.beta",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Canary",
        "com.vivaldi.Vivaldi",
        "com.vivaldi.Vivaldi.snapshot",
        "ai.perplexity.comet",
        "com.opera.Opera",
        "com.operasoftware.Opera",
    ]
    
    private static var tabCache: [String: [BrowserTabInfo]] = [:]
    private static var lastRefresh: Date = .distantPast
    private static let cacheValiditySeconds: TimeInterval = 1.0
    private static var isRefreshing = false
    private static var faviconCache: [String: CGImage] = [:]
    private static var previewCache: [String: CachedTabPreview] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.alttab.browserTabManager.cache")
    
    static func getCachedPreview(for url: String) -> CachedTabPreview? {
        return cacheQueue.sync { previewCache[url] }
    }
    
    static func cachePreview(for url: String, screenshot: CGImage, position: CGPoint, size: CGSize) {
        cacheQueue.sync {
            previewCache[url] = CachedTabPreview(screenshot: screenshot, position: position, size: size, timestamp: Date())
        }
    }
    
    static func getFavicon(for url: String) -> CGImage? {
        return cacheQueue.sync { faviconCache[url] }
    }
    
    static func fetchFavicon(for tabInfo: BrowserTabInfo, completion: @escaping (CGImage?) -> Void) {
        let faviconUrls = tabInfo.faviconUrls
        guard !faviconUrls.isEmpty else {
            completion(nil)
            return
        }
        
        let cacheKey = tabInfo.url
        if let cached = cacheQueue.sync(execute: { faviconCache[cacheKey] }) {
            completion(cached)
            return
        }
        
        fetchFaviconFromUrls(faviconUrls, cacheKey: cacheKey, completion: completion)
    }
    
    private static func fetchFaviconFromUrls(_ urls: [URL], cacheKey: String, completion: @escaping (CGImage?) -> Void) {
        guard let url = urls.first else {
            completion(nil)
            return
        }
        
        let remainingUrls = Array(urls.dropFirst())
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let data = data,
               let nsImage = NSImage(data: data),
               let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
               cgImage.width >= 32 && cgImage.height >= 32 {
                cacheQueue.sync { faviconCache[cacheKey] = cgImage }
                completion(cgImage)
            } else if !remainingUrls.isEmpty {
                fetchFaviconFromUrls(remainingUrls, cacheKey: cacheKey, completion: completion)
            } else {
                completion(nil)
            }
        }.resume()
    }
    
    static func prefetchFavicons(for tabs: [BrowserTabInfo]) {
        for tab in tabs {
            fetchFavicon(for: tab) { _ in }
        }
    }
    
    static func isSupportedBrowser(_ bundleIdentifier: String?) -> Bool {
        guard let bundleId = bundleIdentifier else { return false }
        return supportedBrowsers.contains { bundleId.hasPrefix($0) }
    }
    
    
    static func refreshCacheInBackground() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let browserBundleIds = Applications.list
                .compactMap { $0.bundleIdentifier }
                .filter { isSupportedBrowser($0) }
            
            var newCache: [String: [BrowserTabInfo]] = [:]
            for bundleId in browserBundleIds {
                newCache[bundleId] = fetchAllTabs(bundleIdentifier: bundleId)
            }
            
            DispatchQueue.main.async {
                tabCache = newCache
                lastRefresh = Date()
                isRefreshing = false
            }
        }
    }
    
    static func getAllTabs(bundleIdentifier: String) -> [BrowserTabInfo] {
        let cacheAge = Date().timeIntervalSince(lastRefresh)
        if cacheAge > cacheValiditySeconds {
            refreshCacheInBackground()
        }
        return tabCache[bundleIdentifier] ?? []
    }
    
    private static func fetchAllTabs(bundleIdentifier: String) -> [BrowserTabInfo] {
        guard let browser: ChromiumBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return []
        }
        guard browser.isRunning == true else {
            return []
        }
        var allTabs: [BrowserTabInfo] = []
        guard let windows = browser.windows?() else {
            return []
        }
        for (windowIndex, windowObj) in windows.enumerated() {
            guard let window = windowObj as? ChromiumBrowserWindow else { continue }
            let isIncognito = window.mode == "incognito"
            let activeTabIndex = window.activeTabIndex ?? 0
            guard let tabs = window.tabs?() else { continue }
            for (tabIndex, tabObj) in tabs.enumerated() {
                guard let tab = tabObj as? ChromiumBrowserTab else { continue }
                let isActive = tabIndex == activeTabIndex - 1
                let tabInfo = BrowserTabInfo(
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: tab.title ?? "",
                    url: tab.URL ?? "",
                    isActive: isActive,
                    isIncognito: isIncognito,
                    bundleIdentifier: bundleIdentifier
                )
                allTabs.append(tabInfo)
            }
        }
        return allTabs
    }
    
    static func activateTab(bundleIdentifier: String, windowIndex: Int, tabIndex: Int) -> Bool {
        guard let browser: ChromiumBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return false
        }
        guard browser.isRunning == true else {
            return false
        }
        guard let windows = browser.windows?() else {
            return false
        }
        guard windowIndex < windows.count else {
            return false
        }
        guard let window = windows.object(at: windowIndex) as? ChromiumBrowserWindow else {
            return false
        }
        window.setActiveTabIndex?(tabIndex + 1)
        browser.activate?()
        lastRefresh = .distantPast
        return true
    }
    
    static func getNonActiveTabsForApplication(_ application: Application) -> [BrowserTabInfo] {
        guard let bundleId = application.bundleIdentifier,
              isSupportedBrowser(bundleId) else {
            return []
        }
        
        let allTabs = getAllTabs(bundleIdentifier: bundleId)
        return allTabs.filter { !$0.isActive }
    }
}
