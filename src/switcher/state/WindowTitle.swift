import Foundation

/// A window title is whatever the app put in `kAXTitle`, and some apps put SEVERAL LINES in there:
/// Telegram titles its window with the start of the channel post on screen, Warp with the command it is
/// asking about. AppKit then measures that string as a paragraph — `NSCell.cellSize.height` is one font
/// line height per line — while the whole switcher treats a title as one line. One such window was enough
/// to make every tile in the grid two or three line-heights taller and push the thumbnails down inside
/// them (#6010).
///
/// Flattening where the model records a title keeps every consumer (layout, search ranges, tooltips,
/// VoiceOver) on the single-line assumption they all already make.
enum WindowTitle {
    /// Every scalar AppKit lays out as the start of a new line: LF, VT, FF, CR, NEL (U+0085), and the
    /// Unicode line/paragraph separators (U+2028/U+2029). `CharacterSet.newlines` is the same set, but a
    /// scalar-by-scalar `contains` on it is a bridged call per character, on a path that runs for every
    /// title of every window on every AX update.
    private static func isLineBreak(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
            case 0x0A...0x0D, 0x85, 0x2028, 0x2029: return true
            default: return false
        }
    }

    private static func isHorizontalSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t"
    }

    /// The title as one line: each run of line breaks becomes a single space, and the indentation around
    /// it is dropped, so a wrapped post or a pasted script reads as a sentence rather than as a column of
    /// gaps. Leading and trailing breaks produce no space at all.
    ///
    /// Returns the argument untouched when there is nothing to flatten, which is every title of every
    /// ordinary app.
    static func singleLine(_ raw: String) -> String {
        guard raw.unicodeScalars.contains(where: isLineBreak) else { return raw }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(raw.unicodeScalars.count)
        var pendingSeparator = false
        for scalar in raw.unicodeScalars {
            if isLineBreak(scalar) {
                while let last = out.last, isHorizontalSpace(last) { out.removeLast() }
                pendingSeparator = !out.isEmpty
                continue
            }
            if pendingSeparator {
                if isHorizontalSpace(scalar) { continue }
                out.append(" ")
                pendingSeparator = false
            }
            out.append(scalar)
        }
        return String(out)
    }
}
