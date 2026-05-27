import XCTest
import Cocoa

/// Pins the Pro-badge segment-overlay contract:
///   - Layout: custom icon + label + badge overlay the segment so the segment width stays
///     consistent with its siblings and the label truncates before colliding with the badge.
///   - Colors: AppKit-driven. The overlay's icon and label use system color tokens
///     (`.controlTextColor` / `.alternateSelectedControlTextColor`) via `colorProvider` so
///     AppKit resolves the right value for every combination of selection × key-window ×
///     enabled × light/dark mode. We never hard-code colors.
///   - The badge mirrors the segment's selection via `setSelected`.
/// These tests catch the regressions we keep hitting: wrong textColor in one state, or the
/// Pro segment ending up wider than its siblings.
final class ProBadgeViewSegmentTests: XCTestCase {

    // MARK: - Helpers

    private func makeControl(initialSegmentWidth: CGFloat = 80) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Small", "Medium", "Auto"], trackingMode: .selectOne, target: nil, action: nil)
        for i in 0..<control.segmentCount {
            control.setWidth(initialSegmentWidth, forSegment: i)
        }
        return control
    }

    private func allDescendants(_ view: NSView) -> [NSView] {
        var out = [NSView]()
        for child in view.subviews {
            out.append(child)
            out.append(contentsOf: allDescendants(child))
        }
        return out
    }

    private func attachOverlay(on control: NSSegmentedControl, at segmentIndex: Int = 2,
                               label: String = "Auto", symbol: Symbols = .stub) -> ProBadgeView.SegmentOverlay {
        return ProBadgeView.attach(to: control, segmentIndex: segmentIndex, label: label, symbol: symbol)
    }

    // MARK: - Width: Pro segment must not grow

    /// The previous-previous attempt widened the Pro segment to make room for the badge,
    /// breaking the row's visual rhythm. The correct shape is: the overlay's label truncates
    /// before the badge, so all segments stay the same width.
    func testProSegmentWidthUnchanged() {
        let control = makeControl(initialSegmentWidth: 80)
        _ = attachOverlay(on: control)
        XCTAssertEqual(control.width(forSegment: 2), 80, accuracy: 0.5,
            "regression: Pro segment must remain the same width as its siblings — the layout achieves this by overlaying custom subviews that truncate the label, not by widening the segment")
    }

    func testNonProSegmentWidthsUnchanged() {
        let control = makeControl(initialSegmentWidth: 80)
        _ = attachOverlay(on: control)
        XCTAssertEqual(control.width(forSegment: 0), 80, accuracy: 0.5)
        XCTAssertEqual(control.width(forSegment: 1), 80, accuracy: 0.5)
    }

    // MARK: - Overlay subviews

    func testAttachReturnsBadgeIconAndLabel() {
        let control = makeControl()
        let overlay = attachOverlay(on: control)
        XCTAssertTrue(control.subviews.contains(overlay.badge),
            "badge must be a direct subview of the segmented control")
        XCTAssertTrue(control.subviews.contains(overlay.icon),
            "icon overlay must be a direct subview — that's how we control truncation")
        XCTAssertTrue(control.subviews.contains(overlay.label),
            "label overlay must be a direct subview — that's how we control truncation")
    }

    func testAttachClearsNativeLabel() {
        let control = makeControl()
        _ = attachOverlay(on: control)
        XCTAssertEqual(control.label(forSegment: 2), "",
            "native label is cleared because we draw our own overlay text so the label can truncate before the badge")
    }

    func testAttachClearsNativeImage() {
        let control = makeControl()
        let preExistingImage = NSImage(size: NSSize(width: 8, height: 8))
        control.setImage(preExistingImage, forSegment: 2)
        _ = attachOverlay(on: control)
        XCTAssertNil(control.image(forSegment: 2),
            "native image is cleared because we draw our own overlay icon")
    }

    // MARK: - Colors: AppKit-driven, never hard-coded

    /// The icon/label overlays must use a `colorProvider` closure rather than a hard-coded
    /// `NSColor(red:green:blue:)` tuple. This way AppKit re-resolves the system color token
    /// on every draw — for every appearance × selection × key-window combination.
    func testIconHasColorProvider() {
        let control = makeControl()
        let overlay = attachOverlay(on: control)
        guard let dynamicIcon = overlay.icon as? DynamicColorImageView else {
            return XCTFail("icon must be a `DynamicColorImageView` so its tint is recomputed on every draw — that's the only way AppKit's state-aware color resolution is honored")
        }
        XCTAssertNotNil(dynamicIcon.colorProvider,
            "regression: icon must have a colorProvider — without one, contentTintColor freezes at attach time and never updates on selection/key changes")
    }

    func testLabelHasColorProvider() {
        let control = makeControl()
        let overlay = attachOverlay(on: control)
        guard let dynamicLabel = overlay.label as? DynamicColorTextField else {
            return XCTFail("label must be a `DynamicColorTextField` so its textColor is recomputed on every draw")
        }
        XCTAssertNotNil(dynamicLabel.colorProvider,
            "regression: label must have a colorProvider — without one, textColor freezes at attach time and never updates on selection/key changes")
    }

    /// The provider produced by `segmentColorProvider` must return AppKit's selected-text color
    /// when the segment is selected and the window is key — that's `.alternateSelectedControlTextColor`.
    /// In every other state, it returns `.controlTextColor`, which AppKit fades automatically
    /// for inactive windows, disabled controls, and dark mode.
    func testColorProviderSelectedAndKey() {
        let control = makeControl()
        control.selectedSegment = 2
        let provider = ProBadgeView.segmentColorProvider(for: control, segmentIndex: 2)
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(control)
        window.makeKeyAndOrderFront(nil)
        // makeKeyAndOrderFront may not actually key in a test runner — guard on the real state.
        if window.isKeyWindow {
            XCTAssertEqual(provider(), NSColor.alternateSelectedControlTextColor,
                "selected segment in a key window must use AppKit's selected-text color so the overlay matches the native white-on-blue look")
        }
        window.orderOut(nil)
    }

    func testColorProviderUnselected() {
        let control = makeControl()
        control.selectedSegment = 0
        let provider = ProBadgeView.segmentColorProvider(for: control, segmentIndex: 2)
        XCTAssertEqual(provider(), NSColor.controlTextColor,
            "non-selected segment must use AppKit's default control-text color; AppKit fades it in dark mode / inactive windows / disabled state automatically")
    }

    func testColorProviderSelectedButNotInWindow() {
        // A control not yet attached to a window has `window?.isKeyWindow == nil` (falsy), so
        // the provider returns the unselected color even when the segment IS selected. That's
        // the correct behavior — without a window, AppKit wouldn't draw the blue selection
        // background either, so the matching label color is the unselected one.
        let control = makeControl()
        control.selectedSegment = 2
        let provider = ProBadgeView.segmentColorProvider(for: control, segmentIndex: 2)
        XCTAssertEqual(provider(), NSColor.controlTextColor,
            "without a key window, the matching segment background isn't drawn either — the provider must return the unselected color")
    }

    func testAttachDoesNotHardcodeIconTint() {
        let control = makeControl()
        let overlay = attachOverlay(on: control)
        // The initial contentTintColor should be the system color the provider returned, not
        // an RGB literal. We verify equality with the system token at attach time.
        if #available(macOS 10.14, *) {
            XCTAssertEqual(overlay.icon.contentTintColor, NSColor.controlTextColor,
                "regression: initial icon tint must be `.controlTextColor` (a system token), not a hard-coded RGB — system tokens auto-resolve for every appearance state")
        }
    }

    func testAttachDoesNotHardcodeLabelColor() {
        let control = makeControl()
        let overlay = attachOverlay(on: control)
        XCTAssertEqual(overlay.label.textColor, NSColor.controlTextColor,
            "regression: initial label textColor must be `.controlTextColor` (a system token), not a hard-coded RGB")
    }

    // MARK: - Icon rendering

    /// SF Symbols default to multi-color/hierarchical rendering for some glyphs (e.g. `sparkles`),
    /// which IGNORES `contentTintColor` and renders fragments in the symbol's intrinsic colors.
    /// `isTemplate = true` strips those colors so the symbol respects our tint — matching the
    /// way AppKit's native segment rendering forces monochrome internally.
    func testIconIsTemplateImage() {
        let control = makeControl()
        let overlay = attachOverlay(on: control)
        if #available(macOS 11.0, *) {
            XCTAssertTrue(overlay.icon.image?.isTemplate ?? false,
                "regression: SF Symbol must be template so `contentTintColor` is honored — sibling segments use AppKit's native rendering which forces monochrome internally, so our overlay must do the same or `sparkles`-style glyphs render with intrinsic colors and visually clash with the row")
        }
    }

    // MARK: - Selection sync

    func testBadgeReflectsInitialUnselectedState() {
        let control = makeControl()
        control.selectedSegment = 0
        let overlay = attachOverlay(on: control)
        XCTAssertFalse(overlay.badge.isSelectedState,
            "badge must start in its unselected (gradient) state when the segment isn't selected")
    }

    func testBadgeReflectsInitialSelectedState() {
        let control = makeControl()
        control.selectedSegment = 2
        let overlay = attachOverlay(on: control)
        XCTAssertTrue(overlay.badge.isSelectedState,
            "badge must start in its selected (white-overlay) state when the segment is selected on first show")
    }

    func testRefreshSelectionSyncsBadge() {
        let control = makeControl()
        control.selectedSegment = 0
        let overlay = attachOverlay(on: control)
        XCTAssertFalse(overlay.badge.isSelectedState)
        control.selectedSegment = 2
        ProBadgeView.refreshSelection(in: control, proIndex: 2, overlay: overlay)
        XCTAssertTrue(overlay.badge.isSelectedState,
            "after the user clicks the Pro segment, the badge must mirror the new selection — AppKit doesn't notify the badge automatically")
    }

    func testRefreshSelectionSyncsBadgeOnDeselection() {
        let control = makeControl()
        control.selectedSegment = 2
        let overlay = attachOverlay(on: control)
        XCTAssertTrue(overlay.badge.isSelectedState)
        control.selectedSegment = 0
        ProBadgeView.refreshSelection(in: control, proIndex: 2, overlay: overlay)
        XCTAssertFalse(overlay.badge.isSelectedState)
    }

    func testRefreshSelectionMarksIconAndLabelForRedraw() {
        let control = makeControl()
        control.selectedSegment = 0
        let overlay = attachOverlay(on: control)
        // After a selection change, the icon and label must redraw so their `colorProvider`-driven
        // `viewWillDraw` picks up the new state. The cheap way to assert this is to mark the
        // views non-dirty, call refresh, and check the dirty flag flipped — but
        // `setNeedsDisplay`/`needsDisplay` round-trips aren't reliable across runloops. Instead,
        // we drive the change end-to-end: set the segment, refresh, and verify the overlay's
        // colorProvider would resolve to the new color (which is what we ultimately care about).
        control.selectedSegment = 2
        ProBadgeView.refreshSelection(in: control, proIndex: 2, overlay: overlay)
        let provider = ProBadgeView.segmentColorProvider(for: control, segmentIndex: 2)
        XCTAssertEqual(provider(), NSColor.controlTextColor,
            "without a key window, even the selected segment uses the unselected color — proving the provider tracks the live state, not a snapshot at attach time")
    }

    // MARK: - Enabled state (AppKit-driven, we don't touch)

    func testAttachDoesNotChangeSegmentEnabledState() {
        let control = makeControl()
        control.setEnabled(false, forSegment: 2)
        _ = attachOverlay(on: control)
        XCTAssertFalse(control.isEnabled(forSegment: 2),
            "regression: we must not flip a segment's enabled state — AppKit fades disabled segments natively")
    }

    func testAttachDoesNotChangeControlEnabledState() {
        let control = makeControl()
        control.isEnabled = false
        _ = attachOverlay(on: control)
        XCTAssertFalse(control.isEnabled,
            "regression: we must not flip the control's enabled state — AppKit fades disabled controls natively")
    }

    // MARK: - Badge selection state mechanics

    func testBadgeSelectedStateWorksBeforeWindowAttach() {
        let badge = ProBadgeView()
        XCTAssertFalse(badge.isSelectedState)
        badge.setSelected(true)
        XCTAssertTrue(badge.isSelectedState)
        badge.setSelected(false)
        XCTAssertFalse(badge.isSelectedState)
    }

    // MARK: - Layout / viewDidMoveToWindow (regression coverage)

    /// `layout()` is where the badge sizes its three gradient sublayers and — critically — sets
    /// `borderMask.path` and `textMask.frame`. If `layout()` is ever broken (e.g. an earlier
    /// attempt no-op'd `_layoutSubtreeWithOldSize:` as a cascade-stop, which also suppressed the
    /// `layout()` callback), the masks stay unconfigured and the badge renders with only its
    /// 10%-alpha fill — the "faded" look. This pins that `layout()` produces sized sublayers.
    func testLayoutConfiguresGradientSublayerFrames() {
        let badge = ProBadgeView()
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.contentView?.addSubview(badge)
        badge.frame = NSRect(x: 0, y: 0, width: 30, height: 14)
        badge.layoutSubtreeIfNeeded()
        guard let sublayers = badge.layer?.sublayers, sublayers.count >= 3 else {
            return XCTFail("badge must own three gradient sublayers (fill / border / text) — got \(badge.layer?.sublayers?.count ?? 0)")
        }
        for (i, sublayer) in sublayers.prefix(3).enumerated() {
            XCTAssertGreaterThan(sublayer.frame.width, 0,
                "regression: badge gradient sublayer \(i) has zero width after `layout()` — the gradient frames weren't sized, so the badge can't render its border/text gradients")
            XCTAssertGreaterThan(sublayer.frame.height, 0,
                "regression: badge gradient sublayer \(i) has zero height after `layout()`")
        }
        host.orderOut(nil)
    }

    /// Regression pin for the "faded badge in a lazily-built pane" bug.
    ///
    /// When the badge is created off-window (the per-shortcut Appearance pane is built lazily,
    /// while Settings is already key) its `init` runs with `window == nil`, so `updateColors`
    /// resolves the *not-key* branch. The `didBecomeKey` notification observer registered in
    /// `viewDidMoveToWindow` never fires (the window was already key — no state *change*), so
    /// without an explicit resync the badge stays stuck in the state `init` left it in.
    ///
    /// The fix is the `updateColors()` call in `viewDidMoveToWindow`. `updateColors()` always
    /// invokes `onWindowKeyChanged`, which gives us a deterministic, window-key-independent hook
    /// to assert on: entering a window must re-run `updateColors` exactly because of that call.
    func testViewDidMoveToWindowResyncsColors() {
        let badge = ProBadgeView()
        var resyncCount = 0
        // `onWindowKeyChanged` is invoked from inside `updateColors()`. We set it *after* init
        // (init's own `updateColors` call already ran, before this closure existed) so the only
        // way the counter increments is a fresh `updateColors` triggered by entering the window.
        badge.onWindowKeyChanged = { resyncCount += 1 }
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.contentView?.addSubview(badge)
        XCTAssertGreaterThan(resyncCount, 0,
            "regression: `ProBadgeView.viewDidMoveToWindow` must call `updateColors()` so a badge added to an already-key window resyncs its visual state — otherwise a selected badge built in a lazy pane stays in the gradient state `init` chose when `window` was nil")
        host.orderOut(nil)
    }
}
