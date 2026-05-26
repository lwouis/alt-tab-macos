import Cocoa

/// `NSPopUpButton` configured to look like System Settings popups and — critically — to size
/// itself to the *currently-selected* item rather than the widest one (the AppKit default).
///
/// There is no public API to opt into "size to current item" — `NSPopUpButton` is hardcoded to
/// reserve room for its widest item so the chrome doesn't visually resize when the user picks a
/// different selection. To get pixel-perfect bezel + arrow + padding metrics, the only viable
/// path is to override `intrinsicContentSize` and have AppKit measure a *probe* button that
/// happens to contain just the current title.
///
/// The previous version did that probe measurement on *every* `intrinsicContentSize` query.
/// AppKit queries the property many times per layout cycle, and the `_windowChangedKeyState`
/// cascade fires a fresh layout cycle on every focus change — so we were running `sizeToFit`
/// (which triggers TextKit2 layout on Tahoe) ~50 times per cascade × ~25 popups in Settings.
/// Roughly 50ms of pure overhead per focus switch from this one method.
///
/// Fix: keep the probe technique (preserves pixel-identical sizing), cache the result keyed by
/// the displayed title. The cache is invalidated automatically next time `title` changes (which
/// happens on every selection mutation), so we don't have to override every individual mutator
/// path. AppKit's repeated queries hit the cache in O(1).
class PopupButtonLikeSystemSettings: NSPopUpButton {
    private var cachedIntrinsicSize: NSSize?
    private var cachedIntrinsicSizeTitle: String?

    convenience init() {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    override var intrinsicContentSize: NSSize {
        let currentTitle = title
        if let cached = cachedIntrinsicSize, cachedIntrinsicSizeTitle == currentTitle {
            return cached
        }
        let size: NSSize
        if let selectedItem {
            size = measureSize(for: currentTitle, image: selectedItem.image)
        } else {
            size = super.intrinsicContentSize
        }
        cachedIntrinsicSize = size
        cachedIntrinsicSizeTitle = currentTitle
        return size
    }

    /// Probe measurement — pixel-identical to what AppKit would compute for a popup whose menu
    /// has a single item with this title. Heavy (full TextKit layout via `sizeToFit`), hence
    /// the caller caches the result.
    private func measureSize(for titleText: String, image: NSImage?) -> NSSize {
        let probe = NSPopUpButton()
        probe.addItem(withTitle: titleText)
        probe.item(at: 0)!.image = image
        let probeCell = probe.cell! as! NSPopUpButtonCell
        let selfCell = cell! as! NSPopUpButtonCell
        probeCell.bezelStyle = selfCell.bezelStyle
        probeCell.arrowPosition = selfCell.arrowPosition
        probeCell.imagePosition = selfCell.imagePosition
        probe.showsBorderOnlyWhileMouseInside = showsBorderOnlyWhileMouseInside
        probe.sizeToFit()
        return probe.intrinsicContentSize
    }
}
