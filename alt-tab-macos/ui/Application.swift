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
    var isMetaKeyPressed: Bool = false

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

    func toggleMetaKey() {
        debugPrint("toggleMetaKey")
        isMetaKeyPressed = !isMetaKeyPressed
    }

    func showUiOrSelectNext() {
        debugPrint("showUiOrSelectNext")
        showUiOrCycleSelection(1)
    }

    func showUiOrSelectPrevious() {
        debugPrint("showUiOrSelectPrevious")
        showUiOrCycleSelection(-1)
    }

    func hideUi() {
        debugPrint("hideUi")
        DispatchQueue.main.async(execute: { self.thumbnailsPanel!.orderOut(nil) })
        appIsBeingUsed = false
        isFirstSummon = true
    }

    func focusTarget() {
        debugPrint("focusTarget")
        if appIsBeingUsed {
            focusSelectedWindow(currentlySelectedWindow())
            hideUi()
        }
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
                openWindows.append(OpenWindow(axWindows_[pidAndCurrentIndex[cgOwnerPid]!], cgOwnerPid, cgId, cellTitle))
            }
        }
    }

    func cellWithStep(_ step: Int) -> Int {
        return selectedOpenWindow + step < 0 ? openWindows.count - 1 : (selectedOpenWindow + step) % openWindows.count
    }

    func cycleSelection(_ step: Int) {
        selectedOpenWindow = cellWithStep(step)
        DispatchQueue.main.async(execute: { self.thumbnailsPanel!.highlightCellAt(step) })
    }

    func showUiOrCycleSelection(_ step: Int) {
        appIsBeingUsed = true
        if isFirstSummon {
            isFirstSummon = false
            selectedOpenWindow = 0
            computeOpenWindows()
            if openWindows.count <= 0 {
                return
            }
            selectedOpenWindow = cellWithStep(step)
            var workItem: DispatchWorkItem!
            workItem = DispatchWorkItem {
                if !workItem.isCancelled { self.thumbnailsPanel!.computeThumbnails() }
                if !workItem.isCancelled { self.thumbnailsPanel!.highlightCellAt(step) }
                if !workItem.isCancelled { self.showCenteredPanel(self.thumbnailsPanel!) }
            }
            workItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay!, execute: workItem)
        } else {
            cycleSelection(step)
        }
    }

    func focusSelectedWindow(_ window: OpenWindow?) {
        workItems.forEach({ $0.cancel() })
        workItems.removeAll()
        window?.focus()
    }

    func currentlySelectedWindow() -> OpenWindow? {
        return openWindows.count > selectedOpenWindow ? openWindows[selectedOpenWindow] : nil
    }
}
