import XCTest

/// The in-switcher search field, exercised the way a user uses it: typing, the four delete keys, ⌘A,
/// mouse selections, paste over a selection. Each keystroke goes through `SearchFieldEditing.caretIntent`
/// first, exactly as `TilesView.giveTheFieldTheCaretNow` does, then hits a real AppKit field editor — so
/// what is asserted is AppKit's editing behavior under our caret rule, not a model of it.
final class SearchFieldEditingTests: XCTestCase {

    // MARK: - Harness

    /// Miniature of the production key path. `NSTextView` in field-editor mode is what `NSSearchField`
    /// puts behind its cell, and `NSText.selectedRange` is the same property `TilesView` writes.
    private final class Field {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        var mode = SearchMode.editing
        private(set) var ownsCaret = false
        private(set) var caretTakenCount = 0

        init(_ text: String = "", ownsCaret: Bool = true) {
            editor.isFieldEditor = true
            editor.isEditable = true
            editor.isSelectable = true
            editor.string = text
            editor.selectedRange = NSRange(location: text.utf16.count, length: 0)
            self.ownsCaret = ownsCaret
        }

        var text: String { editor.string }
        var selection: NSRange { editor.selectedRange }
        var caret: Int? { selection.length == 0 ? selection.location : nil }
        var selectedText: String { (editor.string as NSString).substring(with: selection) }

        /// The field is not first responder: the session just opened, or a tile took the caret back.
        /// AppKit hands a text field its whole content selected when it becomes first responder, which is
        /// the state `placeAtEnd` exists to undo.
        func loseTheCaret() {
            ownsCaret = false
            editor.selectedRange = NSRange(location: 0, length: editor.string.utf16.count)
        }

        /// A click or a drag in the field: the mouse both takes the caret and sets the selection, without
        /// any key-down, so the caret rule is not consulted.
        func selectWithMouse(_ range: NSRange) {
            ownsCaret = true
            editor.selectedRange = range
        }

        func clickWithMouse(at location: Int) {
            selectWithMouse(NSRange(location: location, length: 0))
        }

        private func key(_ edit: (NSTextView) -> Void) {
            if SearchFieldEditing.caretIntent(mode: mode, fieldOwnsCaret: ownsCaret) == .takeCaretAndCollapseToEnd {
                ownsCaret = true
                caretTakenCount += 1
                editor.selectedRange = SearchFieldEditing.endOfText(length: editor.string.utf16.count)
            }
            edit(editor)
        }

        func type(_ string: String) { key { $0.insertText(string, replacementRange: $0.selectedRange) } }
        func backspace() { key { $0.deleteBackward(nil) } }
        func forwardDelete() { key { $0.deleteForward(nil) } }
        func optionBackspace() { key { $0.deleteWordBackward(nil) } }
        func optionForwardDelete() { key { $0.deleteWordForward(nil) } }
        func commandBackspace() { key { $0.deleteToBeginningOfLine(nil) } }
        func selectAll() { key { $0.selectAll(nil) } }
        func home() { key { $0.moveToBeginningOfDocument(nil) } }
        func end() { key { $0.moveToEndOfDocument(nil) } }
        /// ⌘V. `NSTextView.paste` would read the user's real pasteboard, so insert the same way the field
        /// editor does once the pasteboard has been read: replacing the selection.
        func paste(_ string: String) { type(string) }
    }

    // MARK: - A. The caret rule

    /// Search off: the field is not being edited, nothing to place.
    func testCaretIntentLeavesSelectionAloneWhenSearchIsOff() throws {
        XCTAssertEqual(SearchFieldEditing.caretIntent(mode: .off, fieldOwnsCaret: false), .leaveSelectionAlone)
        XCTAssertEqual(SearchFieldEditing.caretIntent(mode: .off, fieldOwnsCaret: true), .leaveSelectionAlone)
    }

    /// Editing but the field does not have the caret yet: take it, and collapse AppKit's focus select-all.
    func testCaretIntentTakesTheCaretWhenTheFieldDoesNotHaveIt() throws {
        XCTAssertEqual(SearchFieldEditing.caretIntent(mode: .editing, fieldOwnsCaret: false), .takeCaretAndCollapseToEnd)
    }

    /// #6019: once the field has the caret, its selection is the user's. Every key-down passed to the field
    /// ran through here, so moving it turned ⌘A into a no-op.
    func testCaretIntentLeavesSelectionAloneOnceTheFieldHasTheCaret() throws {
        XCTAssertEqual(SearchFieldEditing.caretIntent(mode: .editing, fieldOwnsCaret: true), .leaveSelectionAlone)
    }

