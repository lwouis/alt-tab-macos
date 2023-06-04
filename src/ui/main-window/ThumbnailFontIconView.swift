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
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class ThumbnailFontIconView: ThumbnailTitleView {
    convenience init(_ symbol: Symbols, _ tooltip: String?, _ size: CGFloat = Preferences.fontHeight, _ color: NSColor = .white, _ shadow: NSShadow? = ThumbnailView.makeShadow(.darkGray)) {
        self.init(size, shadow)
        string = symbol.rawValue
        // This helps SF symbols display vertically centered and not clipped at the top
        font = NSFont(name: "SF Pro Text", size: (size * 0.85).rounded())!
        textColor = color
        // This helps SF symbols not be clipped on the right
        widthAnchor.constraint(equalToConstant: size * 1.15).isActive = true
        toolTip = tooltip
    }

    // number should be in the interval [0-50]
    func setNumber(_ number: Int, _ filled: Bool) {
        let (baseCharacter, offset) = baseCharacterAndOffset(number, filled)
        assignIfDifferent(&string, String(UnicodeScalar(Int(baseCharacter.unicodeScalars.first!.value) + offset)!))
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
        assignIfDifferent(&string, Symbols.circledStar.rawValue)
    }

    func setFilledStar() {
        assignIfDifferent(&string, Symbols.filledCircledStar.rawValue)
    }
}

class ThumbnailFilledFontIconView: NSView {
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, _ backgroundColor: NSColor, _ size: CGFloat) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = ThumbnailFontIconView(.filledCircled, nil, size - 2, backgroundColor, nil)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        backgroundView.frame.origin = CGPoint(x: backgroundView.frame.origin.x + 1, y: backgroundView.frame.origin.y + 1)
        fit(thumbnailFontIconView.fittingSize.width, thumbnailFontIconView.fittingSize.height)
    }
}
