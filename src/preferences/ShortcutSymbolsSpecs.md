# Shortcut symbols

ShortcutRecorder must parse each modifier glyph into its own modifier flag, including
modifier-only hold shortcuts. Special-key glyphs must retain their distinct key codes.
These contracts apply to both Intel and Apple silicon builds; a test run on one
architecture does not verify the other.

`ShortcutSymbolsTests` exercises the linked library with Swift string inputs. In #6138,
the Xcode 27.1 Intel linker corrupted the library's Objective-C UTF-16 literals after
relocatable linking. A default Option hold shortcut then had no modifier flags, so Tab
and backtick were registered as global shortcuts without Option.
