import Cocoa
import Carbon.HIToolbox.Events

class MouseEvents {
    private static var eventTap: CFMachPort!
    private static var shouldBeEnabled: Bool!
    private static var mouseDownTileView: TileView?
    private static var mouseDownButton: TrafficLightButton?

    static func observe() {
        observe_()
    }

    static func toggle(_ enabled: Bool) {
        guard enabled != shouldBeEnabled else { return }
        shouldBeEnabled = enabled
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: enabled)
        }
    }

    private static func observe_() {
        let eventMask = [CGEventType.leftMouseDown, CGEventType.leftMouseUp, CGEventType.otherMouseUp].reduce(CGEventMask(0), { $0 | (1 << $1.rawValue) })
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
            // we run on main-thread directly since all we do is check UI coordinates, which we must do on main-thread
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        } else {
            App.app.restart()
        }
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, cgEvent, _ in
        if type == .leftMouseDown {
            if !isPointerInsideUi() {
                return nil // focused app won't receive the event
            }
            if let button = findButtonUnderPointer() {
                mouseDownButton = button
                button.isHighlighted = true
                button.setNeedsDisplay()
                return nil // swallow - we handle button clicks centrally
            }
            mouseDownTileView = findTileViewUnderPointer()
            return nil // swallow - we handle tile clicks centrally
        } else if type == .leftMouseUp && cgEvent.getIntegerValueField(.mouseEventClickState) >= 1 {
            if !isPointerInsideUi() {
                App.app.hideUi()
                return nil // focused app won't receive the event
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
                if isPointerOverTileView(target) {
                    target.mouseUpCallback()
                }
                return nil
            }
        } else if type == .otherMouseUp {
            guard isPointerInsideUi() else { return Unmanaged.passUnretained(cgEvent) }
            if cgEvent.getIntegerValueField(.mouseEventButtonNumber) == 2 {
                handleMiddleClick()
                return nil
            }
        } else if (type == .tapDisabledByUserInput || type == .tapDisabledByTimeout) && shouldBeEnabled {
            CGEvent.tapEnable(tap: eventTap!, enable: true)
        }
        return Unmanaged.passUnretained(cgEvent) // focused app will receive the event
    }

    private static func isPointerInsideUi() -> Bool {
        return App.app.thumbnailsPanel.contentLayoutRect.contains(App.app.thumbnailsPanel.mouseLocationOutsideOfEventStream)
    }

    private static func findButtonUnderPointer() -> TrafficLightButton? {
        let panel = App.app.thumbnailsPanel!
        let overlay = panel.tilesView.thumbnailOverView
        let windowLocation = panel.mouseLocationOutsideOfEventStream
        let overlayLocation = overlay.convert(windowLocation, from: nil)
        return overlay.findButton(overlayLocation)
    }

    private static func findTileViewUnderPointer() -> TileView? {
        let panel = App.app.thumbnailsPanel!
        let overlay = panel.tilesView.thumbnailOverView
        let windowLocation = panel.mouseLocationOutsideOfEventStream
        let overlayLocation = overlay.convert(windowLocation, from: nil)
        return overlay.findTarget(overlayLocation)
    }

    private static func isPointerOverTileView(_ tileView: TileView) -> Bool {
        let panel = App.app.thumbnailsPanel!
        let windowLocation = panel.mouseLocationOutsideOfEventStream
        let localPoint = tileView.convert(windowLocation, from: nil)
        return tileView.bounds.contains(localPoint)
    }

    private static func handleMiddleClick() {
        guard let target = findTileViewUnderPointer(), let window = target.window_ else { return }
        if window.isWindowlessApp {
            window.application.quit()
        } else {
            window.close()
        }
    }
}
