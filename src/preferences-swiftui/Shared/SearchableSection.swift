import SwiftUI

/// A GroupBox wrapper that hides itself when the search query doesn't match
/// any of its `searchableText`. Reports visibility to SearchViewModel for
/// auto-scroll coordination.
@available(macOS 13.0, *)
struct SearchableSection<Content: View, Label: View>: View {
    @EnvironmentObject var searchVM: SearchViewModel
    let sectionId: String
    let searchableText: [String]
    let label: () -> Label
    let content: () -> Content

    @State private var isVisible = true

    init(
        sectionId: String,
        searchableText: [String],
        @ViewBuilder label: @escaping () -> Label,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.sectionId = sectionId
        self.searchableText = searchableText
        self.label = label
        self.content = content
    }

    var body: some View {
        GroupBox(content: content, label: label)
            .frame(maxHeight: isVisible ? .infinity : 0)
            .opacity(isVisible ? 1 : 0)
            .clipped()
            .id(sectionId)
            .onAppear {
                searchVM.registerSection(sectionId)
                reevaluateVisibility()
            }
            .onChange(of: searchVM.query) { _ in reevaluateVisibility() }
    }

    private func reevaluateVisibility() {
        let newVisible: Bool
        if SettingsSearch.isQueryEmpty(searchVM.query) {
            newVisible = true
        } else {
            newVisible = searchableText.contains { searchVM.textMatches($0) }
        }
        if newVisible != isVisible {
            isVisible = newVisible
        }
        searchVM.updateSectionVisibility(sectionId, isVisible: newVisible)
    }
}
