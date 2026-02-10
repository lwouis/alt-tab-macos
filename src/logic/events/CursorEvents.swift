import Cocoa
import Carbon.HIToolbox.Events

class CursorEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!
    private static var mouseDownTileView: TileView?
    private static var mouseDownButton: TrafficLightButton?
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
            App.app.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        switch type {
            case .leftMouseDown: return handleLeftMouseDown()
            case .leftMouseUp where cgEvent.getIntegerValueField(.mouseEventClickState) >= 1: return handleLeftMouseUp()
            case .otherMouseUp: return handleOtherMouseUp(cgEvent)
            case .mouseMoved: return handleMouseMoved(cgEvent)
            case .tapDisabledByUserInput, .tapDisabledByTimeout:
                if shouldBeEnabled { CGEvent.tapEnable(tap: eventTap!, enable: true) }
                return Unmanaged.passUnretained(cgEvent)
            default: return Unmanaged.passUnretained(cgEvent)
        }
    }

    private static func handleLeftMouseDown() -> Unmanaged<CGEvent>? {
        guard isPointerInsideUi() else { return nil }
        if let button = findButtonUnderPointer() {
            mouseDownButton = button
            button.isHighlighted = true
            button.setNeedsDisplay()
        } else {
            mouseDownTileView = findTileViewUnderPointer()
        }
        return nil
    }

    private static func handleLeftMouseUp() -> Unmanaged<CGEvent>? {
        guard isPointerInsideUi() else {
            App.app.hideUi()
            return nil
        }
        if let button = mouseDownButton {
            mouseDownButton = nil
            button.isHighlighted = false
            button.setNeedsDisplay()
            if findButtonUnderPointer() === button {
                button.onClick()
            }
            return nil
        }
        if let target = mouseDownTileView {
            mouseDownTileView = nil
            if isPointerOver(target) {
                target.mouseUpCallback()
            }
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
        updateDeadzoneSituation(cgEvent)
        if isAllowedToMouseHover {
            App.app.thumbnailsPanel.tilesView.thumbnailOverView.updateHover()
        }
        return Unmanaged.passUnretained(cgEvent)
    }

    private static func pointerLocationInWindow() -> NSPoint {
        App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream
    }

    private static func isPointerInsideUi() -> Bool {
        App.app.thumbnailsPanel.contentLayoutRect.contains(pointerLocationInWindow())
    }

    private static func isPointerOver(_ view: NSView) -> Bool {
        view.bounds.contains(view.convert(pointerLocationInWindow(), from: nil))
    }

    private static func pointerInOverlay() -> (TileOverView, NSPoint) {
        let overlay = App.app.thumbnailsPanel.tilesView.thumbnailOverView
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
    private static func updateDeadzoneSituation(_ cgEvent: CGEvent) {
        guard let event = cgEvent.toNSEvent() else { return }
        guard let deadZoneInitialPosition else {
            deadZoneInitialPosition = event.locationInWindow
            isAllowedToMouseHover = false
            return
        }
        let deltaX = event.locationInWindow.x - deadZoneInitialPosition.x
        let deltaY = event.locationInWindow.y - deadZoneInitialPosition.y
        isAllowedToMouseHover = hypot(deltaX, deltaY) > 25
    }
}