    func testEndOfTextIsACollapsedCaretAfterTheLastCharacter() throws {
        XCTAssertEqual(SearchFieldEditing.endOfText(length: 0), NSRange(location: 0, length: 0))
        XCTAssertEqual(SearchFieldEditing.endOfText(length: 6), NSRange(location: 6, length: 0))
    }

    // MARK: - B. Taking the caret

    /// The keystroke that beats the deferred focus pass must not replace what is already in the field:
    /// AppKit hands over the whole content selected, so the caret goes to the end first.
    func testFirstKeyAfterFocusAppendsInsteadOfReplacing() throws {
        let field = Field("chrome")
        field.loseTheCaret()
        field.type("x")
        XCTAssertEqual(field.text, "chromex")
    }

    func testFirstKeyAfterFocusDeletesTheLastCharacterInsteadOfEverything() throws {
        let field = Field("chrome")
        field.loseTheCaret()
        field.backspace()
        XCTAssertEqual(field.text, "chrom")
    }

    /// Taking the caret happens once. The keys after it find the field already first responder.
    func testCaretIsTakenOnlyOnTheFirstKey() throws {
        let field = Field("chrome")
        field.loseTheCaret()
        field.type("a")
        field.type("b")
        field.backspace()
        XCTAssertEqual(field.caretTakenCount, 1)
    }

    /// Search off (the panel is cycling tiles, not editing): keys are not ours to route to the field.
    func testCaretIsNotTakenWhenSearchIsOff() throws {
        let field = Field("chrome", ownsCaret: false)
        field.mode = .off
        field.type("x")
        XCTAssertEqual(field.caretTakenCount, 0)
    }

    // MARK: - C. Typing

    func testTypingAppendsCharacters() throws {
        let field = Field()
        field.type("k")
        field.type("y")
        field.type("o")
        XCTAssertEqual(field.text, "kyo")
        XCTAssertEqual(field.caret, 3)
    }

    func testTypingInsertsAtTheCaretWhenItSitsMidText() throws {
        let field = Field("chrome")
        field.clickWithMouse(at: 2)
        field.type("X")
        XCTAssertEqual(field.text, "chXrome")
        XCTAssertEqual(field.caret, 3)
    }

    func testTypingReplacesTheSelection() throws {
        let field = Field("chrome")
        field.selectWithMouse(NSRange(location: 0, length: 6))
        field.type("f")
        XCTAssertEqual(field.text, "f")
        XCTAssertEqual(field.caret, 1)
    }

    func testTypingReplacesAPartialSelectionOnly() throws {
        let field = Field("kyoto trip")
        field.selectWithMouse(NSRange(location: 6, length: 4))
        field.type("hike")
        XCTAssertEqual(field.text, "kyoto hike")
    }

    func testTypingASpaceIsKeptInTheField() throws {
        let field = Field("kyoto")
        field.type(" ")
        field.type("t")
        XCTAssertEqual(field.text, "kyoto t")
    }

    // MARK: - D. Backspace

    func testBackspaceDeletesTheCharacterBeforeTheCaret() throws {
        let field = Field("chrome")
        field.backspace()
        XCTAssertEqual(field.text, "chrom")
        XCTAssertEqual(field.caret, 5)
    }

    func testBackspaceMidTextDeletesOnlyThere() throws {
        let field = Field("chrome")
        field.clickWithMouse(at: 3)
        field.backspace()
        XCTAssertEqual(field.text, "chome")
        XCTAssertEqual(field.caret, 2)
    }

    func testBackspaceAtTheStartDoesNothing() throws {
        let field = Field("chrome")
        field.clickWithMouse(at: 0)
        field.backspace()
        XCTAssertEqual(field.text, "chrome")
        XCTAssertEqual(field.caret, 0)
    }

    func testBackspaceOnAnEmptyFieldDoesNothing() throws {
        let field = Field()
        field.backspace()
        XCTAssertEqual(field.text, "")
    }

    func testRepeatedBackspacesEmptyTheField() throws {
        let field = Field("kyo")
        field.backspace()
        field.backspace()
        field.backspace()
        field.backspace()
        XCTAssertEqual(field.text, "")
        XCTAssertEqual(field.caret, 0)
    }

