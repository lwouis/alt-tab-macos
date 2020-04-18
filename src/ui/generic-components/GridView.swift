import Cocoa

class GridView: NSGridView {
    static let padding = CGFloat(20)
    static let interPadding = CGFloat(10)

    convenience init(_ controls: [[NSView]]) {
        self.init(views: controls)
        translatesAutoresizingMaskIntoConstraints = false
        yPlacement = .fill
        rowAlignment = .firstBaseline
        columnSpacing = GridView.interPadding
        rowSpacing = GridView.interPadding
        column(at: 0).leadingPadding = GridView.padding
        column(at: numberOfColumns - 1).trailingPadding = GridView.padding
        row(at: 0).topPadding = GridView.padding
        row(at: numberOfRows - 1).bottomPadding = GridView.padding
    }
}
