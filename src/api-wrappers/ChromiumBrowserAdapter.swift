import AppKit
import ScriptingBridge

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
    @objc optional func setIndex(_ index: Int)
}

@objc public protocol ChromiumBrowserTab {
    @objc optional func id() -> Int
    @objc optional var title: String { get }
    @objc optional var URL: String { get }
    @objc optional var loading: Bool { get }
}

extension SBApplication: ChromiumBrowserApplication {}
extension SBObject: ChromiumBrowserWindow, ChromiumBrowserTab {}

class ChromiumBrowserAdapter: BrowserAdapter {
    static let supportedBundleIds: [String] = [
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
    
    static func fetchAllTabs(bundleIdentifier: String) -> [BrowserTabInfo] {
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
                let tabId = tab.id?() ?? 0
                let isActive = tabIndex == activeTabIndex - 1
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
        guard let numericId = Int(tabId) else { return false }
        guard let browser: ChromiumBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return false
        }
        guard browser.isRunning == true else {
            return false
        }
        guard let windows = browser.windows?() else {
            return false
        }
        
        for windowObj in windows {
            guard let window = windowObj as? ChromiumBrowserWindow,
                  let tabs = window.tabs?() else { continue }
            
            for (tabIndex, tabObj) in tabs.enumerated() {
                guard let tab = tabObj as? ChromiumBrowserTab,
                      tab.id?() == numericId else { continue }
                
                window.setActiveTabIndex?(tabIndex + 1)
                window.setIndex?(1)
                browser.activate?()
                return true
            }
        }
        return false
    }
    
    static func getActiveTabId(bundleIdentifier: String) -> String? {
        guard let browser: ChromiumBrowserApplication = SBApplication(bundleIdentifier: bundleIdentifier) else {
            return nil
        }
        guard browser.isRunning == true else {
            return nil
        }
        guard let windows = browser.windows?(),
              let firstWindow = windows.firstObject as? ChromiumBrowserWindow else {
            return nil
        }
        
        let activeTabIndex = firstWindow.activeTabIndex ?? 0
        guard activeTabIndex > 0,
              let tabs = firstWindow.tabs?(),
              activeTabIndex <= tabs.count,
              let activeTab = tabs[activeTabIndex - 1] as? ChromiumBrowserTab else {
            return nil
        }
        
        if let tabId = activeTab.id?() {
            return String(tabId)
        }
        return nil
    }
}
