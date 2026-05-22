import SwiftUI
/// Applies a yellow highlight to a view when its text content matches the current search query.
/// Used as a simplified (whole-control) highlight — character-level precision is deferred.
@available(macOS 13.0, *)
struct SearchHighlightModifier: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHighlighted ? Color.yellow.opacity(0.5) : .clear)
            )
    }
}

@available(macOS 13.0, *)
extension View {
    func searchHighlight(_ isHighlighted: Bool) -> some View {
        modifier(SearchHighlightModifier(isHighlighted: isHighlighted))
    }
}
