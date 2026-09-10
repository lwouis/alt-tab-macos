import Foundation

/// What the switcher may do to the search field's caret when it is about to hand a key-down to the field.
enum SearchCaretIntent: Equatable {
    /// Do nothing. Either search is off, or the field already owns the caret and its selection is the
    /// user's: a ⌘A, a shift-arrow range, a double-click on a word.
    case leaveSelectionAlone
    /// Make the field first responder, then collapse the selection to the end of the text.
    case takeCaretAndCollapseToEnd
}

/// The caret-ownership rule for the in-switcher search field, split out of `TilesView` as a pure kernel
/// (same pattern as `SearchModeResolver`). `TilesView` performs the AppKit side of it: first responder,
/// `NSText.selectedRange`. Everything a keystroke then does to the text (insert, delete, replace a
/// selection) is AppKit's own editing, which AltTab does not reimplement.
enum SearchFieldEditing {
    static func caretIntent(mode: SearchMode, fieldOwnsCaret: Bool) -> SearchCaretIntent {
        guard mode == .editing, !fieldOwnsCaret else { return .leaveSelectionAlone }
        return .takeCaretAndCollapseToEnd
    }

    /// A collapsed caret sitting after the last character. `length` is in UTF-16 units, the unit
    /// `NSText.selectedRange` is expressed in.
    static func endOfText(length: Int) -> NSRange {
        NSRange(location: length, length: 0)
    }
}
