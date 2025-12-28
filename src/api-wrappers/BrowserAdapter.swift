import AppKit
import ScriptingBridge

struct BrowserTabInfo {
    let tabId: String
    let windowIndex: Int
    let tabIndex: Int
    let title: String
    let url: String
    let isActive: Bool
    let isIncognito: Bool
    let bundleIdentifier: String
    
    var uniqueId: String {
        return "\(bundleIdentifier):\(tabId)"
    }
    
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

protocol BrowserAdapter {
    static var supportedBundleIds: [String] { get }
    static func supports(_ bundleIdentifier: String) -> Bool
    static func fetchAllTabs(bundleIdentifier: String) -> [BrowserTabInfo]
    static func activateTab(bundleIdentifier: String, tabId: String) -> Bool
    static func getActiveTabId(bundleIdentifier: String) -> String?
}

extension BrowserAdapter {
    static func supports(_ bundleIdentifier: String) -> Bool {
        return supportedBundleIds.contains { bundleIdentifier.hasPrefix($0) }
    }
}

class BrowserTabManager {
    private static let adapters: [BrowserAdapter.Type] = [
        ChromiumBrowserAdapter.self,
        DiaBrowserAdapter.self,
        ArcBrowserAdapter.self,
    ]
    
    private static var tabCache: [String: [BrowserTabInfo]] = [:]
    private static var lastRefresh: Date = .distantPast
    private static let cacheValiditySeconds: TimeInterval = 1.0
    private static var isRefreshing = false
    private static var faviconCache: [String: CGImage] = [:]
    private static var previewCache: [String: CachedTabPreview] = [:]
    private static let cacheQueue = DispatchQueue(label: "com.alttab.browserTabManager.cache")
    
    private static func adapter(for bundleIdentifier: String) -> BrowserAdapter.Type? {
        return adapters.first { $0.supports(bundleIdentifier) }
    }
    
    static func isSupportedBrowser(_ bundleIdentifier: String?) -> Bool {
        guard let bundleId = bundleIdentifier else { return false }
        return adapter(for: bundleId) != nil
    }
    
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
    
    static func refreshCacheInBackground() {
        guard !isRefreshing else { return }
        isRefreshing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let browserBundleIds = Applications.list
                .compactMap { $0.bundleIdentifier }
                .filter { isSupportedBrowser($0) }
            
            var newCache: [String: [BrowserTabInfo]] = [:]
            for bundleId in browserBundleIds {
                if let browserAdapter = adapter(for: bundleId) {
                    newCache[bundleId] = browserAdapter.fetchAllTabs(bundleIdentifier: bundleId)
                }
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
    
    static func activateTab(bundleIdentifier: String, tabId: String) -> Bool {
        guard let browserAdapter = adapter(for: bundleIdentifier) else { return false }
        let result = browserAdapter.activateTab(bundleIdentifier: bundleIdentifier, tabId: tabId)
        if result {
            lastRefresh = .distantPast
        }
        return result
    }
    
    static func getNonActiveTabsForApplication(_ application: Application) -> [BrowserTabInfo] {
        guard let bundleId = application.bundleIdentifier,
              isSupportedBrowser(bundleId) else {
            return []
        }
        
        let allTabs = getAllTabs(bundleIdentifier: bundleId)
        return allTabs.filter { !$0.isActive }
    }
    
    static func getActiveTabId(bundleIdentifier: String) -> String? {
        guard let browserAdapter = adapter(for: bundleIdentifier) else { return nil }
        return browserAdapter.getActiveTabId(bundleIdentifier: bundleIdentifier)
    }
}
