import Cocoa

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class FontIcon: CellTitle {
    static let sfSymbolCircledMinusSign = "􀁎"
    static let sfSymbolCircledDotSign = "􀍷"
    static let sfSymbolCircledNumber0 = "􀀸"
    static let sfSymbolCircledNumber10 = "􀓵"

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(_ text: String, _ size: CGFloat, _ color: NSColor) {
        // This helps SF symbols display vertically centered and not clipped at the bottom
        super.init(size, 3)
        string = text
        font = NSFont(name: "SF Pro Text", size: size)
        textColor = color
        // This helps SF symbols not be clipped on the right
        widthAnchor.constraint(equalToConstant: size * 1.15).isActive = true
    }

    // number should be in the interval [0-50]
    func setNumber(_ number: UInt32) {
        let (baseCharacter, offset) = baseCharacterAndOffset(number)
        string = String(UnicodeScalar(baseCharacter.unicodeScalars.first!.value + offset)!)
    }

    private func baseCharacterAndOffset(_ number: UInt32) -> (String, UInt32) {
        if number <= 9 {
            // numbers alternate between empty and full circles; we skip the full circles
            return (FontIcon.sfSymbolCircledNumber0, number * UInt32(2))
        } else {
            return (FontIcon.sfSymbolCircledNumber10, number - 10)
        }
    }
}
