import Foundation
import Cocoa

let cgsMainConnectionId = CGSMainConnectionID()

class Application: NSApplication, NSApplicationDelegate, NSWindowDelegate {
    static let name = "AltTab"
    var statusItem: NSStatusItem?
    var thumbnailsPanel: ThumbnailsPanel?
    var preferencesPanel: PreferencesPanel?
    var uiWorkShouldBeDone = true
    var isFirstSummon = true
    var appIsBeingUsed = false

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
        warmUpThumbnailPanel()
    }

    // running this code on startup avoid having the very first invocation be slow for the user
    private func warmUpThumbnailPanel() {
        thumbnailsPanel!.computeThumbnails(Screen.preferred())
    }

    // we put application code here which should be executed on init() and Preferences change
    func initPreferencesDependentComponents() {
        thumbnailsPanel = ThumbnailsPanel(self)
    }

    func hideUi() {
        debugPrint("hideUi")
        thumbnailsPanel!.orderOut(nil)
        appIsBeingUsed = false
        isFirstSummon = true
    }

    func focusTarget() {
        debugPrint("focusTarget")
        if appIsBeingUsed {
            debugPrint("focusTarget: appIsBeingUsed")
            focusSelectedWindow(TrackedWindows.focusedWindow())
        }
    }

    @objc
    func showPreferencesPanel() {
        if preferencesPanel == nil {
            preferencesPanel = PreferencesPanel()
        }
        Screen.showPanel(preferencesPanel!, Screen.preferred(), .appleCentered)
    }

    @objc
    func showUi() {
        uiWorkShouldBeDone = true
        showUiOrCycleSelection(0)
    }

    func cycleSelection(_ step: Int) {
        TrackedWindows.focusedWindowIndex = TrackedWindows.moveFocusedWindowIndex(step)
        self.thumbnailsPanel!.highlightCellAt(step)
    }

    func showUiOrCycleSelection(_ step: Int) {
        debugPrint("showUiOrCycleSelection", step)
        appIsBeingUsed = true
        if isFirstSummon {
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            isFirstSummon = false
            TrackedWindows.refreshList(step)
            if TrackedWindows.list.count == 0 {
                appIsBeingUsed = false
                isFirstSummon = true
                return
            }
            TrackedWindows.focusedWindowIndex = TrackedWindows.moveFocusedWindowIndex(step)
            let currentScreen = Screen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
            if uiWorkShouldBeDone { self.thumbnailsPanel!.computeThumbnails(currentScreen); debugPrint("computeThumbnails") }
            if uiWorkShouldBeDone { self.thumbnailsPanel!.highlightCellAt(step); debugPrint("highlightCellAt") }
            if uiWorkShouldBeDone { Screen.showPanel(self.thumbnailsPanel!, currentScreen, .appleCentered); debugPrint("showPanel") }
        } else {
            debugPrint("showUiOrCycleSelection: !isFirstSummon")
            cycleSelection(step)
        }
    }

    func focusSelectedWindow(_ window: TrackedWindow?) {
        hideUi()
        DispatchQueue.global(qos: .userInteractive).async { window?.focus() }
    }
}
