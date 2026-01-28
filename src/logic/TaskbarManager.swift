import Cocoa

class TaskbarManager {
    static var shared = TaskbarManager()
    var taskbarPanels = [ScreenUuid: TaskbarPanel]()
    var isEnabled = false

    func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        createPanelsForAllScreens()
        updateContents()
        // adjust any already-maximized windows to leave room for taskbar
        adjustAllMaximizedWindows()
    }

    func disable() {
        guard isEnabled else { return }
        isEnabled = false
        for (_, panel) in taskbarPanels {
            panel.orderOut(nil)
        }
        taskbarPanels.removeAll()
    }

    private func createPanelsForAllScreens() {
        for screen in NSScreen.screens {
            if let uuid = screen.uuid(), taskbarPanels[uuid] == nil {
                let panel = TaskbarPanel(screenUuid: uuid)
                panel.positionAtScreenBottom(screen)
                panel.orderFront(nil)
                taskbarPanels[uuid] = panel
            }
        }
    }

    func repositionAll() {
        guard isEnabled else { return }

        let currentUuids = Set(NSScreen.screens.compactMap { $0.uuid() })
        let existingUuids = Set(taskbarPanels.keys)

        // remove panels for disconnected screens
        for uuid in existingUuids.subtracting(currentUuids) {
            taskbarPanels[uuid]?.orderOut(nil)
            taskbarPanels.removeValue(forKey: uuid)
        }

        // add panels for new screens and reposition existing
        for screen in NSScreen.screens {
            if let uuid = screen.uuid() {
                if let panel = taskbarPanels[uuid] {
                    panel.positionAtScreenBottom(screen)
                } else {
                    let panel = TaskbarPanel(screenUuid: uuid)
                    panel.positionAtScreenBottom(screen)
                    panel.orderFront(nil)
                    taskbarPanels[uuid] = panel
                }
            }
        }

        updateContents()
    }

    func updateContents() {
        guard isEnabled else { return }
        for (screenUuid, panel) in taskbarPanels {
            let filteredWindows = filterWindowsForTaskbar(screenUuid: screenUuid)
            panel.updateContents(filteredWindows)
        }
    }

    private func filterWindowsForTaskbar(screenUuid: ScreenUuid) -> [Window] {
        let screenSpaces = Spaces.screenSpacesMap[screenUuid] ?? []
        let visibleSpacesForScreen = Spaces.visibleSpaces.filter { screenSpaces.contains($0) }

        return Windows.list.filter { window in
            // basic filter: should show to user and not a windowless app
            guard !window.isWindowlessApp else { return false }

            // filter by screen
            guard window.screenId == screenUuid else { return false }

            // filter by space
            let spacesToShow = Preferences.taskbarSpacesToShow
            if spacesToShow == .visible {
                // only show windows on visible space for this screen
                guard visibleSpacesForScreen.contains(where: { visibleSpace in window.spaceIds.contains { $0 == visibleSpace } }) else { return false }
            }
            // .all shows windows from all spaces

            // filter minimized windows
            if Preferences.taskbarShowMinimizedWindows == .hide && window.isMinimized {
                return false
            }

            // filter hidden windows
            if Preferences.taskbarShowHiddenWindows == .hide && window.isHidden {
                return false
            }

            // filter fullscreen windows
            if Preferences.taskbarShowFullscreenWindows == .hide && window.isFullscreen {
                return false
            }

            return true
        }
    }

    func updateAppearance() {
        for (_, panel) in taskbarPanels {
            panel.updateAppearance()
        }
    }

    /// Adjusts all existing maximized windows to leave room for the taskbar
    /// Called when taskbar is enabled or taskbar height changes
    func adjustAllMaximizedWindows() {
        guard isEnabled else { return }
        for window in Windows.list {
            adjustWindowIfMaximized(window)
        }
    }

    /// Adjusts a window if it's maximized to leave room for the taskbar
    /// Called when a window is resized or moved
    func adjustWindowIfMaximized(_ window: Window) {
        guard isEnabled else { return }
        guard !window.isWindowlessApp else { return }
        guard !window.isFullscreen else { return } // don't adjust actual fullscreen windows
        guard let axUiElement = window.axUiElement else { return }
        guard let position = window.position, let size = window.size else { return }
        guard let screenId = window.screenId else { return }

        // find the screen for this window
        guard let screen = NSScreen.screens.first(where: { $0.uuid() == screenId }) else { return }

        let visibleFrame = screen.visibleFrame
        let taskbarHeight = Preferences.taskbarHeight

        // convert screen coordinates (origin at bottom-left) to window coordinates (origin at top-left)
        let screenTopLeftY = NSMaxY(NSScreen.screens[0].frame) - NSMaxY(visibleFrame)
        let expectedWindowY = screenTopLeftY
        let expectedWindowHeight = visibleFrame.height

        // check if window fills the visible frame (is "maximized")
        // allow small tolerance for rounding
        let tolerance: CGFloat = 2
        let isMaximizedWidth = abs(position.x - visibleFrame.minX) < tolerance && abs(size.width - visibleFrame.width) < tolerance
        let isMaximizedHeight = abs(position.y - expectedWindowY) < tolerance && abs(size.height - expectedWindowHeight) < tolerance

        // also check if window is already adjusted for taskbar (to avoid unnecessary operations)
        let adjustedHeight = expectedWindowHeight - taskbarHeight
        let isAlreadyAdjusted = abs(size.height - adjustedHeight) < tolerance

        if isMaximizedWidth && isMaximizedHeight && !isAlreadyAdjusted {
            // window is maximized - adjust to leave room for taskbar
            let newHeight = expectedWindowHeight - taskbarHeight
            let newY = expectedWindowY // keep top position the same

            // only adjust if the new size is different
            if abs(size.height - newHeight) > tolerance {
                BackgroundWork.accessibilityCommandsQueue.addOperation {
                    // set new size
                    var newSize = CGSize(width: size.width, height: newHeight)
                    if let sizeValue = AXValueCreate(.cgSize, &newSize) {
                        try? axUiElement.setAttribute(kAXSizeAttribute, sizeValue)
                    }

                    // set position (in case it shifted)
                    var newPosition = CGPoint(x: position.x, y: newY)
                    if let posValue = AXValueCreate(.cgPoint, &newPosition) {
                        try? axUiElement.setAttribute(kAXPositionAttribute, posValue)
                    }
                }
            }
        }
    }
}
