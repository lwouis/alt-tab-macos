import AppKit
import ScriptingBridge

@objc public protocol ArcBrowserApplication {
    @objc optional func windows() -> SBElementArray
    @objc optional var name: String { get }
    @objc optional var frontmost: Bool { get }
    @objc optional var version: String { get }
    @objc optional var isRunning: Bool { get }
    @objc optional func activate()
}

@objc public protocol ArcBrowserWindow {
    @objc optional func tabs() -> SBElementArray
    @objc optional func id() -> String
    @objc optional var name: String { get }
    @objc optional var index: Int { get }
    @objc optional var minimized: Bool { get }
    @objc optional var visible: Bool { get }
    @objc optional var incognito: Bool { get }
    @objc optional var activeTab: ArcBrowserTab { get }
}

@objc public protocol ArcBrowserTab {
    @objc optional func id() -> String
    @objc optional var title: String { get }
    @objc optional var URL: String { get }
    @objc optional var loading: Bool { get }
    @objc optional var location: String { get }
    @objc optional func select()
}

extension SBApplication: ArcBrowserApplication {}
extension SBObject: ArcBrowserWindow, ArcBrowserTab {}

class ArcBrowserAdapter: BrowserAdapter {
    static let supportedBundleIds: [String] = [
        "company.thebrowser.Browser",
    ]
    
    static func fetchAllTabs(bundleIdentifier: String) -> [BrowserTabInfo] {
        guard let browser: ArcBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
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
            guard let window = windowObj as? ArcBrowserWindow else { continue }
            let isIncognito = window.incognito ?? false
            let activeTabId = window.activeTab?.id?()
            guard let tabs = window.tabs?() else { continue }
            for (tabIndex, tabObj) in tabs.enumerated() {
                guard let tab = tabObj as? ArcBrowserTab else { continue }
                let tabId = tab.id?() ?? ""
                let isActive = tabId == activeTabId
                let tabInfo = BrowserTabInfo(
                    tabId: String(tabId),
                    windowIndex: windowIndex,
                    tabIndex: tabIndex,
                    title: String(tab.title ?? ""),
                    url: String(tab.URL ?? ""),
                    isActive: isActive,
                    isIncognito: isIncognito,
                    bundleIdentifier: bundleIdentifier
                )
                allTabs.append(tabInfo)
            }
        }
        return allTabs
    }
    
    static func activateTab(bundleIdentifier: String, tabId: String) -> Bool {
        guard let browser: ArcBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return false
        }
        guard browser.isRunning == true else {
            return false
        }
        guard let windows = browser.windows?() else {
            return false
        }
        
        for windowObj in windows {
            guard let window = windowObj as? ArcBrowserWindow,
                  let tabs = window.tabs?() else { continue }
            
            for tabObj in tabs {
                guard let tab = tabObj as? ArcBrowserTab,
                      tab.id?() == tabId else { continue }
                
                tab.select?()
                browser.activate?()
                return true
            }
        }
        return false
    }
    
    static func getActiveTabId(bundleIdentifier: String) -> String? {
        guard let browser: ArcBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        guard browser.isRunning == true else {
            return nil
        }
        guard let windows = browser.windows?(),
              let firstWindow = windows.firstObject as? ArcBrowserWindow else {
            return nil
        }
        return firstWindow.activeTab?.id?()
    }
}
