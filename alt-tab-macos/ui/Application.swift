import Foundation
import Cocoa

let cgsMainConnectionId = CGSMainConnectionID()

class Application: NSApplication, NSApplicationDelegate, NSWindowDelegate {
    static let name = "AltTab"
    let observer = Observer()
    var statusItem: NSStatusItem?
    var thumbnailsPanel: ThumbnailsPanel?
    var preferencesPanel: PreferencesPanel?
    var uiWorkShouldBeDone = true
    var isFirstSummon = true
    var isOutdated = false
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
        observer.clearObservers()
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

    func closeTarget() {
        if appIsBeingUsed {
            debugPrint("closeTarget")
            closeSelectedWindow(TrackedWindows.focusedWindow())
        }
    }

    func quitTargetApp() {
        if appIsBeingUsed {
            debugPrint("quitTargetApp")
            quitApplicationOfSelectedWindow(TrackedWindows.focusedWindow())
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
        if isFirstSummon || isOutdated {
            debugPrint("showUiOrCycleSelection: isFirstSummon", isFirstSummon, "isOutdated", isOutdated)
            isFirstSummon = false
            isOutdated = false
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

    func closeSelectedWindow(_ window: TrackedWindow?) {
        observer.createObserver(window!, self, .refreshUiOnClose)
        DispatchQueue.global(qos: .userInteractive).async { window?.close() }
    }

    func quitApplicationOfSelectedWindow(_ window: TrackedWindow?) {
        observer.createObserver(window!, self, .refreshUiOnQuit)
        DispatchQueue.global(qos: .userInteractive).async { window?.quitApp() }
    }
}
