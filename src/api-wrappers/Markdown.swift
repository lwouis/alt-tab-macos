import Cocoa

class Markdown {
    private static let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 15)
    ]
    private static let listItemParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.firstLineHeadIndent = 20
        return style
    }()
    private static let listItemAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .paragraphStyle: listItemParagraphStyle
    ]
    private static let boldAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 13)
    ]
    private static let linkAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor.blue,
        .underlineStyle: NSUnderlineStyle.single.rawValue
    ]
    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor.labelColor,
    ]
    private static let linkRegex = try! NSRegularExpression(pattern: "\\[(.*?)\\]\\((.*?)\\)")
    private static let boldRegex = try! NSRegularExpression(pattern: "\\*\\*(.*?)\\*\\*")

    static func toAttributedString(_ markdown: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString()
        for line in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let processedLine = NSMutableAttributedString(string: String(line) + "\n", attributes: baseAttributes)
            // links
            let linkMatches = linkRegex.matches(in: processedLine.string, range: NSRange(location: 0, length: processedLine.string.utf16.count))
            for match in linkMatches.reversed() {
                let linkTextRange = match.range(at: 1)
                let linkURLRange = match.range(at: 2)
                let linkText = processedLine.attributedSubstring(from: linkTextRange).string
                let linkURL = processedLine.attributedSubstring(from: linkURLRange).string
                processedLine.replaceCharacters(in: match.range, with: linkText)
                processedLine.addAttributes(linkAttributes, range: NSRange(location: match.range.location, length: linkText.utf16.count))
                processedLine.addAttribute(.link, value: linkURL, range: NSRange(location: match.range.location, length: linkText.utf16.count))
            }
            // titles
            let titlePattern = "## "
            if processedLine.string.starts(with: titlePattern) {
                processedLine.replaceCharacters(in: NSRange(location: 0, length: titlePattern.count), with: "")
                processedLine.addAttributes(titleAttributes, range: NSRange(location: 0, length: processedLine.length - 1)) // Exclude the newline
                attributedString.append(processedLine)
                continue
            }
            // bold
            let boldMatches = boldRegex.matches(in: processedLine.string, range: NSRange(location: 0, length: processedLine.string.utf16.count))
            for match in boldMatches.reversed() {
                let boldTextRange = match.range(at: 1)
                let boldText = processedLine.attributedSubstring(from: boldTextRange).string
                processedLine.replaceCharacters(in: match.range, with: boldText)
                processedLine.addAttributes(boldAttributes, range: NSRange(location: match.range.location, length: boldText.utf16.count))
            }
            // list items
            let listPattern = "*"
            if processedLine.string.trimmingCharacters(in: .whitespaces).starts(with: listPattern) {
                processedLine.replaceCharacters(in: NSRange(location: 0, length: listPattern.count), with: "•")
                processedLine.addAttributes(listItemAttributes, range: NSRange(location: 0, length: processedLine.length - 1))
            }
            attributedString.append(processedLine)
        }
        return attributedString
    }
}
