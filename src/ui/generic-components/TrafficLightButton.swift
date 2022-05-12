import Cocoa
import Foundation

class TrafficLightButton: NSButton {
    var isMouseOver = false
    var type: NSWindow.ButtonType!
    var window_: Window?

    init(_ type: NSWindow.ButtonType, _ size: CGFloat) {
        super.init(frame: .init(origin: .zero, size: .init(width: size, height: size)))
        self.type = type
        target = self
        action = #selector(onClick)
        fit(size, size)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    @objc func onClick() {
        if (type == .zoomButton) {
            window_?.toggleFullscreen()
        } else if (type == .miniaturizeButton) {
            window_?.minDemin()
        } else if (type == .closeButton) {
            window_?.close()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        isMouseOver = true
        setNeedsDisplay()
    }

    override func mouseExited(with event: NSEvent) {
        isMouseOver = false
        setNeedsDisplay()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.saveGraphicsState()
        let (backgroundGradient, lineColor, strokeColor) = colors()
        var disk = drawDisk(backgroundGradient, strokeColor)
        drawSymbol(lineColor)
        drawDimming(disk)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func colors() -> (NSGradient, NSColor, NSColor) {
        if NSColor.currentControlTint == .graphiteControlTint {
            return (
                NSGradient(starting: NSColor(red: 0.57, green: 0.57, blue: 0.60, alpha: 1),
                    ending: NSColor(red: 0.56, green: 0.55, blue: 0.57, alpha: 1))!,
                type == .zoomButton ?
                    NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1)
                    : type == .miniaturizeButton ?
                    NSColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1)
                    :
                    NSColor(red: 0.19, green: 0.18, blue: 0.20, alpha: 1),
                NSColor(red: 0.51, green: 0.51, blue: 0.53, alpha: 1)
            )
        }
        if type == .zoomButton {
            return (
                NSGradient(starting: NSColor(red: 0.153, green: 0.788, blue: 0.247, alpha: 1),
                    ending: NSColor(red: 0.153, green: 0.816, blue: 0.255, alpha: 1))!,
                NSColor(red: 0.004, green: 0.392, blue: 0, alpha: 1),
                NSColor(red: 0.180, green: 0.690, blue: 0.235, alpha: 1)
            )
        }
        if type == .miniaturizeButton {
            return (
                NSGradient(starting: NSColor(red: 1, green: 0.741, blue: 0.180, alpha: 1),
                    ending: NSColor(red: 1, green: 0.773, blue: 0.184, alpha: 1))!,
                NSColor(red: 0.600, green: 0.345, blue: 0.004, alpha: 1),
                NSColor(red: 0.875, green: 0.616, blue: 0.094, alpha: 1)
            )
        }
        return (
            NSGradient(starting: NSColor(red: 1, green: 0.373, blue: 0.337, alpha: 1),
                ending: NSColor(red: 1, green: 0.388, blue: 0.357, alpha: 1))!,
            NSColor(red: 0.302, green: 0, blue: 0, alpha: 1),
            NSColor(red: 0.886, green: 0.243, blue: 0.216, alpha: 1)
        )
    }

    private func drawDimming(_ disk: NSBezierPath) {
        disk.lineWidth = 1
        if (isHighlighted) {
            NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.5).setFill()
            disk.fill()
        } else if (isMouseOver) {
            NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.25).setFill()
            disk.fill()
        }
    }

    private func drawDisk(_ backgroundGradient: NSGradient, _ strokeColor: NSColor) -> NSBezierPath {
        var disk = NSBezierPath()
        disk.appendOval(in: NSMakeRect(bounds.origin.x + 0.5, bounds.origin.y + 0.5, bounds.width - 1, bounds.height - 1))
        backgroundGradient.draw(in: disk, relativeCenterPosition: .zero)
        strokeColor.setStroke()
        disk.lineWidth = 0.5
        disk.stroke()
        return disk
    }

    private func drawSymbol(_ lineColor: NSColor) {
        if (type == NSWindow.ButtonType.zoomButton) {
            var symbol = NSBezierPath()
            symbol.move(to: NSMakePoint(bounds.width * 0.25, bounds.height * 0.75))
            symbol.line(to: NSMakePoint(bounds.width * 0.25, bounds.height * 1 / 3))
            symbol.line(to: NSMakePoint(bounds.width * 2 / 3, bounds.height * 0.75))
            symbol.close()
            lineColor.setFill()
            symbol.fill()
            symbol.move(to: NSMakePoint(bounds.width * 0.75, bounds.height * 0.25))
            symbol.line(to: NSMakePoint(bounds.width * 0.75, bounds.height * 2 / 3))
            symbol.line(to: NSMakePoint(bounds.width * 1 / 3, bounds.height * 0.25))
            symbol.close()
            lineColor.setFill()
            symbol.fill()
            // maximize cross
            // NSGraphicsContext.current?.shouldAntialias = false
            // var symbol = NSBezierPath()
            // symbol.move(to: NSMakePoint(bounds.width / 2, bounds.height * 0.20))
            // symbol.line(to: NSMakePoint(bounds.width / 2, bounds.height * 0.80))
            // symbol.move(to: NSMakePoint(bounds.width * 0.80, bounds.height / 2))
            // symbol.line(to: NSMakePoint(bounds.width * 0.20, bounds.height / 2))
            // symbol.lineWidth = 0.75
            // NSGraphicsContext.current?.shouldAntialias = true
        } else if (type == NSWindow.ButtonType.miniaturizeButton) {
            NSGraphicsContext.current?.shouldAntialias = false
            var symbol = NSBezierPath()
            symbol.move(to: NSMakePoint(bounds.width * 0.80, bounds.height / 2))
            symbol.line(to: NSMakePoint(bounds.width * 0.20, bounds.height / 2))
            symbol.lineWidth = 0.75
            lineColor.setStroke()
            symbol.stroke()
            NSGraphicsContext.current?.shouldAntialias = true
        } else if (type == NSWindow.ButtonType.closeButton) {
            var symbol = NSBezierPath()
            symbol.move(to: NSMakePoint(bounds.width * 0.30, bounds.height * 0.30))
            symbol.line(to: NSMakePoint(bounds.width * 0.70, bounds.height * 0.70))
            symbol.move(to: NSMakePoint(bounds.width * 0.70, bounds.height * 0.30))
            symbol.line(to: NSMakePoint(bounds.width * 0.30, bounds.height * 0.70))
            symbol.lineWidth = 1
            lineColor.setStroke()
            symbol.stroke()
        }
    }
}



// experiment: use actual buttons from OS through standardWindowButton
// issues:
//   * zoom button has a popover that can't be removed
//   * overall they look/act depending on the parent window
//     e.g. need to set `window.collectionBehavior = .fullScreenPrimary` to get fullscreen button

//class TrafficLightButton: NSView {
//    convenience init(_ nameTest: NSWindow.ButtonType) {
//        self.init(frame: .zero)
//        let button = NSWindow.standardWindowButton(nameTest, for: [.miniaturizable, .closable, .nonactivatingPanel])!
//        button.action = nil
//        addSubview(button)
//        fit(button.frame.size.width, button.frame.size.height)
//    }
//
//    /// force the hovered state as if the mouse was on the traffic lights area
//    /// see https://stackoverflow.com/a/30417372/2249756
//    @objc func _mouseInGroup(_: Any) -> Bool {
//        return true
//    }
//
//    override func updateTrackingAreas() {
//        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
//    }
//
//    override func mouseEntered(with event: NSEvent) {
//    }
//
//    override func mouseExited(with event: NSEvent) {
//    }
//}
