import Cocoa

class ForwardingVerticalScrollView: NSScrollView {
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        axis == .vertical
    }

    override func scrollWheel(with event: NSEvent) {
        guard isVerticalScroll(event) else {
            super.scrollWheel(with: event)
            return
        }
        let bounds = contentView.bounds
        let y = bounds.origin.y
        // Ask AppKit for the actual valid scroll range (accounts for headers, insets, etc.)
        let minY = contentView.constrainBoundsRect(NSRect(x: bounds.origin.x, y: -1e9, width: bounds.width, height: bounds.height)).origin.y
        let maxY = contentView.constrainBoundsRect(NSRect(x: bounds.origin.x, y: 1e9, width: bounds.width, height: bounds.height)).origin.y
        let canScrollUp = y > minY + 0.5
        let canScrollDown = y < maxY - 0.5
        // scrollingDeltaY > 0 → scroll up (y decreases); < 0 → scroll down (y increases)
        let wantsUp = event.scrollingDeltaY > 0
        let wantsDown = event.scrollingDeltaY < 0
        let shouldForward = (wantsUp && !canScrollUp) || (wantsDown && !canScrollDown)
        if shouldForward {
            parentScrollView()?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }

    private func isVerticalScroll(_ event: NSEvent) -> Bool {
        abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) && abs(event.scrollingDeltaY) > 0.1
    }

    private func parentScrollView() -> NSScrollView? {
        var parent = superview
        while let view = parent {
            if let scrollView = view as? NSScrollView { return scrollView }
            parent = view.superview
        }
        return nil
    }
}

class ForwardingVerticalDocumentView: FlippedView {
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        axis == .vertical
    }
}
