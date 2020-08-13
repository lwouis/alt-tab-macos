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
    case filledCircledMultiplySign = "􀁑"
    case filledCircledMinusSign = "􀁏"
    case filledCircledPlusSign = "􀁍"
    case filledCircledNumber0 = "􀀹"
    case filledCircledNumber10 = "􀔔"
}

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class ThumbnailFontIconView: ThumbnailTitleView {
    convenience init(_ symbol: Symbols, _ size: CGFloat = Preferences.fontIconSize, _ color: NSColor = .white, _ shadow: NSShadow? = ThumbnailView.makeShadow(.darkGray)) {
        // This helps SF symbols display vertically centered and not clipped at the bottom
        self.init(size, 3, shadow: shadow)
        string = symbol.rawValue
        font = NSFont(name: "SF Pro Text", size: size)
        textColor = color
        // This helps SF symbols not be clipped on the right
        widthAnchor.constraint(equalToConstant: size * 1.15).isActive = true
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
    convenience init(_ thumbnailFontIconView: ThumbnailFontIconView, _ backgroundColor: NSColor, _ offset: Bool = false) {
        self.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let backgroundView = ThumbnailFontIconView(.filledCircled, thumbnailFontIconView.font!.pointSize - (offset ? 2 : 0), backgroundColor)
        addSubview(backgroundView)
        addSubview(thumbnailFontIconView, positioned: .above, relativeTo: nil)
        if offset {
            backgroundView.leftAnchor.constraint(equalTo: backgroundView.superview!.leftAnchor, constant: 1).isActive = true
        }
        fit(thumbnailFontIconView.fittingSize.width, thumbnailFontIconView.fittingSize.height)
    }
}
