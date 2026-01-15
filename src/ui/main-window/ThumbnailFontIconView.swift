import Cocoa

enum Symbols: String {
    case circledPlusSign = "􀁌"
    case circledMinusSign = "􀁎"
    case circledSlashSign = "􀕧"
    case circledNumber0 = "􀀸"
    case circledNumber10 = "􀓵"
    case circledStar = "􀕬"
    case filledCircledDot = "􀢚"
    case filledCircledStar = "􀕭"
    case filledCircled = "􀀁"
    case filledCircledNumber0 = "􀀹"
    case filledCircledNumber10 = "􀔔"
    case circledInfo = "􀅴"
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class ThumbnailFontIconView: ThumbnailTitleView {
    static var paragraphStyle = {
        let paragraphStyle = NSMutableParagraphStyle()
        // clip the top of the box since we know these symbols are always disks
        paragraphStyle.lineHeightMultiple = 0.85
        return paragraphStyle
    }()
    var initialAttributedString: NSMutableAttributedString!
    private var overlayLabel: NSTextField?
    private var overlayCenterX: NSLayoutConstraint?
    private var overlayCenterY: NSLayoutConstraint?
    private var wakeObserver: Any?
    private var appActiveObserver: Any?
    private var overlayText: String?

    convenience init(symbol: Symbols, tooltip: String? = nil, size: CGFloat = Appearance.fontHeight, color: NSColor = Appearance.fontColor) {
        // This helps SF symbols display vertically centered and not clipped at the top
        self.init(font: NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!)
        initialAttributedString = NSMutableAttributedString(string: symbol.rawValue, attributes: [.paragraphStyle: ThumbnailFontIconView.paragraphStyle])
        attributedStringValue = initialAttributedString
        textColor = color
        toolTip = tooltip
        addOrUpdateConstraint(widthAnchor, cell!.cellSize.width)
        wantsLayer = true
        canDrawSubviewsIntoLayer = true
    }

    private func ensureOverlayLabel() {
        if overlayLabel != nil { return }
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = true
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.textColor = .white
        label.wantsLayer = true
        addSubview(label)
        overlayLabel = label
    }
    
    private func occupancy(for text: String) -> CGFloat {
        // Slightly larger target occupancy for 1–2 digits; smaller for 3–4 digits
        return (text.count <= 2) ? 0.78 : (text.count <= 3 ? 0.62 : 0.50)
    }

    private func fittedFont(for text: String) -> NSFont {
        let baseFont = self.font ?? NSFont(name: "SF Pro Text", size: (Appearance.fontHeight * 0.85).rounded())!
        let boundsW = (cell?.cellSize.width ?? bounds.width)
        let boundsH = (cell?.cellSize.height ?? bounds.height)

        let occupancy = occupancy(for: text)
        let availableW = boundsW * occupancy
        let availableH = boundsH * occupancy

        let attrs: [NSAttributedString.Key: Any] = [.font: baseFont]
        let measured = (text as NSString).size(withAttributes: attrs)

        // Always compute a uniform scale so 2-digit numbers can scale UP a bit,
        // and 3–4 digit numbers scale DOWN more than before.
        let widthScale = availableW / max(measured.width, 1)
        let heightScale = availableH / max(measured.height, 1)
        let scale = min(widthScale, heightScale)

        // Clamp to reasonable bounds and quantize to avoid jitter across repeated calls.
        let clampedScale = max(0.4, min(scale, 1.25))
        let newSize = max(6, floor(baseFont.pointSize * clampedScale))
        return NSFont(name: baseFont.fontName, size: newSize) ?? baseFont
    }

    override func layout() {
        super.layout()
        if let label = overlayLabel, !label.isHidden {
            let container = (self.cell?.titleRect(forBounds: self.bounds)) ?? self.bounds
            let size: CGSize
            if let cell = label.cell {
                size = cell.cellSize
            } else {
                size = label.intrinsicContentSize
            }
            let x = container.midX - size.width / 2.0
            let y = container.midY - size.height / 2.0
            let dx: CGFloat = -1.75  // move slightly left
            let occupancy = occupancy(for: label.stringValue)
            let dy: CGFloat =  -1 - (5*occupancy - 2.5)  // move slightly up; -1.5 is about right for two digits
            label.frame = CGRect(x: x + dx, y: y + dy, width: size.width, height: size.height)
            label.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let text = overlayText, !text.isEmpty else { return }

        let container = (self.cell?.titleRect(forBounds: self.bounds)) ?? self.bounds
        let font = fittedFont(for: text)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let x = container.midX - size.width / 2.0
        let y = container.midY - size.height / 2.0
        let dx: CGFloat = -1.75
        let occ = occupancy(for: text)
        let dy: CGFloat = -1 - (5*occ - 2.5)
        (text as NSString).draw(at: NSPoint(x: x + dx, y: y + dy), withAttributes: attrs)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
        if let obs = appActiveObserver {
            NotificationCenter.default.removeObserver(obs)
            appActiveObserver = nil
        }
        guard window != nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceRelayoutAndRedraw()
        }
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.forceRelayoutAndRedraw()
        }
    }

