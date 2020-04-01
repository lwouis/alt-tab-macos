import Cocoa

class GridView {
    static let padding = CGFloat(20)
    static let interPadding = CGFloat(10)
    static let indentPadding = padding * 2

    static func make(_ controls: [[NSView]]) -> NSGridView {
        let gridView = NSGridView(views: controls)
        gridView.translatesAutoresizingMaskIntoConstraints = false
        gridView.yPlacement = .fill
        gridView.rowAlignment = .firstBaseline
        gridView.columnSpacing = interPadding
        gridView.rowSpacing = interPadding
        gridView.column(at: 0).leadingPadding = padding
        gridView.column(at: gridView.numberOfColumns - 1).trailingPadding = padding
        gridView.row(at: 0).topPadding = padding
        gridView.row(at: gridView.numberOfRows - 1).bottomPadding = padding
        return gridView
    }
}
