import Cocoa

enum Symbols: String {
    case circledPlusSign = "􀁌"
    case circledMinusSign = "􀁎"
    case circledSlashSign = "􀕧"
    case circledNumber0 = "􀀸"
    case circledNumber10 = "􀓵"
    case circledStar = "􀕬"
    case filledCircledStar = "􀕭"
    case filledCircled = "􀀁"
    case filledCircledNumber0 = "􀀹"
    case filledCircledNumber10 = "􀔔"
    case circledInfo = "􀅴"
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class ThumbnailFontIconView: ThumbnailTitleView {
    convenience init(symbol: Symbols, tooltip: String? = nil, size: CGFloat = Appearance.fontHeight,
                     color: NSColor = Appearance.fontColor,
                     shadow: NSShadow? = ThumbnailView.makeShadow(Appearance.indicatedIconShadowColor)) {
        // This helps SF symbols display vertically centered and not clipped at the top
        self.init(shadow: shadow, font: NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!)
        stringValue = symbol.rawValue
        textColor = color
        addOrUpdateConstraint(widthAnchor, cell!.cellSize.width)
        toolTip = tooltip
        fixHeight()
    }

    // number should be in the interval [0-50]
    func setNumber(_ number: Int, _ filled: Bool) {
        let (baseCharacter, offset) = baseCharacterAndOffset(number, filled)
        assignIfDifferent(&stringValue, String(UnicodeScalar(Int(baseCharacter.unicodeScalars.first!.value) + offset)!))
    }

    private func baseCharacterAndOffset(_ number: Int, _ filled: Bool) -> (String, Int) {
        if number <= 9 {
            // numbers alternate between empty and full circles; we skip the full circles
            return ((filled ? Symbols.filledCircledNumber0 : Symbols.circledNumber0).rawValue, number * 2)
        } else {
            return ((filled ? Symbols.filledCircledNumber10 : Symbols.circledNumber10).rawValue, number - 10)
        }
    }

    func setStar() {
        assignIfDifferent(&stringValue, Symbols.circledStar.rawValue)
    }

    func setFilledStar() {
        assignIfDifferent(&stringValue, Symbols.filledCircledStar.rawValue)
    }
}

class ThumbnailFilledFontIconView: NSView {
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, backgroundColor: NSColor, size: CGFloat) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = ThumbnailFontIconView(symbol: .filledCircled, size: size - 4, color: backgroundColor, shadow: nil)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        backgroundView.frame.origin = CGPoint(x: backgroundView.frame.origin.x + 2, y: backgroundView.frame.origin.y + 2)
        fit(thumbnailFontIconView.fittingSize.width, thumbnailFontIconView.fittingSize.height)
    }
}
