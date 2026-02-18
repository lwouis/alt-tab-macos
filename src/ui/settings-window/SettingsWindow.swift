import Cocoa

private struct SettingsSearchToken {
    let normalized: [Character]
    let normalizedToOriginal: [Int]
}

private struct SettingsSearchResult {
    let score: Double
    let ranges: [Range<Int>]
}

private enum SettingsSearch {
    private struct TokenMatch {
        let score: Double
        let ranges: [Range<Int>]
    }

    static func isQueryEmpty(_ query: String) -> Bool {
        tokens(query).flatMap { $0.normalized }.isEmpty
    }

    static func match(_ query: String, in text: String) -> SettingsSearchResult? {
        let mergeAcrossSeparators = hasInterTermSeparator(query)
        let queryTokens = tokens(query).map(\.normalized)
        guard !queryTokens.isEmpty else { return nil }
        let textTokens = tokens(text)
        guard !textTokens.isEmpty else { return nil }
        var tokenScores = [Double]()
        var matchedRanges = [Range<Int>]()
        for queryToken in queryTokens {
            guard let bestMatch = bestMatch(for: queryToken, in: textTokens) else { return nil }
            tokenScores.append(bestMatch.score)
            matchedRanges.append(contentsOf: bestMatch.ranges)
        }
        let averageScore = tokenScores.reduce(0, +) / Double(tokenScores.count)
        guard averageScore >= minimumScore(queryTokens.map { $0.count }.max() ?? 0) else { return nil }
        if mergeAcrossSeparators && matchedRanges.count > 1 {
            return SettingsSearchResult(score: averageScore, ranges: mergeRangesAcrossSeparators(matchedRanges, in: Array(text)))
        }
        return SettingsSearchResult(score: averageScore, ranges: mergeRanges(matchedRanges))
    }

    private static func bestMatch(for queryToken: [Character], in textTokens: [SettingsSearchToken]) -> TokenMatch? {
        var best: TokenMatch?
        textTokens.forEach { token in
            guard let candidate = scoreTokenMatch(queryToken, token) else { return }
            if best == nil || candidate.score > best!.score {
                best = candidate
            }
        }
        return best
    }

    private static func scoreTokenMatch(_ query: [Character], _ token: SettingsSearchToken) -> TokenMatch? {
        let tokenChars = token.normalized
        let queryLength = query.count
        let tokenLength = tokenChars.count
        guard queryLength > 0, tokenLength > 0 else { return nil }
        if queryLength <= 2 {
            guard let exactRange = firstExactRange(of: query, in: tokenChars) else { return nil }
            return TokenMatch(score: 1, ranges: [originalRange(from: exactRange, using: token)])
        }
        let maxLength = max(queryLength, tokenLength)
        let minLength = min(queryLength, tokenLength)
        let distance = damerauLevenshteinDistance(query, tokenChars)
        let distanceScore = 1 - Double(distance) / Double(maxLength)
        let prefixLength = commonPrefixLength(query, tokenChars)
        let prefixScore = Double(prefixLength) / Double(minLength)
        let lcsIndexes = lcsTokenIndexes(query, tokenChars)
        let coverageScore = Double(lcsIndexes.count) / Double(queryLength)
        var score = distanceScore * 0.64 + prefixScore * 0.23 + coverageScore * 0.13
        if tokenChars.starts(with: query) {
            score = max(score, 0.92 - Double(max(0, tokenLength - queryLength)) * 0.015)
        }
        if let exactRange = firstExactRange(of: query, in: tokenChars) {
            score = max(score, 0.86 - Double(max(0, tokenLength - queryLength)) * 0.01)
            guard score >= minimumScore(queryLength) else { return nil }
            return TokenMatch(score: score, ranges: [originalRange(from: exactRange, using: token)])
        }
        guard lcsIndexes.count >= minimumLcsLength(queryLength) else { return nil }
        guard score >= minimumScore(queryLength) else { return nil }
        let ranges = originalRanges(from: lcsIndexes, using: token)
        guard !ranges.isEmpty else { return nil }
        return TokenMatch(score: score, ranges: ranges)
    }

    private static func minimumScore(_ queryLength: Int) -> Double {
        switch queryLength {
        case 0...2: return 1
        case 3: return 0.74
        case 4: return 0.68
        case 5: return 0.64
        case 6...7: return 0.60
        default: return 0.56
        }
    }

    private static func minimumLcsLength(_ queryLength: Int) -> Int {
        if queryLength <= 2 { return queryLength }
        if queryLength == 3 { return 2 }
        if queryLength <= 5 { return Int(ceil(Double(queryLength) * 0.6)) }
        return Int(ceil(Double(queryLength) * 0.55))
    }

    private static func mergeRanges(_ ranges: [Range<Int>]) -> [Range<Int>] {
        mergeRanges(ranges) { _, _ in false }
    }

    private static func mergeRangesAcrossSeparators(_ ranges: [Range<Int>], in textCharacters: [Character]) -> [Range<Int>] {
        mergeRanges(ranges) {
            onlySeparatorsBetween($0, $1, in: textCharacters)
        }
    }

