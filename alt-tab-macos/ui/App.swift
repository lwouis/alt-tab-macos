import Foundation
import Cocoa

let cgsMainConnectionId = CGSMainConnectionID()

class App: NSApplication, NSApplicationDelegate, NSWindowDelegate {
    static let name = "AltTab"
    var statusItem: NSStatusItem?
    var thumbnailsPanel: ThumbnailsPanel?
    var preferencesPanel: PreferencesWindow?
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
        SystemPermissions.ensureAccessibilityCheckboxIsChecked()
        SystemPermissions.ensureScreenRecordingCheckboxIsChecked()
        Preferences.loadFromDiskAndUpdateValues()
        statusItem = StatusItem.make(self)
        initPreferencesDependentComponents()
        Spaces.initialDiscovery()
        Applications.initialDiscovery()
        Keyboard.listenToGlobalEvents(self)
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
            let window = Windows.focusedWindow()
            focusSelectedWindow(window)
        }
    }

    @objc
    func showPreferencesPanel() {
        if preferencesPanel == nil {
            preferencesPanel = PreferencesWindow()
        }
        Screen.repositionPanel(preferencesPanel!, Screen.preferred(), .appleCentered)
        preferencesPanel?.show()
    }

    @objc
    func showUi() {
        uiWorkShouldBeDone = true
        showUiOrCycleSelection(0)
    }

    func cycleSelection(_ step: Int) {
        Windows.cycleFocusedWindowIndex(step)
        thumbnailsPanel!.highlightCell()
    }

    func showUiOrCycleSelection(_ step: Int) {
        debugPrint("showUiOrCycleSelection", step)
        appIsBeingUsed = true
        if isFirstSummon {
            debugPrint("showUiOrCycleSelection: isFirstSummon")
            isFirstSummon = false
            if Windows.list.count == 0 || CGWindow.isMissionControlActive() {
                appIsBeingUsed = false
                isFirstSummon = true
                return
            }
            // TODO: find a way to update isSingleSpace by listening to space creation, instead of on every trigger
            Spaces.updateIsSingleSpace()
            // TODO: find a way to update space index when windows are moved to another space, instead of on every trigger
            Windows.updateSpaces()
            // TODO: find a way to update thumbnails by listening to content change, instead of every trigger. Or better, switch to video
            Windows.refreshAllThumbnails()
            Windows.focusedWindowIndex = 0
            Windows.cycleFocusedWindowIndex(step)
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Preferences.windowDisplayDelay!, execute: {
                self.refreshOpenUi()
                if self.uiWorkShouldBeDone { self.thumbnailsPanel?.show() }
            })
        } else {
            debugPrint("showUiOrCycleSelection: !isFirstSummon")
            cycleSelection(step)
        }
    }

    func reopenUi() {
        thumbnailsPanel!.orderOut(nil)
        Windows.refreshAllThumbnails()
        refreshOpenUi()
        thumbnailsPanel!.show()
    }

    func refreshOpenUi() {
        guard appIsBeingUsed else { return }
        let currentScreen = Screen.preferred() // fix screen between steps since it could change (e.g. mouse moved to another screen)
        if uiWorkShouldBeDone { thumbnailsPanel!.refreshCollectionView(currentScreen, uiWorkShouldBeDone); debugPrint("refreshCollectionView") }
        if uiWorkShouldBeDone { thumbnailsPanel!.highlightCell(); debugPrint("highlightCellAt") }
        if uiWorkShouldBeDone { Screen.repositionPanel(thumbnailsPanel!, currentScreen, .appleCentered); debugPrint("repositionPanel") }
    }

    func focusSelectedWindow(_ window: Window?) {
        hideUi()
        guard !CGWindow.isMissionControlActive() else { return }
        window?.focus()
    }
}
