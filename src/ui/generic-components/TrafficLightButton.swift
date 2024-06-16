import Cocoa
import Foundation

/// Enumeration for the different types of traffic light buttons.
enum TrafficLightButtonType {
    case quit
    case close
    case miniaturize
    case fullscreen
}

/// A custom button class representing traffic light buttons in a macOS window
class TrafficLightButton: NSView {
    // Tracks whether the mouse is hovering over the button
    var isMouseOver = false
    // The type of traffic light button (quit, close, miniaturize, fullscreen)
    var type: TrafficLightButtonType!
    // Reference to the window that contains this button
    var targetWindow: Window?

    /// Custom initializer for the button.
    ///
    /// - Parameters:
    ///   - type: The type of the traffic light button.
    ///   - tooltip: The tooltip text to display when the user hovers over the button.
    ///   - size: The size (both width and height) of the button.
    init(_ type: TrafficLightButtonType, _ tooltip: String, _ size: CGFloat) {
        super.init(frame: .init(origin: .zero, size: .init(width: size, height: size)))
        self.type = type

        // Adjust the button size to fit the specified dimensions
        fit(size, size)
        // Add a tracking area to detect mouse enter and exit events
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
        toolTip = tooltip
        wantsLayer = true
    }

    /// Required initializer for decoding the button (not used here)
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Mouse entered event handler
    override func mouseEntered(with event: NSEvent) {
        isMouseOver = true
        setNeedsDisplay(bounds)
    }

    /// Mouse exited event handler
    override func mouseExited(with event: NSEvent) {
        isMouseOver = false
        setNeedsDisplay(bounds)
    }

    /// Mouse up event handler
    override func mouseUp(with event: NSEvent) {
        performClick()
    }

    /// Perform the button click action
    private func performClick() {
        if let window = targetWindow, let type = type {
            switch type {
            case .fullscreen:
                window.toggleFullscreen()
            case .miniaturize:
                window.minDemin()
            case .close:
                window.close()
            case .quit:
                window.application.quit()
            }
        }
    }

    /// Custom drawing of the button.
    ///
    /// - Parameters:
    ///   - dirtyRect: The portion of the view’s bounds that needs to be redrawn.
    override func draw(_ dirtyRect: NSRect) {
        // Retrieve the colors for the button based on its type and system control tint
        let (diskBackgroundColor, diskStrokeColor, symbolColor) = colors()

        let disk = NSBezierPath()
        disk.appendOval(in: NSMakeRect(bounds.origin.x + 0.5, bounds.origin.y + 0.5, bounds.width - 1, bounds.height - 1))

        // Fill the disk with the black background color
        NSColor.black.setFill()
        disk.fill()

        // Fill the disk with the background color
        diskBackgroundColor.draw(in: disk, relativeCenterPosition: .zero)
        // Draw the gradient within the disk
        drawDisk(diskBackgroundColor, diskStrokeColor)
        // Draw the symbol on the button
        drawSymbol(symbolColor)
        // Draw a dimming effect if the button is highlighted or hovered
        drawDimming(disk)
    }

    /// Draws a dimming effect on the button when it's highlighted or hovered.
    ///
    /// - Parameters:
    ///   - disk: The `NSBezierPath` representing the button's disk.
    private func drawDimming(_ disk: NSBezierPath) {
        // Set the line width of the disk
        disk.lineWidth = 1
        if isMouseOver {
            // Set the fill color to black with 25% opacity
            NSColor.black.withAlphaComponent(0.25).setFill()
            // Fill the disk with the dimming color
            disk.fill()
        }
    }

    /// Draws the disk background and stroke for the button.
    ///
    /// - Parameters:
    ///   - backgroundGradient: The gradient background color to fill the disk.
    ///   - strokeColor: The color to use for the disk's stroke.
    /// - Returns: The `NSBezierPath` representing the drawn disk.
    private func drawDisk(_ backgroundGradient: NSGradient, _ strokeColor: NSColor) -> NSBezierPath {
        let disk = NSBezierPath()
        // Append an oval shape to the bezier path within the specified bounds
        // Slightly offset inward and reduced in size to ensure proper border positioning within the view.
        disk.appendOval(in: NSMakeRect(bounds.origin.x + 0.5, bounds.origin.y + 0.5, bounds.width - 1, bounds.height - 1))
        // Draw the gradient within the disk, centered at the relative center position
        backgroundGradient.draw(in: disk, relativeCenterPosition: .zero)
        // Set the stroke color for the disk
        strokeColor.setStroke()
        // Set the stroke width
        disk.lineWidth = 0.5
        // Stroke the disk path
        disk.stroke()
        return disk
    }