    private static func mergeRanges(_ ranges: [Range<Int>], _ shouldMergeGap: (Int, Int) -> Bool) -> [Range<Int>] {
        if ranges.isEmpty { return [] }
        let sorted = ranges.sorted {
            if $0.lowerBound == $1.lowerBound {
                return $0.upperBound < $1.upperBound
            }
            return $0.lowerBound < $1.lowerBound
        }
        var merged = [sorted[0]]
        sorted.dropFirst().forEach { range in
            let lastIndex = merged.count - 1
            let lastRange = merged[lastIndex]
            if range.lowerBound <= lastRange.upperBound || shouldMergeGap(lastRange.upperBound, range.lowerBound) {
                merged[lastIndex] = lastRange.lowerBound..<max(lastRange.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    private static func onlySeparatorsBetween(_ start: Int, _ end: Int, in textCharacters: [Character]) -> Bool {
        guard start < end else { return true }
        guard start >= 0, end <= textCharacters.count else { return false }
        for index in start..<end {
            if !normalizedCharacters(textCharacters[index]).isEmpty { return false }
        }
        return true
    }

    private static func firstExactRange(of query: [Character], in token: [Character]) -> Range<Int>? {
        if query.isEmpty || query.count > token.count { return nil }
        for start in 0...(token.count - query.count) {
            if Array(token[start..<(start + query.count)]) == query {
                return start..<(start + query.count)
            }
        }
        return nil
    }

    private static func commonPrefixLength(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let commonLength = min(lhs.count, rhs.count)
        if commonLength == 0 { return 0 }
        for i in 0..<commonLength where lhs[i] != rhs[i] {
            return i
        }
        return commonLength
    }

    private static func damerauLevenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let n = lhs.count
        let m = rhs.count
        if n == 0 { return m }
        if m == 0 { return n }
        var matrix = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { matrix[i][0] = i }
        for j in 0...m { matrix[0][j] = j }
        if n == 0 || m == 0 { return matrix[n][m] }
        for i in 1...n {
            for j in 1...m {
                let cost = lhs[i - 1] == rhs[j - 1] ? 0 : 1
                let deletion = matrix[i - 1][j] + 1
                let insertion = matrix[i][j - 1] + 1
                let substitution = matrix[i - 1][j - 1] + cost
                var value = min(deletion, insertion, substitution)
                if i > 1, j > 1, lhs[i - 1] == rhs[j - 2], lhs[i - 2] == rhs[j - 1] {
                    value = min(value, matrix[i - 2][j - 2] + 1)
                }
                matrix[i][j] = value
            }
        }
        return matrix[n][m]
    }

    private static func lcsTokenIndexes(_ query: [Character], _ token: [Character]) -> [Int] {
        let n = query.count
        let m = token.count
        if n == 0 || m == 0 { return [] }
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                if query[i] == token[j] {
                    dp[i][j] = 1 + dp[i + 1][j + 1]
                } else {
                    dp[i][j] = max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var i = 0
        var j = 0
        var matchedIndexes = [Int]()
        while i < n && j < m {
            if query[i] == token[j] {
                matchedIndexes.append(j)
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return matchedIndexes
    }

    private static func originalRange(from normalizedRange: Range<Int>, using token: SettingsSearchToken) -> Range<Int> {
        let start = token.normalizedToOriginal[normalizedRange.lowerBound]
        let end = token.normalizedToOriginal[normalizedRange.upperBound - 1] + 1
        return start..<end
    }

    private static func originalRanges(from normalizedIndexes: [Int], using token: SettingsSearchToken) -> [Range<Int>] {
        if normalizedIndexes.isEmpty { return [] }
        var ranges = [Range<Int>]()
        var runStart = normalizedIndexes[0]
        var runEnd = normalizedIndexes[0]
        normalizedIndexes.dropFirst().forEach { index in
            if index == runEnd + 1 {
                runEnd = index
            } else {
                ranges.append(originalRange(from: runStart..<(runEnd + 1), using: token))
                runStart = index
                runEnd = index
            }
        }
        ranges.append(originalRange(from: runStart..<(runEnd + 1), using: token))
        return mergeRanges(ranges)
    }

    private static func tokens(_ text: String) -> [SettingsSearchToken] {
        let characters = Array(text)
        var tokens = [SettingsSearchToken]()
        var normalized = [Character]()
        var normalizedToOriginal = [Int]()
        func flushCurrentToken() {
            guard !normalized.isEmpty else { return }
            tokens.append(SettingsSearchToken(normalized: normalized, normalizedToOriginal: normalizedToOriginal))
            normalized.removeAll(keepingCapacity: true)
            normalizedToOriginal.removeAll(keepingCapacity: true)
        }
        for (originalIndex, character) in characters.enumerated() {
            let normalizedChars = normalizedCharacters(character)
            if normalizedChars.isEmpty {
                flushCurrentToken()
                continue
            }
            normalizedChars.forEach {
                normalized.append($0)
                normalizedToOriginal.append(originalIndex)
            }
        }
        flushCurrentToken()
        return tokens
    }

    private static func hasInterTermSeparator(_ query: String) -> Bool {
        var sawSearchCharacter = false
        var sawSeparatorAfterSearchCharacter = false
        for character in query {
            if normalizedCharacters(character).isEmpty {
                if sawSearchCharacter {
                    sawSeparatorAfterSearchCharacter = true
                }
                continue
            }
            if sawSearchCharacter && sawSeparatorAfterSearchCharacter {
                return true
            }
            sawSearchCharacter = true
            sawSeparatorAfterSearchCharacter = false
        }
        return false
    }

    private static func normalizedCharacters(_ character: Character) -> [Character] {
        let folded = String(character).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil).lowercased()
        var chars = [Character]()
        folded.unicodeScalars.forEach {
            if isSearchScalar($0) {
                chars.append(Character(String($0)))
            }
        }
        return chars
    }

    private static func isSearchScalar(_ scalar: UnicodeScalar) -> Bool {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) { return false }
        if CharacterSet.punctuationCharacters.contains(scalar) { return false }
        if CharacterSet.symbols.contains(scalar) { return false }
        return true
    }
}

private struct SettingsSectionDefinition {
    let id: String
    let title: String
    let imageName: String
    let systemSymbolName: String
    let view: NSView
}

private final class SettingsSearchHighlightTarget {
    private let matchRanges: (String) -> [Range<Int>]
    private let applyHighlight: ([Range<Int>]) -> Void
    private let clearHighlight: () -> Void

    init(_ matchRanges: @escaping (String) -> [Range<Int>], _ applyHighlight: @escaping ([Range<Int>]) -> Void, _ clearHighlight: @escaping () -> Void) {
        self.matchRanges = matchRanges
        self.applyHighlight = applyHighlight
        self.clearHighlight = clearHighlight
    }

    convenience init(_ hasMatch: @escaping (String) -> Bool, _ applyHighlight: @escaping () -> Void, _ clearHighlight: @escaping () -> Void) {
        self.init({ query in
            hasMatch(query) ? [0..<1] : []
        }, { _ in
            applyHighlight()
        }, clearHighlight)
    }

    func hasMatch(_ query: String) -> Bool {
        !matchRanges(query).isEmpty
    }

    func updateHighlight(_ query: String) {
        let ranges = matchRanges(query)
        if ranges.isEmpty {
            clearHighlight()
        } else {
            applyHighlight(ranges)
        }
    }

    func clear() {
        clearHighlight()
    }
}

private final class SettingsSection {
    let id: String
    let title: String
    let icon: NSImage
    let container: NSView
    let anchor: NSView
    let searchableStrings: [String]
    let highlightTargets: [SettingsSearchHighlightTarget]
    let interSectionSpacingConstraint: NSLayoutConstraint
    let bottomSpacingConstraint: NSLayoutConstraint
    let titleTopConstraint: NSLayoutConstraint

    init(_ id: String,
         _ title: String,
         _ icon: NSImage,
         _ container: NSView,
         _ anchor: NSView,
         _ searchableStrings: [String],
         _ highlightTargets: [SettingsSearchHighlightTarget],
         _ interSectionSpacingConstraint: NSLayoutConstraint,
         _ bottomSpacingConstraint: NSLayoutConstraint,
         _ titleTopConstraint: NSLayoutConstraint) {
        self.id = id
        self.title = title
        self.icon = icon
        self.container = container
        self.anchor = anchor
        self.searchableStrings = searchableStrings
        self.highlightTargets = highlightTargets
        self.interSectionSpacingConstraint = interSectionSpacingConstraint
        self.bottomSpacingConstraint = bottomSpacingConstraint
        self.titleTopConstraint = titleTopConstraint
    }

    func matches(_ query: String) -> Bool {
        if SettingsSearch.isQueryEmpty(query) { return true }
        if searchableStrings.contains(where: { SettingsSearch.match(query, in: $0) != nil }) { return true }
        return highlightTargets.contains { $0.hasMatch(query) }
    }

    func highlightMatches(_ query: String) {
        highlightTargets.forEach { $0.updateHighlight(query) }
    }

    func clearHighlights() {
        highlightTargets.forEach { $0.clear() }
    }
}

private final class SettingsSidebarCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier(rawValue: "SettingsSidebarCell")
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { refreshStyle() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("Class only supports programmatic initialization")
    }

    private func setupView() {
        iconView.imageScaling = .scaleProportionallyDown
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshStyle()
    }

    func configure(_ section: SettingsSection) {
        titleLabel.stringValue = section.title
        iconView.image = section.icon
        iconView.image?.isTemplate = true
        refreshStyle()
    }

    private func refreshStyle() {
        let selected = backgroundStyle == .emphasized
        titleLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .medium)
        titleLabel.textColor = selected ? .white : .labelColor
        if #available(macOS 10.14, *) {
            iconView.contentTintColor = selected ? .white : .secondaryLabelColor
        }
    }
}

class SettingsWindow: NSWindow {
    static let contentWidth = CGFloat(620)
    static let width = contentWidth
    static let sidebarActionButtonHeight: CGFloat = {
        let button = NSButton(title: " ", target: nil, action: nil)
        button.bezelStyle = .rounded
        return button.fittingSize.height
    }()
    private static let sidebarWidth = CGFloat(210)
    private static let contentHorizontalPadding = CGFloat(20)
    private static let contentTopPadding = CGFloat(0)
    private static let topSectionTitlePadding = CGFloat(20)
    private static let contentBottomPadding = CGFloat(20)
    private static let sectionTitleSpacing = CGFloat(-5)
    private static let sectionInterSectionSpacing = CGFloat(15)
    private static let sectionBottomSpacing = CGFloat(30) - sectionInterSectionSpacing
    private static let sectionScrollTopPadding = CGFloat(20)
    private static let minWindowHeight = CGFloat(500)
    private static let sidebarTopInset = CGFloat(40)
    private static let sidebarHorizontalPadding = CGFloat(10)
    private static let roundedHighlightLayerName = "settingsSearchRoundedHighlight"
    private static let roundedHighlightCornerRadius = CGFloat(4)
    private static let roundedHighlightHorizontalInset = CGFloat(1.5)
    private static let roundedHighlightVerticalInset = CGFloat(0.8)
    private static let roundedHighlightLeadingTrim = CGFloat(1.4)
    private static let controlHighlightLayerName = "settingsSearchControlHighlight"
    private static let segmentedControlHighlightLayerName = "settingsSearchSegmentHighlight"
    private static let controlHighlightInset = CGFloat(1)
    private static let controlHighlightMinCornerRadius = CGFloat(4)
    private static let controlHighlightMaxCornerRadius = CGFloat(9)

