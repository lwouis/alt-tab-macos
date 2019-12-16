import Foundation
import Cocoa

class Application: NSApplication, NSApplicationDelegate, NSWindowDelegate {
    static let name = "AltTab"
    var statusItem: NSStatusItem?
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
        statusItem = StatusItem.make(self)
        initPreferencesDependentComponents()
        Keyboard.listenToGlobalEvents(self)
    }

    // we put application code here which should be executed on init() and Preferences change
    func initPreferencesDependentComponents() {
        thumbnailsPanel = ThumbnailsPanel(self)
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
        self.thumbnailsPanel!.orderOut(nil)
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

    @objc
    func showPreferencesPanel() {
        if preferencesPanel == nil {
            preferencesPanel = PreferencesPanel()
        }
        Screen.showPanel(preferencesPanel!, Screen.preferredScreen(), .appleCentered)
    }

    func computeOpenWindows() {
        openWindows.removeAll()
        // first pass: get all visible windows, in recently-used order
        computeOpenWindows_(.optionOnScreenOnly)
        // second pass: get all minimized windows, in fixed order
        computeOpenWindows_(.optionAll)
    }

    private func computeOpenWindows_(_ option: CGWindowListOption) {
        for cgWindow in CoreGraphicsApis.windows(option) {
            let cgId = CoreGraphicsApis.value(cgWindow, kCGWindowNumber, UInt32(0))
            if option == .optionOnScreenOnly {
                openWindows.append(OpenWindow(cgWindow, cgId, false, nil))
            } else {
                // not already there from the visible-windows first pass
                if openWindows.first(where: { $0.cgId == cgId }) == nil {
                    let ownerPid = CoreGraphicsApis.value(cgWindow, kCGWindowOwnerPID, Int32(0))
                    if let axWindow = AccessibilityApis.windowThatMatchCgWindow(ownerPid, cgId) {
                        if AccessibilityApis.attribute(axWindow, kAXMinimizedAttribute, Bool.self)! {
                            openWindows.append(OpenWindow(cgWindow, cgId, true, axWindow))
                        }
                    }
                }
            }
        }
    }

    func cellWithStep(_ step: Int) -> Int {
        return selectedOpenWindow + step < 0 ? openWindows.count - 1 : (selectedOpenWindow + step) % openWindows.count
    }

    func cycleSelection(_ step: Int) {
        selectedOpenWindow = cellWithStep(step)
        self.thumbnailsPanel!.highlightCellAt(step)
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
                let currentScreen = Screen.preferredScreen() // fix screen between steps since it could change (e.g. mouse moved to another screen)
                if !workItem.isCancelled { self.thumbnailsPanel!.computeThumbnails(currentScreen) }
                if !workItem.isCancelled { self.thumbnailsPanel!.highlightCellAt(step) }
                if !workItem.isCancelled { Screen.showPanel(self.thumbnailsPanel!, currentScreen, .appleCentered) }
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
