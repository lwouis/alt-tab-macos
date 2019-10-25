import Foundation
import Cocoa

class Application: NSApplication, NSApplicationDelegate, NSWindowDelegate {
    static let name = "AltTab"
    var statusItem: NSStatusItem?
    var backgroundView: NSVisualEffectView?
    var thumbnailsPanel: ThumbnailsPanel?
    var preferencesPanel: PreferencesPanel?
    var selectedOpenWindow: Int = 0
    var numberOfColumns: Int = 0
    var openWindows: [OpenWindow] = []
    var workItems: [DispatchWorkItem] = []
    var isFirstSummon: Bool = true
    var appIsBeingUsed: Bool = false

    override init() {
        super.init()
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        SystemPermissions.ensureScreenRecordingCheckboxIsChecked()
        SystemPermissions.ensureAccessibilityCheckboxIsChecked()
        Preferences.loadFromDiskAndUpdateValues()
        Screen.updateThumbnailMaxSize()
        statusItem = StatusItem.make(self)
        thumbnailsPanel = ThumbnailsPanel(self)
        preferencesPanel = PreferencesPanel()
        Keyboard.listenToGlobalEvents(self)
        Screen.listenToChanges()
    }

    @objc func showCenteredPreferencesPanel() {
        showCenteredPanel(preferencesPanel!)
    }

    func showCenteredPanel(_ panel: NSPanel) {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        Application.shared.arrangeInFront(nil)
    }

    func computeOpenWindows() {
        openWindows.removeAll()
        // we rely on the fact that CG and AX APIs arrays follow the same order to match objects from both APIs
        var pidAndCurrentIndex: [pid_t: Int] = [:]
        for cgWindow in cgWindows() {
            let cgId = cgWindow[kCGWindowNumber] as! CGWindowID
            let cgTitle = cgWindow[kCGWindowName] as? String ?? ""
            let cgOwnerName = cgWindow[kCGWindowOwnerName] as? String ?? ""
            let cellTitle = cgTitle.isEmpty ? cgOwnerName : cgTitle
            let cgOwnerPid = cgWindow[kCGWindowOwnerPID] as! pid_t
            let i = pidAndCurrentIndex.index(forKey: cgOwnerPid)
            pidAndCurrentIndex[cgOwnerPid] = (i == nil ? 0 : pidAndCurrentIndex[i!].value + 1)
            let axWindows_ = axWindows(cgOwnerPid)
            // windows may have changed between the CG and the AX calls
            if axWindows_.count > pidAndCurrentIndex[cgOwnerPid]! {
                openWindows.append(OpenWindow(target: axWindows_[pidAndCurrentIndex[cgOwnerPid]!], ownerPid: cgOwnerPid, cgId: cgId, cgTitle: cellTitle))
            }
        }
    }

    func cellWithStep(_ step: Int) -> Int {
        selectedOpenWindow + step < 0 ? openWindows.count - 1 : (selectedOpenWindow + step) % openWindows.count
    }

    func selectOtherCell(_ step: Int) {
        appIsBeingUsed = true
        if openWindows.count > 0 {
            selectedOpenWindow = cellWithStep(step)
            if isFirstSummon {
                isFirstSummon = false
                let workItem = DispatchWorkItem {
                    self.computeOpenWindows()
                    self.thumbnailsPanel!.computeThumbnails()
                    self.thumbnailsPanel!.highlightThumbnail(step)
                    self.showCenteredPanel(self.thumbnailsPanel!)
                }
                workItems.append(workItem)
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay!, execute: workItem)
            } else {
                self.thumbnailsPanel!.highlightThumbnail(step)
            }
        }
    }

    func currentlySelectedWindow() -> OpenWindow? {
        openWindows.count > selectedOpenWindow ? openWindows[selectedOpenWindow] : nil
    }

    func closeThumbnailsPanel() {
        thumbnailsPanel!.orderOut(nil)
        appIsBeingUsed = false
        isFirstSummon = true
    }

    func focusSelectedWindow(_ window: OpenWindow?) {
        workItems.forEach({ $0.cancel() })
        workItems.removeAll()
        window?.focus()
        closeThumbnailsPanel()
    }

    func keyDownMeta() {
        debugPrint("meta down")
        computeOpenWindows()
        selectedOpenWindow = 0
    }

    func keyDownMetaTab() {
        debugPrint("meta+tab down")
        selectOtherCell(1)
    }

    func keyDownMetaShiftTab() {
        debugPrint("meta+shift+tab down")
        selectOtherCell(-1)
    }

    func keyDownMetaEsc() {
        debugPrint("meta+esc down")
        closeThumbnailsPanel()
    }

    func keyUpMeta() {
        debugPrint("meta up")
        if appIsBeingUsed {
            focusSelectedWindow(currentlySelectedWindow())
        }
    }
}