    var canBecomeKey_ = true
    override var canBecomeKey: Bool { canBecomeKey_ }

    private let splitViewController = NSSplitViewController()
    private let sidebarContainer = NSView()
    private let contentContainer = NSView()
    private let searchField = NSSearchField(frame: .zero)
    private let sidebarScrollView = NSScrollView()
    private let sidebarTableView = NSTableView()
    private let rightScrollView = NSScrollView()
    private let sectionsDocumentView = FlippedView(frame: .zero)
    private let sectionsStack = NSStackView()
    private let supportButton = AboutTab.makeSupportProjectButton()
    private let resetButton = NSButton(title: NSLocalizedString("Reset settings and restart…", comment: ""), target: nil, action: nil)
    private let quitButton = NSButton(title: String(format: NSLocalizedString("Quit %@", comment: "%@ is AltTab"), App.name), target: nil, action: #selector(NSApplication.terminate(_:)))
    private var sections = [SettingsSection]()
    private var visibleSections = [SettingsSection]()
    private var selectedSectionId: String?
    private var sheetHighlightTargets = [ObjectIdentifier: [SettingsSearchHighlightTarget]]()
    private var liveResizeOriginX: CGFloat?

    convenience init() {
        let windowWidth = Self.sidebarWidth + Self.contentWidth + 3 * Self.contentHorizontalPadding
        self.init(contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: 605),
                  styleMask: [.titled, .miniaturizable, .closable, .resizable, .fullSizeContentView],
                  backing: .buffered, defer: false)
        minSize = NSSize(width: windowWidth, height: Self.minWindowHeight)
        maxSize = NSSize(width: windowWidth, height: CGFloat.greatestFiniteMagnitude)
        setupWindow()
        setupView()
        setFrameAutosaveName("SettingsWindow")
    }

