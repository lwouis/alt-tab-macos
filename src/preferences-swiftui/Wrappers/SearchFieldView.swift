import SwiftUI
/// NSViewRepresentable wrapping `NSSearchField` for native search field appearance
/// and behavior. Bridges to a SwiftUI `Binding<String>`.
@available(macOS 13.0, *)
struct SearchFieldView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = NSLocalizedString("Search", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.bezelStyle = .roundedBezel
        searchField.controlSize = .large
        searchField.delegate = context.coordinator
        searchField.translatesAutoresizingMaskIntoConstraints = false
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        let parent: SearchFieldView

        init(_ parent: SearchFieldView) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }
    }
}
