import SwiftUI
/// Arrow-branch indicator button shown next to global appearance rows when one or more
/// shortcuts override that value. Mirrors the `.arrowTriangleBranch` rotated 180° icon
/// from the AppKit version. Tooltip lists overriding shortcut numbers; click navigates
/// to the first overriding shortcut's Appearance pane in ControlsTab.
@available(macOS 13.0, *)
struct OverrideIndicatorButton: View {
    let overrideIndices: [Int]
    let action: () -> Void

    var body: some View {
        Image(systemName: "arrow.triangle.branch")
            .font(.system(size: 14))
            .rotationEffect(.degrees(180))
            .foregroundColor(.accentColor)
            .help(tooltip)
            .opacity(overrideIndices.isEmpty ? 0 : 1)
            .frame(width: overrideIndices.isEmpty ? 0 : 20)
            .onTapGesture { action() }
    }

    private var tooltip: String {
        let numbers = overrideIndices.map { String($0 + 1) }.joined(separator: ", ")
        return NSLocalizedString("Overridden in Shortcut:", comment: "") + " " + numbers
    }
}
