import SwiftUI

/// A reusable row with a label on the left and custom content on the right.
/// Applies search highlighting to the label when the current query matches.
@available(macOS 13.0, *)
struct LabeledRow<Content: View>: View {
    @EnvironmentObject var searchVM: SearchViewModel
    let label: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .searchHighlight(searchVM.textMatches(label))
            Spacer()
            content()
        }
        .padding(.vertical, 6).padding(.horizontal, 12)
    }
}

/// A full-width row that renders the given content without a label column.
@available(macOS 13.0, *)
struct FullWidthRow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(.vertical, 6).padding(.horizontal, 12)
    }
}

/// A thin divider used between rows in a GroupBox.
@available(macOS 13.0, *)
struct RowDivider: View {
    var body: some View {
        Divider().padding(.vertical, 4)
    }
}
