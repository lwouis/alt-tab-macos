import Cocoa

/// Lays an email address out over a few short lines, for the sidebar upgrade pill.
///
/// AppKit can't do this on its own: `NSButtonCell` wraps or truncates, never both, and its wrapping
/// breaks mid-word because an email has no spaces.
enum EmailLineWrap {
    struct Result {
        let lines: [String]
        /// The address didn't fit in `maxLines`, so the last line ends in an ellipsis.
        let isTruncated: Bool
    }

    private static let separators = Set<Character>("@.-_+")
    /// A pull-back to a separator is only worth it when the line it leaves is still mostly full.
    /// The `@` gets a lower bar than the rest: `local@` / `domain.tld` is how an address reads.
    private static let atFillRatio = CGFloat(0.45)
    private static let separatorFillRatio = CGFloat(0.55)

    static func wrap(_ email: String, font: NSFont, maxWidth: CGFloat, maxLines: Int) -> Result {
        guard !email.isEmpty, maxWidth > 0, maxLines > 0 else { return Result(lines: [], isTruncated: !email.isEmpty) }
        var lines = [String]()
        var rest = Substring(email)
        while !rest.isEmpty && lines.count < maxLines {
            guard width(rest, font) > maxWidth else {
                lines.append(String(rest))
                rest = ""
                break
            }
            let cut = breakIndex(rest, font, maxWidth)
            lines.append(String(rest[..<cut]))
            rest = rest[cut...]
        }
        guard !rest.isEmpty, let last = lines.last else { return Result(lines: lines, isTruncated: false) }
        lines[lines.count - 1] = ellipsized(last, font, maxWidth)
        return Result(lines: lines, isTruncated: true)
    }

    /// Shrinks the font by half-points, down to `minSize`, when that saves a whole line, and keeps
    /// the base size otherwise. Without it a medium address like `john@cool-software.com` falls a
    /// couple of points short and drops a lonely `com` onto a second line.
    static func fittedFont(_ email: String, baseFont: NSFont, maxWidth: CGFloat, minSize: CGFloat, maxLines: Int) -> NSFont {
        let baseLineCount = wrap(email, font: baseFont, maxWidth: maxWidth, maxLines: maxLines).lines.count
        var size = baseFont.pointSize - 0.5
        while size >= minSize {
            let font = NSFont(descriptor: baseFont.fontDescriptor, size: size) ?? baseFont
            if wrap(email, font: font, maxWidth: maxWidth, maxLines: maxLines).lines.count < baseLineCount {
                return font
            }
            size -= 0.5
        }
        return baseFont
    }

    /// Where to end a line: the longest prefix that fits, pulled back to just after a separator when
    /// one is close enough to the end. Breaking anywhere else cuts a word in half
    /// (`christopher.vandenbe` / `rghe@universiteit-am`).
    private static func breakIndex(_ text: Substring, _ font: NSFont, _ maxWidth: CGFloat) -> String.Index {
        let end = longestFittingPrefix(text, font, maxWidth)
        if let at = text.firstIndex(of: "@"), at < end {
            let afterAt = text.index(after: at)
            if width(text[..<afterAt], font) >= maxWidth * atFillRatio { return afterAt }
        }
        var i = text.index(before: end)
        while i > text.startIndex {
            if separators.contains(text[i]) {
                let afterSeparator = text.index(after: i)
                return width(text[..<afterSeparator], font) >= maxWidth * separatorFillRatio ? afterSeparator : end
            }
            i = text.index(before: i)
        }
        return end
    }

    /// Always past `startIndex`, so a width too narrow for even one character still makes progress.
    private static func longestFittingPrefix(_ text: Substring, _ font: NSFont, _ maxWidth: CGFloat) -> String.Index {
        var end = text.index(after: text.startIndex)
        var i = end
        while i < text.endIndex {
            let next = text.index(after: i)
            guard width(text[..<next], font) <= maxWidth else { break }
            end = next
            i = next
        }
        return end
    }

    private static func ellipsized(_ line: String, _ font: NSFont, _ maxWidth: CGFloat) -> String {
        var line = line
        while !line.isEmpty && width(Substring(line + "…"), font) > maxWidth {
            line.removeLast()
        }
        return line + "…"
    }

    private static func width(_ text: Substring, _ font: NSFont) -> CGFloat {
        (String(text) as NSString).size(withAttributes: [.font: font]).width
    }
}