    /// #6019, the reported sequence: ⌘A then Delete must clear the whole search, not one character.
    func testBackspaceAfterSelectAllClearsTheField() throws {
        let field = Field("chrome")
        field.selectAll()
        field.backspace()
        XCTAssertEqual(field.text, "")
        XCTAssertEqual(field.caret, 0)
    }

    func testBackspaceDeletesAPartialSelectionAndNothingElse() throws {
        let field = Field("kyoto trip")
        field.selectWithMouse(NSRange(location: 5, length: 5))
        field.backspace()
        XCTAssertEqual(field.text, "kyoto")
        XCTAssertEqual(field.caret, 5)
    }

    /// The character before the selection is not part of it, so it survives.
    func testBackspaceOnASelectionDoesNotAlsoEatThePrecedingCharacter() throws {
        let field = Field("kyoto")
        field.selectWithMouse(NSRange(location: 2, length: 2))
        field.backspace()
        XCTAssertEqual(field.text, "kyo")
    }

    // MARK: - E. Forward delete (fn+Delete)

    func testForwardDeleteRemovesTheCharacterAfterTheCaret() throws {
        let field = Field("chrome")
        field.clickWithMouse(at: 0)
        field.forwardDelete()
        XCTAssertEqual(field.text, "hrome")
        XCTAssertEqual(field.caret, 0)
    }

    func testForwardDeleteAtTheEndDoesNothing() throws {
        let field = Field("chrome")
        field.forwardDelete()
        XCTAssertEqual(field.text, "chrome")
    }

    func testForwardDeleteAfterSelectAllClearsTheField() throws {
        let field = Field("chrome")
        field.selectAll()
        field.forwardDelete()
        XCTAssertEqual(field.text, "")
    }

    func testForwardDeleteRemovesASelectionInsteadOfOneCharacter() throws {
        let field = Field("kyoto trip")
        field.selectWithMouse(NSRange(location: 0, length: 6))
        field.forwardDelete()
        XCTAssertEqual(field.text, "trip")
    }

    // MARK: - F. Word and line deletes

    func testOptionBackspaceDeletesThePreviousWord() throws {
        let field = Field("kyoto trip")
        field.optionBackspace()
        XCTAssertEqual(field.text, "kyoto ")
    }

    func testOptionBackspaceTwiceDeletesBothWords() throws {
        let field = Field("kyoto trip")
        field.optionBackspace()
        field.optionBackspace()
        XCTAssertEqual(field.text, "")
    }

    func testOptionBackspaceOnASelectionDeletesJustTheSelection() throws {
        let field = Field("kyoto trip")
        field.selectWithMouse(NSRange(location: 6, length: 4))
        field.optionBackspace()
        XCTAssertEqual(field.text, "kyoto ")
    }

    func testOptionBackspaceAfterSelectAllClearsTheField() throws {
        let field = Field("kyoto trip")
        field.selectAll()
        field.optionBackspace()
        XCTAssertEqual(field.text, "")
    }

    func testOptionForwardDeleteRemovesTheNextWord() throws {
        let field = Field("kyoto trip")
        field.clickWithMouse(at: 0)
        field.optionForwardDelete()
        XCTAssertEqual(field.text, " trip")
    }

    func testCommandBackspaceClearsEverythingBeforeTheCaret() throws {
        let field = Field("kyoto trip")
        field.commandBackspace()
        XCTAssertEqual(field.text, "")
        XCTAssertEqual(field.caret, 0)
    }

    func testCommandBackspaceMidTextKeepsWhatIsAfterTheCaret() throws {
        let field = Field("kyoto trip")
        field.clickWithMouse(at: 6)
        field.commandBackspace()
        XCTAssertEqual(field.text, "trip")
    }

    // MARK: - G. ⌘A

    func testSelectAllSelectsTheWholeField() throws {
        let field = Field("chrome")
        field.selectAll()
        XCTAssertEqual(field.selection, NSRange(location: 0, length: 6))
    }

    /// ⌘A arrives as a key-down and is routed to the field like any other: it must survive the routing.
    func testSelectAllSurvivesWhenTheFieldOnlyJustTookTheCaret() throws {
        let field = Field("chrome")
        field.loseTheCaret()
        field.selectAll()
        XCTAssertEqual(field.selectedText, "chrome")
    }

    /// Retyping a query from scratch: the whole point of the selection.
    func testTypingAfterSelectAllReplacesTheWholeQuery() throws {
        let field = Field("chrome")
        field.selectAll()
        field.type("f")
        XCTAssertEqual(field.text, "f")
    }

