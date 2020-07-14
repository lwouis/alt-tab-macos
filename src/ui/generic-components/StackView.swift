import Cocoa

class StackView: NSStackView {
    convenience init(_ views: [NSView], _ orientation: NSUserInterfaceLayoutOrientation = .horizontal, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0, left: CGFloat = 0) {
        self.init(views: views)
        edgeInsets = NSEdgeInsets(top: top, left: left, bottom: bottom, right: right)
        alignment = orientation == .horizontal ? .firstBaseline : .leading
        // workaround: for some reason, horizontal stackviews with a RecorderControl have extra fittingSize.height
        if orientation == .horizontal && (views.contains { $0 is CustomRecorderControl }) {
            fit(fittingSize.width, fittingSize.height - 7)
        } else {
            fit()
        }
    }
}