    deinit {
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = appActiveObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        forceRelayoutAndRedraw()
    }

    private func forceRelayoutAndRedraw()
    {
        // Keep label-based path alive if it's currently visible (<=30), but prefer our draw-based overlay for >30
        if let label = overlayLabel, !label.isHidden {
            let text = label.stringValue
            let font = fittedFont(for: text)
            let attrs: [NSAttributedString.Key: Any] = [ .font: font ]
            label.attributedStringValue = NSAttributedString(string: text, attributes: attrs)
            label.invalidateIntrinsicContentSize()
            label.needsDisplay = true
            label.displayIfNeeded()
        }
        // Always invalidate our own drawing; cheap and avoids stale overlays.
        needsLayout = true
        layoutSubtreeIfNeeded()
        needsDisplay = true
        displayIfNeeded()
    }

    func setNumber(_ number: Int, _ filled: Bool) {
        // Preserve existing SF Symbols behavior for 0–30 exactly
        if number <= 30 {
            overlayText = nil
            overlayLabel?.isHidden = true
            let (baseCharacter, offset) = baseCharacterAndOffset(number, filled)
            replaceCharIfNeeded(String(UnicodeScalar(Int(baseCharacter.unicodeScalars.first!.value) + offset)!))
            return
        }

        // 5+ digits → fall back to filled star
        if number >= 10000 {
            overlayText = nil
            overlayLabel?.isHidden = true
            setFilledStar()
            return
        }

        // Custom render for numbers > 30 and up to 4 digits:
        // Draw the filled circle symbol, then overlay centered white text using the same SF font.
        overlayText = String(number)
        overlayLabel?.isHidden = true
        replaceCharIfNeeded(Symbols.filledCircled.rawValue)
        needsLayout = true
        needsDisplay = true
    }
    
    private func setSymbol(_ symbol: String) {
        overlayText = nil
        overlayLabel?.isHidden = true
        needsDisplay = true
        replaceCharIfNeeded(symbol)
    }

    func setStar() {
        setSymbol(Symbols.circledStar.rawValue)
    }

    func setFilledStar() {
        setSymbol(Symbols.filledCircledStar.rawValue)
    }

    func setFilledDot() {
        setSymbol(Symbols.filledCircledDot.rawValue)
    }

    private func replaceCharIfNeeded(_ newChar: String) {
        if newChar != attributedStringValue.string {
            initialAttributedString.replaceCharacters(in: NSRange(location: 0, length: 1), with: newChar)
            attributedStringValue = initialAttributedString
        }
    }

    private func baseCharacterAndOffset(_ number: Int, _ filled: Bool) -> (String, Int) {
        if number <= 9 {
            // numbers alternate between empty and full circles; we skip the full circles
            return ((filled ? Symbols.filledCircledNumber0 : Symbols.circledNumber0).rawValue, number * 2)
        } else {
            return ((filled ? Symbols.filledCircledNumber10 : Symbols.circledNumber10).rawValue, number - 10)
        }
    }
}

class ThumbnailFilledFontIconView: NSView {
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, backgroundColor: NSColor, size: CGFloat) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = ThumbnailFontIconView(symbol: .filledCircled, size: size - 3, color: backgroundColor)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        backgroundView.centerXAnchor.constraint(equalTo: thumbnailFontIconView.centerXAnchor).isActive = true
        let offset = ((thumbnailFontIconView.cell!.cellSize.width - backgroundView.cell!.cellSize.width) / 2).rounded()
        backgroundView.topAnchor.constraint(equalTo: thumbnailFontIconView.topAnchor, constant: offset).isActive = true
        widthAnchor.constraint(equalTo: thumbnailFontIconView.widthAnchor).isActive = true
        heightAnchor.constraint(equalTo: thumbnailFontIconView.heightAnchor).isActive = true
    }
}