    func testSelectAllOnAnEmptyFieldSelectsNothing() throws {
        let field = Field()
        field.selectAll()
        field.backspace()
        XCTAssertEqual(field.text, "")
    }

    /// The user changes their mind after ⌘A and clicks in the text: the selection collapses to a caret,
    /// and the next Delete is a one-character delete again.
    func testClickingAfterSelectAllGoesBackToASingleCharacterDelete() throws {
        let field = Field("chrome")
        field.selectAll()
        field.clickWithMouse(at: 6)
        field.backspace()
        XCTAssertEqual(field.text, "chrom")
    }

    func testSelectAllThenSelectAllAgainIsStillTheWholeField() throws {
        let field = Field("chrome")
        field.selectAll()
        field.selectAll()
        field.backspace()
        XCTAssertEqual(field.text, "")
    }

    // MARK: - H. Caret movement keys

    func testHomeMovesTheCaretToTheStart() throws {
        let field = Field("chrome")
        field.home()
        field.type("X")
        XCTAssertEqual(field.text, "Xchrome")
    }

    func testEndMovesTheCaretBackToTheEnd() throws {
        let field = Field("chrome")
        field.clickWithMouse(at: 0)
        field.end()
        field.type("X")
        XCTAssertEqual(field.text, "chromeX")
    }

    func testHomeCollapsesASelection() throws {
        let field = Field("chrome")
        field.selectAll()
        field.home()
        field.backspace()
        XCTAssertEqual(field.text, "chrome")
    }

    // MARK: - I. Paste

    func testPasteOverASelectionReplacesIt() throws {
        let field = Field("chrome")
        field.selectAll()
        field.paste("kyoto")
        XCTAssertEqual(field.text, "kyoto")
    }

    func testPasteAtTheCaretInsertsWithoutLosingText() throws {
        let field = Field("chrome")
        field.clickWithMouse(at: 6)
        field.paste(" tabs")
        XCTAssertEqual(field.text, "chrome tabs")
    }

    // MARK: - J. Non-ASCII text

    func testBackspaceDeletesAWholeEmoji() throws {
        let field = Field("kyoto 🍜")
        field.backspace()
        XCTAssertEqual(field.text, "kyoto ")
    }

    func testBackspaceDeletesAWholeZwjSequence() throws {
        let field = Field("a👨‍👩‍👧")
        field.backspace()
        XCTAssertEqual(field.text, "a")
    }

    func testBackspaceDeletesAComposedAccentAsOneCharacter() throws {
        let field = Field("cafe\u{0301}")
        field.backspace()
        XCTAssertEqual(field.text, "caf")
    }

    func testBackspaceDeletesOneCjkCharacter() throws {
        let field = Field("京都")
        field.backspace()
        XCTAssertEqual(field.text, "京")
    }

    /// Emoji are two UTF-16 units, and `selectedRange` counts UTF-16 units — so the caret after
    /// AppKit's focus hand-off has to be placed in those units, not in characters.
    func testCaretAfterFocusLandsAtTheEndOfNonAsciiText() throws {
        let field = Field("🍜🍜")
        field.loseTheCaret()
        field.type("a")
        XCTAssertEqual(field.text, "🍜🍜a")
    }

    func testSelectAllThenBackspaceClearsNonAsciiText() throws {
        let field = Field("京都 🍜")
        field.selectAll()
        field.backspace()
        XCTAssertEqual(field.text, "")
    }

    // MARK: - K. Longer sessions

    /// A whole search, typed, corrected, retyped: the sequence a user actually performs.
    func testTypeCorrectSelectAllAndRetype() throws {
        let field = Field()
        field.loseTheCaret()
        field.type("chr")
        field.type("o")
        field.backspace()
        field.type("ome")
        XCTAssertEqual(field.text, "chrome")
        field.selectAll()
        field.type("kyoto")
        XCTAssertEqual(field.text, "kyoto")
        field.selectAll()
        field.backspace()
        XCTAssertEqual(field.text, "")
        field.type("f")
        XCTAssertEqual(field.text, "f")
    }

    /// Losing the caret mid-session (a tile takes it back) and typing again resumes at the end.
    func testTypingResumesAtTheEndAfterTheCaretIsLost() throws {
        let field = Field()
        field.type("kyo")
        field.loseTheCaret()
        field.type("to")
        XCTAssertEqual(field.text, "kyoto")
        XCTAssertEqual(field.caretTakenCount, 1)
    }
}