    private func setupWindow() {
        delegate = self
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        if #available(macOS 11.0, *) {
            toolbarStyle = .unified
            titlebarSeparatorStyle = .none
        }
    }

    private func setupView() {
        setupSplitView()
        setupSidebar()
        setupContentPane()
        sectionDefinitions().forEach { addSection($0) }
        refreshControlsFromSettings()
        applySearch("")
    }

    private func setupSplitView() {
        let sidebarVC = NSViewController()
        sidebarVC.view = sidebarContainer
        let contentVC = NSViewController()
        contentVC.view = contentContainer
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = Self.sidebarWidth
        sidebarItem.maximumThickness = Self.sidebarWidth
        let contentItem = NSSplitViewItem(viewController: contentVC)
        splitViewController.splitViewItems = [sidebarItem, contentItem]
        splitViewController.splitView.dividerStyle = .thin
        contentViewController = splitViewController
    }

    private func setupSidebar() {
        setupSearchField(sidebarContainer)
        setupQuitButton(sidebarContainer)
        setupResetButton(sidebarContainer)
        setupSupportButton(sidebarContainer)
        setupSidebarTable(sidebarContainer)
    }

    private func setupContentPane() {
        rightScrollView.drawsBackground = false
        rightScrollView.hasVerticalScroller = true
        rightScrollView.hasHorizontalScroller = false
        rightScrollView.scrollerStyle = .overlay
        if #available(macOS 11.0, *) {
            rightScrollView.automaticallyAdjustsContentInsets = false
        }
        rightScrollView.contentInsets = NSEdgeInsetsZero
        rightScrollView.scrollerInsets = NSEdgeInsetsZero
        rightScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(rightScrollView)
        sectionsDocumentView.translatesAutoresizingMaskIntoConstraints = false
        rightScrollView.documentView = sectionsDocumentView
        sectionsStack.orientation = .vertical
        sectionsStack.spacing = 0
        sectionsStack.alignment = .leading
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        sectionsDocumentView.addSubview(sectionsStack)
        NSLayoutConstraint.activate([
            rightScrollView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            rightScrollView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            rightScrollView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            rightScrollView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
            sectionsStack.topAnchor.constraint(equalTo: sectionsDocumentView.topAnchor, constant: Self.contentTopPadding),
            sectionsStack.leadingAnchor.constraint(equalTo: sectionsDocumentView.leadingAnchor, constant: Self.contentHorizontalPadding),
            sectionsStack.trailingAnchor.constraint(equalTo: sectionsDocumentView.trailingAnchor, constant: -Self.contentHorizontalPadding),
            sectionsStack.bottomAnchor.constraint(equalTo: sectionsDocumentView.bottomAnchor, constant: -Self.contentBottomPadding),
            sectionsDocumentView.widthAnchor.constraint(equalTo: rightScrollView.contentView.widthAnchor),
        ])
    }

    private func setupSearchField(_ parent: NSView) {
        searchField.delegate = self
        searchField.placeholderString = NSLocalizedString("Search", comment: "")
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = true
        searchField.bezelStyle = .roundedBezel
        if #available(macOS 26.0, *) {
            searchField.controlSize = .extraLarge
        } else if #available(macOS 13.0, *) {
            searchField.controlSize = .large
        }
        searchField.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(searchField)
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: parent.topAnchor, constant: Self.sidebarTopInset),
            searchField.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: Self.sidebarHorizontalPadding),
            searchField.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -Self.sidebarHorizontalPadding),
        ])
    }

    private func setupSidebarTable(_ parent: NSView) {
        sidebarScrollView.drawsBackground = false
        sidebarScrollView.hasVerticalScroller = true
        sidebarScrollView.hasHorizontalScroller = false
        sidebarScrollView.scrollerStyle = .overlay
        sidebarTableView.headerView = nil
        sidebarTableView.intercellSpacing = NSSize(width: 0, height: 2)
        sidebarTableView.rowHeight = 30
        sidebarTableView.selectionHighlightStyle = .sourceList
        sidebarTableView.backgroundColor = .clear
        sidebarTableView.focusRingType = .none
        sidebarTableView.usesAlternatingRowBackgroundColors = false
        if #available(macOS 11.0, *) {
            sidebarTableView.style = .sourceList
        }
        sidebarTableView.delegate = self
        sidebarTableView.dataSource = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "SettingsSidebarColumn"))
        column.resizingMask = .autoresizingMask
        sidebarTableView.addTableColumn(column)
        sidebarScrollView.documentView = sidebarTableView
        sidebarScrollView.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(sidebarScrollView)
        NSLayoutConstraint.activate([
            sidebarScrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            sidebarScrollView.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: Self.sidebarHorizontalPadding - 2),
            sidebarScrollView.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -(Self.sidebarHorizontalPadding - 2)),
            sidebarScrollView.bottomAnchor.constraint(equalTo: supportButton.topAnchor, constant: -10),
        ])
    }

    private func setupSupportButton(_ parent: NSView) {
        supportButton.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(supportButton)
        NSLayoutConstraint.activate([
            supportButton.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            supportButton.bottomAnchor.constraint(equalTo: resetButton.topAnchor, constant: -20),
        ])
    }

    @objc private func resetPreferences() {
        GeneralTab.resetPreferences()
    }

    private func setupResetButton(_ parent: NSView) {
        resetButton.bezelStyle = .rounded
        if #available(macOS 11.0, *) { resetButton.hasDestructiveAction = true }
        resetButton.target = self
        resetButton.action = #selector(resetPreferences)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(resetButton)
        NSLayoutConstraint.activate([
            resetButton.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            resetButton.bottomAnchor.constraint(equalTo: quitButton.topAnchor, constant: -20),
            resetButton.heightAnchor.constraint(equalToConstant: Self.sidebarActionButtonHeight),
        ])
    }

    private func setupQuitButton(_ parent: NSView) {
        quitButton.bezelStyle = .rounded
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(quitButton)
        NSLayoutConstraint.activate([
            quitButton.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            quitButton.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -10),
            quitButton.heightAnchor.constraint(equalToConstant: Self.sidebarActionButtonHeight),
        ])
    }

    private func sectionDefinitions() -> [SettingsSectionDefinition] {
        [
            SettingsSectionDefinition(id: "appearance", title: NSLocalizedString("Appearance", comment: ""), imageName: "appearance", systemSymbolName: "paintpalette", view: AppearanceTab.initTab()),
            SettingsSectionDefinition(id: "controls", title: NSLocalizedString("Controls", comment: ""), imageName: "controls", systemSymbolName: "command", view: ControlsTab.initTab()),
            SettingsSectionDefinition(id: "general", title: NSLocalizedString("General", comment: ""), imageName: "general", systemSymbolName: "gearshape", view: GeneralTab.initTab()),
            SettingsSectionDefinition(id: "policies", title: NSLocalizedString("Policies", comment: ""), imageName: "policies", systemSymbolName: "antenna.radiowaves.left.and.right", view: PoliciesTab.initTab()),
            SettingsSectionDefinition(id: "blacklists", title: NSLocalizedString("Blacklists", comment: ""), imageName: "blacklists", systemSymbolName: "hand.raised", view: BlacklistsTab.initTab()),
        ]
    }

    private func sidebarImage(_ definition: SettingsSectionDefinition) -> NSImage {
        if #available(macOS 11.0, *), let image = NSImage(systemSymbolName: definition.systemSymbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            return configured
        }
        let image = NSImage.initCopy(definition.imageName)
        image.isTemplate = true
        return image
    }

    private func addSection(_ definition: SettingsSectionDefinition) {
        let sectionTitle = TableGroupView.makeText(definition.title, bold: true)
        sectionTitle.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        sectionTitle.lineBreakMode = .byWordWrapping
        sectionTitle.maximumNumberOfLines = 0
        let container = NSView()
        let spacer = NSView()
        container.addSubview(sectionTitle)
        container.addSubview(definition.view)
        container.addSubview(spacer)
        sectionTitle.translatesAutoresizingMaskIntoConstraints = false
        definition.view.translatesAutoresizingMaskIntoConstraints = false
        spacer.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        let titleTopConstraint = sectionTitle.topAnchor.constraint(equalTo: container.topAnchor)
        let interSectionSpacingConstraint = spacer.topAnchor.constraint(equalTo: definition.view.bottomAnchor, constant: Self.sectionInterSectionSpacing)
        let spacerHeightConstraint = spacer.heightAnchor.constraint(equalToConstant: Self.sectionBottomSpacing)
        NSLayoutConstraint.activate([
            titleTopConstraint,
            sectionTitle.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sectionTitle.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            definition.view.topAnchor.constraint(equalTo: sectionTitle.bottomAnchor, constant: Self.sectionTitleSpacing),
            definition.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            definition.view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            interSectionSpacingConstraint,
            spacer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            spacer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            spacer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            spacerHeightConstraint,
        ])
        sectionsStack.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true
        let (searchableStrings, highlightTargets) = collectSearchContent(sectionTitle, definition.view)
        let section = SettingsSection(definition.id,
                                      definition.title,
                                      sidebarImage(definition),
                                      container,
                                      sectionTitle,
                                      searchableStrings,
                                      highlightTargets,
                                      interSectionSpacingConstraint,
                                      spacerHeightConstraint,
                                      titleTopConstraint)
        sections.append(section)
    }

    private func updateVisibleSectionsSpacing() {
        visibleSections.enumerated().forEach { index, section in
            let isFirst = index == 0
            let isLast = index == visibleSections.count - 1
            section.titleTopConstraint.constant = isFirst ? Self.topSectionTitlePadding : 0
            section.interSectionSpacingConstraint.constant = isLast ? 0 : Self.sectionInterSectionSpacing
            section.bottomSpacingConstraint.constant = isLast ? 0 : Self.sectionBottomSpacing
        }
    }

    private func collectSearchContent(_ sectionTitle: NSTextField, _ root: NSView) -> ([String], [SettingsSearchHighlightTarget]) {
        var textValues = [String]()
        var highlightTargets = [SettingsSearchHighlightTarget]()
        textValues.append(sectionTitle.stringValue)
        if let target = highlightTarget(sectionTitle) {
            highlightTargets.append(target)
        }
        collectSearchContent(root, &textValues, &highlightTargets)
        return (Array(Set(textValues)), highlightTargets)
    }

    private func collectSearchContent(_ root: NSView,
                                      _ textValues: inout [String],
                                      _ highlightTargets: inout [SettingsSearchHighlightTarget]) {
        if let textField = root as? NSTextField {
            let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
                if let target = highlightTarget(textField) {
                    highlightTargets.append(target)
                }
            }
        } else if let popUpButton = root as? NSPopUpButton {
            let value = popUpButton.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
            popUpButton.itemTitles.forEach {
                let value = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    textValues.append(value)
                }
            }
            if let target = highlightTarget(popUpButton) {
                highlightTargets.append(target)
            }
        } else if let tableView = root as? TableView {
            SettingsWindow.searchStrings(tableView).forEach {
                textValues.append($0)
            }
            if let target = highlightTarget(tableView) {
                highlightTargets.append(target)
            }
        } else if let button = root as? NSButton {
            let value = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
            if let target = highlightTarget(button) {
                highlightTargets.append(target)
            }
        } else if let segmentedControl = root as? NSSegmentedControl {
            (0..<segmentedControl.segmentCount).forEach {
                let value = (segmentedControl.label(forSegment: $0) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    textValues.append(value)
                }
            }
            if let target = highlightTarget(segmentedControl) {
                highlightTargets.append(target)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            SettingsWindow.searchStrings(infoButton).forEach {
                textValues.append($0)
            }
            if let target = highlightTarget(infoButton) {
                highlightTargets.append(target)
            }
        } else if let textView = root as? NSTextView {
            let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                textValues.append(value)
            }
        }
        root.subviews.forEach { collectSearchContent($0, &textValues, &highlightTargets) }
    }

    private func highlightTarget(_ textField: NSTextField) -> SettingsSearchHighlightTarget? {
        let text = textField.stringValue
        guard !text.isEmpty else { return nil }
        let baseAttributedString = textField.attributedStringValue
        return SettingsSearchHighlightTarget({ query in
            SettingsSearch.match(query, in: text)?.ranges ?? []
        }, { ranges in
            let mutable = NSMutableAttributedString(attributedString: baseAttributedString)
            let nsRanges = ranges.compactMap { SettingsWindow.characterRangeToNSRange($0, in: text) }
            nsRanges.forEach {
                mutable.addAttribute(.foregroundColor, value: Appearance.searchMatchForegroundColor, range: $0)
            }
            textField.attributedStringValue = mutable
            SettingsWindow.applyRoundedHighlights(to: textField, attributedString: mutable, ranges: nsRanges)
        }, {
            textField.attributedStringValue = baseAttributedString
            SettingsWindow.clearRoundedHighlights(from: textField)
        })
    }

    private func highlightTarget(_ popUpButton: NSPopUpButton) -> SettingsSearchHighlightTarget? {
        controlHighlightTarget(popUpButton) {
            SettingsWindow.searchStrings(popUpButton)
        }
    }

    private func highlightTarget(_ tableView: TableView) -> SettingsSearchHighlightTarget? {
        let targetView = tableView.enclosingScrollView ?? tableView
        return controlHighlightTarget(targetView) {
            SettingsWindow.searchStrings(tableView)
        }
    }

    private func highlightTarget(_ button: NSButton) -> SettingsSearchHighlightTarget? {
        guard SettingsWindow.sheet(forSearchButton: button) != nil else { return nil }
        return controlHighlightTarget(button) {
            var values = [String]()
            SettingsWindow.appendTrimmed(button.title, &values)
            if let sheet = SettingsWindow.sheet(forSearchButton: button) {
                values.append(contentsOf: SettingsWindow.sheetSearchStrings(sheet))
            }
            return Array(Set(values))
        }
    }

    private func highlightTarget(_ segmentedControl: NSSegmentedControl) -> SettingsSearchHighlightTarget? {
        let segmentLabels = (0..<segmentedControl.segmentCount).map {
            SettingsWindow.trimmedText(segmentedControl.label(forSegment: $0) ?? "")
        }
        if segmentLabels.allSatisfy(\.isEmpty) { return nil }
        var matchingSegmentIndexes = [Int]()
        return SettingsSearchHighlightTarget({ query in
            matchingSegmentIndexes = []
            segmentLabels.enumerated().forEach { index, label in
                guard !label.isEmpty else { return }
                if SettingsSearch.match(query, in: label) != nil {
                    matchingSegmentIndexes.append(index)
                }
            }
            if matchingSegmentIndexes.isEmpty { return [] }
            return [0..<1]
        }, { _ in
            SettingsWindow.applySegmentedControlHighlight(to: segmentedControl, segmentIndexes: matchingSegmentIndexes)
        }, {
            SettingsWindow.clearSegmentedControlHighlight(from: segmentedControl)
        })
    }

    private func highlightTarget(_ infoButton: ClickHoverImageView) -> SettingsSearchHighlightTarget? {
        controlHighlightTarget(infoButton) {
            SettingsWindow.searchStrings(infoButton)
        }
    }

    private func controlHighlightTarget(_ control: NSView, _ searchableStrings: @escaping () -> [String]) -> SettingsSearchHighlightTarget? {
        if searchableStrings().isEmpty { return nil }
        return SettingsSearchHighlightTarget({ query in
            searchableStrings().contains {
                SettingsSearch.match(query, in: $0) != nil
            }
        }, {
            SettingsWindow.applyControlHighlight(to: control)
        }, {
            SettingsWindow.clearControlHighlight(from: control)
        })
    }

    private static func characterRangeToNSRange(_ range: Range<Int>, in text: String) -> NSRange? {
        if range.lowerBound < 0 || range.upperBound > text.count || range.isEmpty { return nil }
        let start = text.index(text.startIndex, offsetBy: range.lowerBound)
        let end = text.index(text.startIndex, offsetBy: range.upperBound)
        return NSRange(start..<end, in: text)
    }

    private static func clearRoundedHighlights(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == roundedHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func clearControlHighlight(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == controlHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func clearSegmentedControlHighlight(from view: NSView) {
        view.layer?.sublayers?.filter { $0.name == segmentedControlHighlightLayerName }.forEach { $0.removeFromSuperlayer() }
    }

    private static func applySegmentedControlHighlight(to control: NSSegmentedControl, segmentIndexes: [Int]) {
        clearSegmentedControlHighlight(from: control)
        control.layoutSubtreeIfNeeded()
        guard !segmentIndexes.isEmpty else { return }
        control.wantsLayer = true
        let segmentRects = segmentedControlSegmentRects(control)
        segmentIndexes.forEach {
            guard segmentRects.indices.contains($0) else { return }
            let rect = segmentRects[$0].insetBy(dx: 1, dy: 1)
            guard rect.width > 0, rect.height > 0 else { return }
            let layer = noAnimation { CAShapeLayer() }
            layer.name = segmentedControlHighlightLayerName
            layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
            let cornerRadius = min(max(rect.height * 0.3, 4), 7)
            layer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
            control.layer?.insertSublayer(layer, at: 0)
        }
    }

    private static func segmentedControlSegmentRects(_ control: NSSegmentedControl) -> [CGRect] {
        let segmentCount = control.segmentCount
        if segmentCount <= 0 { return [] }
        let widths = (0..<segmentCount).map { max(control.width(forSegment: $0), 0) }
        let explicitWidthTotal = widths.reduce(0) {
            $0 + ($1 > 0 ? $1 : 0)
        }
        let autoSegmentCount = widths.filter { $0 == 0 }.count
        let autoSegmentWidth = autoSegmentCount > 0 ? max(control.bounds.width - explicitWidthTotal, 0) / CGFloat(autoSegmentCount) : 0
        var currentX = control.bounds.minX
        return widths.enumerated().map { index, width in
            let resolvedWidth = width > 0 ? width : autoSegmentWidth
            let isLastSegment = index == segmentCount - 1
            let segmentWidth = isLastSegment ? max(control.bounds.maxX - currentX, 0) : resolvedWidth
            defer { currentX += segmentWidth }
            return CGRect(x: currentX, y: control.bounds.minY, width: segmentWidth, height: control.bounds.height)
        }
    }

    private static func applyControlHighlight(to view: NSView) {
        clearControlHighlight(from: view)
        view.layoutSubtreeIfNeeded()
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        view.wantsLayer = true
        let layer = noAnimation { CAShapeLayer() }
        layer.name = controlHighlightLayerName
        layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
        let rect = view.bounds.insetBy(dx: -controlHighlightInset, dy: -controlHighlightInset)
        let cornerRadius = min(max(rect.height * 0.35, controlHighlightMinCornerRadius), controlHighlightMaxCornerRadius)
        layer.path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
        view.layer?.insertSublayer(layer, at: 0)
    }

    private static func applyRoundedHighlights(to textField: NSTextField,
                                               attributedString: NSAttributedString,
                                               ranges: [NSRange]) {
        clearRoundedHighlights(from: textField)
        guard !ranges.isEmpty else { return }
        textField.layoutSubtreeIfNeeded()
        let textRect = textDrawingRect(textField)
        guard textRect.width > 0, textRect.height > 0 else { return }
        textField.wantsLayer = true
        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: textRect.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = textField.maximumNumberOfLines
        textContainer.lineBreakMode = textField.lineBreakMode
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let horizontalOffset = textRect.minX
        let verticalOffset = textRect.minY + max(0, (textRect.height - usedRect.height) / 2)
        ranges.forEach { range in
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: textContainer) { rect, _ in
                var highlightRect = rect.offsetBy(dx: horizontalOffset, dy: verticalOffset)
                highlightRect = highlightRect.insetBy(dx: -roundedHighlightHorizontalInset, dy: -roundedHighlightVerticalInset)
                highlightRect = leadingTrimmedHighlightRect(highlightRect, textField)
                let layer = noAnimation { CAShapeLayer() }
                layer.name = roundedHighlightLayerName
                layer.fillColor = Appearance.searchMatchHighlightColor.cgColor
                layer.path = CGPath(roundedRect: highlightRect, cornerWidth: roundedHighlightCornerRadius, cornerHeight: roundedHighlightCornerRadius, transform: nil)
                textField.layer?.insertSublayer(layer, at: 0)
            }
        }
    }

    private static func leadingTrimmedHighlightRect(_ rect: CGRect, _ textField: NSTextField) -> CGRect {
        let trimmedWidth = max(rect.width - roundedHighlightLeadingTrim, 0.5)
        if textField.userInterfaceLayoutDirection == .rightToLeft {
            return CGRect(x: rect.minX, y: rect.minY, width: trimmedWidth, height: rect.height)
        }
        return CGRect(x: rect.minX + roundedHighlightLeadingTrim, y: rect.minY, width: trimmedWidth, height: rect.height)
    }

    private static func textDrawingRect(_ textField: NSTextField) -> CGRect {
        textField.cell?.drawingRect(forBounds: textField.bounds) ?? textField.bounds
    }

    private static func appendTrimmed(_ text: String, _ values: inout [String]) {
        let value = trimmedText(text)
        if !value.isEmpty {
            values.append(value)
        }
    }

    private static func trimmedText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func searchStrings(_ popUpButton: NSPopUpButton) -> [String] {
        var values = [String]()
        appendTrimmed(popUpButton.title, &values)
        popUpButton.itemTitles.forEach {
            appendTrimmed($0, &values)
        }
        return Array(Set(values))
    }

    private static func searchStrings(_ segmentedControl: NSSegmentedControl) -> [String] {
        var values = [String]()
        (0..<segmentedControl.segmentCount).forEach {
            appendTrimmed(segmentedControl.label(forSegment: $0) ?? "", &values)
        }
        return Array(Set(values))
    }

    private static func searchStrings(_ infoButton: ClickHoverImageView) -> [String] {
        var values = [String]()
        infoButton.searchableStrings.forEach {
            appendTrimmed($0, &values)
        }
        return Array(Set(values))
    }

    private static func searchStrings(_ tableView: TableView) -> [String] {
        var values = [String]()
        tableView.tableColumns.forEach {
            appendTrimmed($0.headerCell.stringValue, &values)
            appendTrimmed($0.headerToolTip ?? "", &values)
        }
        tableView.items.forEach {
            appendTrimmed($0.bundleIdentifier, &values)
            appendTrimmed($0.hide.localizedString, &values)
            appendTrimmed($0.ignore.localizedString, &values)
        }
        return Array(Set(values))
    }

    private static func sheet(forSearchButton button: NSButton) -> SheetWindow? {
        guard let action = button.action else { return nil }
        if action == #selector(AppearanceTab.showCustomizeStyleSheet) { return AppearanceTab.customizeStyleSheet }
        if action == #selector(AppearanceTab.showAnimationsSheet) { return AppearanceTab.animationsSheet }
        if action == #selector(ControlsTab.showShortcutsSettings) { return ControlsTab.shortcutsWhenActiveSheet }
        if action == #selector(ControlsTab.showAdditionalControlsSettings) { return ControlsTab.additionalControlsSheet }
        return nil
    }

    private static func sheetSearchStrings(_ sheet: SheetWindow) -> [String] {
        guard let contentView = sheet.contentView else { return [] }
        var values = [String]()
        collectSearchStrings(contentView, &values)
        return Array(Set(values))
    }

    private static func collectSearchStrings(_ root: NSView, _ values: inout [String]) {
        if let textField = root as? NSTextField {
            appendTrimmed(textField.stringValue, &values)
        } else if let popUpButton = root as? NSPopUpButton {
            appendTrimmed(popUpButton.title, &values)
            popUpButton.itemTitles.forEach {
                appendTrimmed($0, &values)
            }
        } else if let tableView = root as? TableView {
            searchStrings(tableView).forEach {
                appendTrimmed($0, &values)
            }
        } else if let button = root as? NSButton {
            appendTrimmed(button.title, &values)
        } else if let segmentedControl = root as? NSSegmentedControl {
            (0..<segmentedControl.segmentCount).forEach {
                appendTrimmed(segmentedControl.label(forSegment: $0) ?? "", &values)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            searchStrings(infoButton).forEach {
                appendTrimmed($0, &values)
            }
        } else if let textView = root as? NSTextView {
            appendTrimmed(textView.string, &values)
        }
        root.subviews.forEach {
            collectSearchStrings($0, &values)
        }
    }

    private func refreshControlsFromSettings() {
        GeneralTab.refreshControlsFromPreferences()
        PoliciesTab.refreshControlsFromPreferences()
    }

    func beginSheetWithSearchHighlight(_ sheet: SheetWindow) {
        beginSheet(sheet) { [weak self] _ in
            self?.clearSheetHighlights(sheet)
        }
        applySearchToSheet(sheet, searchField.stringValue)
    }

    private func applySearchToVisibleSheets(_ query: String) {
        sheets.compactMap { $0 as? SheetWindow }.forEach {
            applySearchToSheet($0, query)
        }
    }

    private func applySearchToSheet(_ sheet: SheetWindow, _ query: String) {
        let targets = highlightTargets(for: sheet)
        if SettingsSearch.isQueryEmpty(query) {
            targets.forEach { $0.clear() }
            return
        }
        targets.forEach { $0.updateHighlight(query) }
    }

    private func highlightTargets(for sheet: SheetWindow) -> [SettingsSearchHighlightTarget] {
        let key = ObjectIdentifier(sheet)
        if let targets = sheetHighlightTargets[key] {
            return targets
        }
        guard let contentView = sheet.contentView else { return [] }
        var targets = [SettingsSearchHighlightTarget]()
        collectSheetHighlightTargets(contentView, &targets)
        sheetHighlightTargets[key] = targets
        return targets
    }

    private func collectSheetHighlightTargets(_ root: NSView, _ targets: inout [SettingsSearchHighlightTarget]) {
        if let textField = root as? NSTextField {
            if let target = highlightTarget(textField) {
                targets.append(target)
            }
        } else if let popUpButton = root as? NSPopUpButton {
            if let target = highlightTarget(popUpButton) {
                targets.append(target)
            }
        } else if let segmentedControl = root as? NSSegmentedControl {
            if let target = highlightTarget(segmentedControl) {
                targets.append(target)
            }
        } else if let infoButton = root as? ClickHoverImageView {
            if let target = highlightTarget(infoButton) {
                targets.append(target)
            }
        }
        root.subviews.forEach {
            collectSheetHighlightTargets($0, &targets)
        }
    }

    private func clearSheetHighlights(_ sheet: SheetWindow) {
        let key = ObjectIdentifier(sheet)
        guard let targets = sheetHighlightTargets[key] else { return }
        targets.forEach { $0.clear() }
    }

    private func selectSection(_ section: SettingsSection, scroll: Bool, selectInSidebar: Bool = true) {
        selectedSectionId = section.id
        if selectInSidebar, let row = visibleSections.firstIndex(where: { $0.id == section.id }), sidebarTableView.selectedRow != row {
            sidebarTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        guard scroll else { return }
        scrollToSection(section)
    }

    private func scrollToSection(_ section: SettingsSection) {
        sectionsDocumentView.layoutSubtreeIfNeeded()
        let anchorFrame = section.anchor.convert(section.anchor.bounds, to: sectionsDocumentView)
        let targetY = max(anchorFrame.minY - Self.sectionScrollTopPadding, 0)
        rightScrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        rightScrollView.reflectScrolledClipView(rightScrollView.contentView)
    }

    private func applySearch(_ query: String) {
        Popover.shared.updateSearchContext(query) { query, text in
            SettingsSearch.match(query, in: text)?.ranges ?? []
        }
        let hasQuery = !SettingsSearch.isQueryEmpty(query)
        let matchingSections = sections.filter { !hasQuery || $0.matches(query) }
        visibleSections = matchingSections
        let visibleSectionIds = Set(visibleSections.map(\.id))
        sections.forEach {
            let isVisible = visibleSectionIds.contains($0.id)
            $0.container.isHidden = !isVisible
            if isVisible && hasQuery {
                $0.highlightMatches(query)
            } else {
                $0.clearHighlights()
            }
        }
        applySearchToVisibleSheets(query)
        updateVisibleSectionsSpacing()
        sidebarTableView.reloadData()
        guard !visibleSections.isEmpty else {
            selectedSectionId = nil
            sidebarTableView.deselectAll(nil)
            return
        }
        if let selectedSectionId, let row = visibleSections.firstIndex(where: { $0.id == selectedSectionId }) {
            selectSection(visibleSections[row], scroll: true)
            return
        }
        selectSection(visibleSections[0], scroll: true)
    }

    override func close() {
        hideAppIfLastWindowIsClosed()
        super.close()
    }
}

extension SettingsWindow: NSWindowDelegate {
    func windowWillStartLiveResize(_ notification: Notification) {
        liveResizeOriginX = frame.origin.x
    }

    func windowDidResize(_ notification: Notification) {
        guard inLiveResize, let liveResizeOriginX else { return }
        guard abs(frame.origin.x - liveResizeOriginX) > 0 else { return }
        setFrameOrigin(NSPoint(x: liveResizeOriginX, y: frame.origin.y))
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        liveResizeOriginX = nil
    }
}

extension SettingsWindow: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        applySearch(searchField.stringValue)
    }
}

extension SettingsWindow: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleSections.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        30
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let section = visibleSections[row]
        let cell = tableView.makeView(withIdentifier: SettingsSidebarCellView.identifier, owner: self) as? SettingsSidebarCellView ?? {
            let view = SettingsSidebarCellView()
            view.identifier = SettingsSidebarCellView.identifier
            return view
        }()
        cell.configure(section)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        guard row >= 0, row < visibleSections.count else { return }
        let section = visibleSections[row]
        if selectedSectionId == section.id { return }
        selectSection(section, scroll: true, selectInSidebar: false)
    }
}
