import Cocoa

// Font icon using SF Symbols from the SF Pro font from Apple
// see https://developer.apple.com/design/human-interface-guidelines/sf-symbols/overview/
class FontIcon: CellTitle {
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(_ text: String, _ size: CGFloat, _ color: NSColor) {
        // This helps SF symbols display vertically centered and not clipped at the bottom
        super.init(4)
        string = text
        font = NSFont(name: "SF Pro Text", size: size)
        textColor = color
        heightAnchor.constraint(equalToConstant: size + magicOffset).isActive = true
        // This helps SF symbols not be clipped on the right
        widthAnchor.constraint(equalToConstant: size * 1.15).isActive = true
    }
}