    /// Determines the colors for the button based on its type and the system control tint.
    ///
    /// - Returns: A tuple containing three elements:
    ///   - NSGradient: The gradient background color
    ///   - NSColor: The stroke color
    ///   - NSColor: The symbol color
    private func colors() -> (NSGradient, NSColor, NSColor) {
        if NSColor.currentControlTint == .graphiteControlTint {
            return (
                // Gray gradient
                NSGradient(starting: NSColor(red: 0.57, green: 0.57, blue: 0.60, alpha: 1),
                    ending: NSColor(red: 0.56, green: 0.55, blue: 0.57, alpha: 1))!,
                // Dark Gray
                NSColor(red: 0.51, green: 0.51, blue: 0.53, alpha: 1),
                type == .fullscreen ?
                    // Very Dark Gray
                    NSColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1) :
                    type == .miniaturize ?
                    // Medium Gray
                    NSColor(red: 0.35, green: 0.35, blue: 0.37, alpha: 1) :
                    // Dark Gray
                    NSColor(red: 0.19, green: 0.18, blue: 0.20, alpha: 1)
            )
        }
        if type == .fullscreen {
            return (
                // Green gradient
                NSGradient(starting: NSColor(red: 0.153, green: 0.788, blue: 0.247, alpha: 1),
                    ending: NSColor(red: 0.153, green: 0.816, blue: 0.255, alpha: 1))!,
                // Lighter Green
                NSColor(red: 0.180, green: 0.690, blue: 0.235, alpha: 1),
                // Dark Green
                NSColor(red: 0.004, green: 0.392, blue: 0, alpha: 1)
            )
        }
        if type == .miniaturize {
            return (
                // Yellow gradient
                NSGradient(starting: NSColor(red: 1, green: 0.741, blue: 0.180, alpha: 1),
                    ending: NSColor(red: 1, green: 0.773, blue: 0.184, alpha: 1))!,
                // Golden Yellow
                NSColor(red: 0.875, green: 0.616, blue: 0.094, alpha: 1),
                // Dark Brown
                NSColor(red: 0.600, green: 0.345, blue: 0.004, alpha: 1)
            )
        }
        if type == .close {
            return (
                // Red gradient
                NSGradient(starting: NSColor(red: 1, green: 0.373, blue: 0.337, alpha: 1),
                    ending: NSColor(red: 1, green: 0.388, blue: 0.357, alpha: 1))!,
                // Light Red
                NSColor(red: 0.886, green: 0.243, blue: 0.216, alpha: 1),
                // Dark Red
                NSColor(red: 0.302, green: 0, blue: 0, alpha: 1)
            )
        }
        return (
            // Purple gradient
            NSGradient(starting: NSColor(red: 0.74, green: 0.32, blue: 1, alpha: 1),
                ending: NSColor(red: 0.77, green: 0.35, blue: 1, alpha: 1))!,
            // Dark Purple
            NSColor(red: 0.62, green: 0.23, blue: 0.88, alpha: 1),
            // Very Dark Purple
            NSColor(red: 0.25, green: 0, blue: 0.4, alpha: 1)
        )
    }

    /// Draws the symbol on the button based on its type.
    ///
    /// - Parameters
    ///   - lineColor: The color to use for the symbol.
    private func drawSymbol(_ lineColor: NSColor) {
        let symbol = NSBezierPath()

        // Rotate the context
        let rotationTransform = NSAffineTransform()
        rotationTransform.translateX(by: bounds.midX, yBy: bounds.midY)
        rotationTransform.rotate(byDegrees: 180)
        rotationTransform.translateX(by: -bounds.midX, yBy: -bounds.midY)
        rotationTransform.concat()

        if type == .fullscreen {
            // Draw fullscreen symbol
            // Draw first triangle
            symbol.move(to: NSMakePoint(bounds.width * 0.25, bounds.height * 0.75))
            symbol.line(to: NSMakePoint(bounds.width * 0.25, bounds.height * 1 / 3))
            symbol.line(to: NSMakePoint(bounds.width * 2 / 3, bounds.height * 0.75))
            symbol.close()
            lineColor.setFill()
            symbol.fill()

            // Draw second triangle
            symbol.move(to: NSMakePoint(bounds.width * 0.75, bounds.height * 0.25))
            symbol.line(to: NSMakePoint(bounds.width * 0.75, bounds.height * 2 / 3))
            symbol.line(to: NSMakePoint(bounds.width * 1 / 3, bounds.height * 0.25))
            symbol.close()
            lineColor.setFill()
            symbol.fill()
        } else if type == .miniaturize {
            // Draw miniaturize symbol (horizontal line)
            NSGraphicsContext.current?.shouldAntialias = false
            symbol.move(to: NSMakePoint(bounds.width * 0.20, bounds.height / 2))
            symbol.line(to: NSMakePoint(bounds.width * 0.80, bounds.height / 2))
            symbol.lineWidth = 0.75
            lineColor.setStroke()
            symbol.stroke()
            NSGraphicsContext.current?.shouldAntialias = true
        } else if type == .close {
            // Draw close symbol (cross)
            symbol.move(to: NSMakePoint(bounds.width * 0.30, bounds.height * 0.30))
            symbol.line(to: NSMakePoint(bounds.width * 0.70, bounds.height * 0.70))
            symbol.move(to: NSMakePoint(bounds.width * 0.70, bounds.height * 0.30))
            symbol.line(to: NSMakePoint(bounds.width * 0.30, bounds.height * 0.70))
            symbol.lineWidth = 1
            lineColor.setStroke()
            symbol.stroke()
        } else if type == .quit {
            // Draw quit symbol (arc with a line)
            let mouthAngle = CGFloat(80) / 2

            // Draw arc
            symbol.appendArc(
                withCenter: NSMakePoint(bounds.width / 2, bounds.height / 2),
                radius: bounds.width * 0.27,
                startAngle: 180 + 90 + mouthAngle,
                endAngle: 180 + 360 + 90 - mouthAngle
            )
            symbol.lineWidth = 0.75
            lineColor.setStroke()
            symbol.stroke()

            // Draw vertical line
            symbol.move(to: NSMakePoint(bounds.width / 2, bounds.height * 0.15))
            symbol.line(to: NSMakePoint(bounds.width / 2, bounds.height * 0.50))
            symbol.lineWidth = 1.2
            symbol.stroke()
        }
    }
}