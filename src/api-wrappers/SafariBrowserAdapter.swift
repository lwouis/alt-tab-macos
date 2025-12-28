import AppKit
import ScriptingBridge

@objc public protocol SafariBrowserApplication {
    @objc optional func windows() -> SBElementArray
    @objc optional var name: String { get }
    @objc optional var frontmost: Bool { get }
    @objc optional var version: String { get }
    @objc optional var isRunning: Bool { get }
    @objc optional func activate()
}

@objc public protocol SafariBrowserWindow {
    @objc optional func tabs() -> SBElementArray
    @objc optional var id: Int { get }
    @objc optional var name: String { get }
    @objc optional var index: Int { get }
    @objc optional var miniaturized: Bool { get }
    @objc optional var visible: Bool { get }
    @objc optional var currentTab: SafariBrowserTab { get }
    @objc optional func setCurrentTab(_ tab: SafariBrowserTab)
    @objc optional func setIndex(_ index: Int)
}

@objc public protocol SafariBrowserTab {
    @objc optional var name: String { get }
    @objc optional var URL: String { get }
    @objc optional var index: Int { get }
    @objc optional var visible: Bool { get }
}

extension SBApplication: SafariBrowserApplication {}
extension SBObject: SafariBrowserWindow, SafariBrowserTab {}

class SafariBrowserAdapter: BrowserAdapter {
    static let supportedBundleIds: [String] = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
    ]
    
    private static func makeTabId(windowId: Int, tabIndex: Int) -> String {
        return "\(windowId):\(tabIndex)"
    }
    
    private static func parseTabId(_ tabId: String) -> (windowId: Int, tabIndex: Int)? {
        let parts = tabId.split(separator: ":")
        guard parts.count == 2,
              let windowId = Int(parts[0]),
              let tabIndex = Int(parts[1]) else {
            return nil
        }
        return (windowId, tabIndex)
    }
    
    static func fetchAllTabs(bundleIdentifier: String) -> [BrowserTabInfo] {
        guard let browser: SafariBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
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
            guard let window = windowObj as? SafariBrowserWindow else { continue }
            let windowId = window.id ?? windowIndex
            let currentTabIndex = window.currentTab?.index ?? 1
            
            guard let tabs = window.tabs?() else { continue }
            
            for (tabIndex, tabObj) in tabs.enumerated() {
                guard let tab = tabObj as? SafariBrowserTab else { continue }
                let safariTabIndex = tab.index ?? (tabIndex + 1)
                let isActive = safariTabIndex == currentTabIndex
                let tabId = makeTabId(windowId: windowId, tabIndex: safariTabIndex)
                
                let tabInfo = BrowserTabInfo(
                    tabId: tabId,
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: String(tab.name ?? ""),
                    url: String(tab.URL ?? ""),
                    isActive: isActive,
                    isIncognito: false,
                    bundleIdentifier: bundleIdentifier
                )
                allTabs.append(tabInfo)
            }
        }
        return allTabs
    }
    
    static func activateTab(bundleIdentifier: String, tabId: String) -> Bool {
        guard let parsed = parseTabId(tabId) else { return false }
        guard let browser: SafariBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return false
        }
        guard browser.isRunning == true else {
            return false
        }
        guard let windows = browser.windows?() else {
            return false
        }
        
        for windowObj in windows {
            guard let window = windowObj as? SafariBrowserWindow,
                  window.id == parsed.windowId,
                  let tabs = window.tabs?() else { continue }
            
            for tabObj in tabs {
                guard let tab = tabObj as? SafariBrowserTab,
                      tab.index == parsed.tabIndex else { continue }
                
                window.setCurrentTab?(tab)
                window.setIndex?(1)
                browser.activate?()
                return true
            }
        }
        return false
    }
    
    static func getActiveTabId(bundleIdentifier: String) -> String? {
        guard let browser: SafariBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        guard browser.isRunning == true else {
            return nil
        }
        guard let windows = browser.windows?(),
              let firstWindow = windows.firstObject as? SafariBrowserWindow else {
            return nil
        }
        
        let windowId = firstWindow.id ?? 0
        let currentTabIndex = firstWindow.currentTab?.index ?? 1
        return makeTabId(windowId: windowId, tabIndex: currentTabIndex)
    }
}
