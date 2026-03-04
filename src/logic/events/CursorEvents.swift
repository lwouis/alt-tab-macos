import Cocoa
import Carbon.HIToolbox.Events

class CursorEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!
    private static var mouseDownTarget: AnyObject?
    private static var mouseDownInsideSearchField = false
    static var deadZoneInitialPosition: CGPoint?
    static var isAllowedToMouseHover = true

    static func observe() {
        observe_()
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if !enabled {
            deadZoneInitialPosition = nil
        }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    private static func observe_() {
        let eventMask = [CGEventType.leftMouseDown, CGEventType.leftMouseUp, CGEventType.otherMouseUp, CGEventType.mouseMoved].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
        // CGEvent.tapCreate returns nil if ensureAccessibilityCheckboxIsChecked() didn't pass
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: handleEvent,
            userInfo: nil)
        if let eventTap {
            toggle(false)
            let runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
            // we run on main-thread directly since all we do is check NSEvent and UI coordinates, which we must do on main-thread
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        } else {
            App.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
            case .leftMouseDown: return handleLeftMouseDown(cgEvent)
            case .leftMouseUp: return handleLeftMouseUp(cgEvent)
            case .otherMouseUp: return handleOtherMouseUp(cgEvent)
            case .mouseMoved: return handleMouseMoved(cgEvent)
            case .tapDisabledByUserInput, .tapDisabledByTimeout:
                if shouldBeEnabled { CGEvent.tapEnable(tap: eventTap!, enable: true) }
                return Unmanaged.passUnretained(cgEvent)
            default: return Unmanaged.passUnretained(cgEvent)
        }
    }

    private static func handleLeftMouseDown(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if isPointerInsideSearchField() {
            mouseDownInsideSearchField = true
            return Unmanaged.passUnretained(cgEvent)
        }
        mouseDownInsideSearchField = false
        guard isPointerInsideUi() else { return nil }
        mouseDownTarget = (findButtonUnderPointer() ?? findTileViewUnderPointer()) as AnyObject?
        return nil
    }

    private static func handleLeftMouseUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if mouseDownInsideSearchField || isPointerInsideSearchField() {
            mouseDownInsideSearchField = false
            return Unmanaged.passUnretained(cgEvent)
        }
        guard isPointerInsideUi() else {
            if mouseDownTarget == nil { App.hideUi() }
            mouseDownTarget = nil
            return nil
        }
        let downTarget = mouseDownTarget
        mouseDownTarget = nil
        if let button = findButtonUnderPointer(), button === downTarget {
            button.onClick()
            return nil
        }
        if let target = findTileViewUnderPointer(), target === downTarget {
            target.mouseUpCallback()
            return nil
        }
        return nil
    }

    private static func handleOtherMouseUp(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        guard isPointerInsideUi(),
              cgEvent.getIntegerValueField(.mouseEventButtonNumber) == 2,
              let target = findTileViewUnderPointer(),
              let window = target.window_ else {
            return Unmanaged.passUnretained(cgEvent)
        }
        window.isWindowlessApp ? window.application.quit() : window.close()
        return nil
    }

    private static func handleMouseMoved(_ cgEvent: CGEvent) -> Unmanaged<CGEvent>? {
        if isAllowedToReactToPointerMovement(cgEvent.location) {
            TilesView.thumbnailOverView.updateHover()
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    static func isAllowedToReactToPointerMovement(_ location: CGPoint) -> Bool {
        updateDeadzoneSituation(location)
        return isAllowedToMouseHover
    }

    private static func pointerLocationInWindow() -> NSPoint {
        TilesPanel.shared.mouseLocationOutsideOfEventStream
    }

    private static func isPointerInsideUi() -> Bool {
        TilesPanel.shared.contentLayoutRect.contains(pointerLocationInWindow())
    }

    private static func isPointerInsideSearchField() -> Bool {
        let searchField = TilesView.searchField
        if searchField.isHidden { return false }
        let point = searchField.convert(pointerLocationInWindow(), from: nil)
        return searchField.bounds.contains(point)
    }

    private static func pointerInOverlay() -> (TileOverView, NSPoint) {
        let overlay = TilesView.thumbnailOverView
        return (overlay, overlay.convert(pointerLocationInWindow(), from: nil))
    }

    private static func findButtonUnderPointer() -> TrafficLightButton? {
        let (overlay, point) = pointerInOverlay()
        return overlay.findButton(point)
    }

    private static func findTileViewUnderPointer() -> TileView? {
        let (overlay, point) = pointerInOverlay()
        return overlay.findTarget(point)
    }

    /// when using the trackpad, the user may swipe with a slight mistake. This will create a small cursor movement
    /// we ignore those, as they are not intended. Intended movements will be larger and not ignored
    private static func updateDeadzoneSituation(_ location: CGPoint) {
        guard let deadZoneInitialPosition else {
            deadZoneInitialPosition = location
            isAllowedToMouseHover = false
            return
        }
        let deltaX = location.x - deadZoneInitialPosition.x
        let deltaY = location.y - deadZoneInitialPosition.y
        if hypot(deltaX, deltaY) > 25 { isAllowedToMouseHover = true }
    }
}
