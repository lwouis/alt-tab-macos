import Cocoa
import ShortcutRecorder
import XCTest

final class SearchDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var context: SearchDiscoveryPolicy.Context {
        .init(access: .trial(day: 5), windowCount: 8, hasShortcut: true)
    }

    func testMascotFillsItsSlotWithoutClippingTheArtwork() throws {
        _ = NSApplication.shared
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("resources/pro-rabbit.png")
        let source = try XCTUnwrap(NSImage(contentsOf: file))
        func visibleBounds(_ image: NSImage) throws -> CGRect {
            let view = NSImageView(frame: NSRect(x: 0, y: 0, width: 76, height: 76))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var bounds = CGRect.null
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.01 {
                    bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
            let scale = CGFloat(bitmap.pixelsWide) / 76
            return CGRect(x: bounds.minX / scale, y: bounds.minY / scale,
                          width: bounds.width / scale, height: bounds.height / scale)
        }
        let bounds = try visibleBounds(source)
        XCTAssertGreaterThan(bounds.width, 70)
        XCTAssertGreaterThan(bounds.height, 64)
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 76, height: 76).contains(bounds))
    }

    func testThresholdUsesEligibleTargets() {
        var c = context
        let history = SearchDiscoveryPolicy.History(hasSearched: false)
        c.windowCount = 7
        XCTAssertFalse(c.isEligible(history: history))
        c.windowCount = 8
        XCTAssertTrue(c.isEligible(history: history))
    }

    func testTrialCalendarReservesExistingPrompts() {
        for day in -1...15 {
            var c = context
            c.access = .trial(day: day)
            XCTAssertEqual(c.isEligible(history: .init(hasSearched: false)),
                           [1, 2, 4, 5, 6, 7, 8, 9, 10].contains(day), "day \(day)")
        }
    }

    func testPurchaseAndExpirationStopDiscovery() {
        var c = context
        XCTAssertTrue(c.isEligible(history: .init(hasSearched: false)))
        c.access = .pro
        XCTAssertFalse(c.isEligible(history: .init(hasSearched: false)))
        c.access = .locked
        XCTAssertFalse(c.isEligible(history: .init(hasSearched: false)))
    }

    func testUnknownOrUsedSearchNeverOffersHint() {
        XCTAssertFalse(context.isEligible(history: .init()))
        XCTAssertFalse(context.isEligible(history: .init(hasSearched: true)))
        XCTAssertTrue(context.isEligible(history: .init(hasSearched: false)))
    }

    func testLateHistoryCannotUndoNewSearch() {
        var history = SearchDiscoveryPolicy.History()
        history.recordSearch()
        history.resolvePreviousSearch(false)
        history.resolvePreviousSearch(nil)
        XCTAssertEqual(history.hasSearched, true)
    }

    func testHistoricalSearchSuppressesHint() {
        var history = SearchDiscoveryPolicy.History()
        history.resolvePreviousSearch(true)
        XCTAssertFalse(context.isEligible(history: history))
    }

    func testRefusalSearchAndCompetingUIHavePriority() {
        let mutations: [(inout SearchDiscoveryPolicy.Context) -> Void] = [
            { $0.enabled = false }, { $0.optedOut = true }, { $0.searchActive = true },
            { $0.blockedByOtherUI = true }, { $0.hasShortcut = false },
        ]
        for mutate in mutations {
            var c = context
            mutate(&c)
            XCTAssertFalse(c.isEligible(history: .init(hasSearched: false)))
        }
    }

    func testCooldownBoundaryAndClockRollback() {
        let history = SearchDiscoveryPolicy.History(hasSearched: false, exposures: 1, lastExposure: now)
        XCTAssertFalse(history.canPresent(at: now.addingTimeInterval(-1)))
        XCTAssertFalse(history.canPresent(at: now.addingTimeInterval(SearchDiscoveryPolicy.cooldown - 1)))
        XCTAssertTrue(history.canPresent(at: now.addingTimeInterval(SearchDiscoveryPolicy.cooldown)))
    }

    func testThirdExposureRemainsVisibleButNeverRepeats() {
        var history = SearchDiscoveryPolicy.History(hasSearched: false, exposures: 2,
                                                    lastExposure: now.addingTimeInterval(-SearchDiscoveryPolicy.cooldown))
        XCTAssertTrue(history.canPresent(at: now))
        history.recordExposure(at: now)
        XCTAssertTrue(context.isEligible(history: history))
        XCTAssertFalse(history.canPresent(at: now.addingTimeInterval(10 * SearchDiscoveryPolicy.cooldown)))
        XCTAssertEqual(history.exposures, 3)
    }

    func testMissingExposureDateDoesNotResetLimits() {
        XCTAssertTrue(SearchDiscoveryPolicy.History().canPresent(at: now))
        XCTAssertFalse(SearchDiscoveryPolicy.History(exposures: 1).canPresent(at: now))
        XCTAssertFalse(SearchDiscoveryPolicy.History(exposures: -1).canPresent(at: now))
    }

    func testOneOpportunityPerSessionEvenAfterDismissal() {
        let opportunity = SearchDiscoveryPolicy.Opportunity()
        XCTAssertTrue(opportunity.schedule())
        XCTAssertFalse(opportunity.schedule())
        opportunity.cancel()
        XCTAssertFalse(opportunity.schedule())
        XCTAssertFalse(opportunity.isReady(current: opportunity, now: 100))
    }

    #if DEBUG
    func testQAPreviewBypassesDiscoveryEligibilityOnlyForItsSession() {
        let c = SearchDiscoveryPolicy.Context(access: .locked, windowCount: 1, enabled: false,
                                              optedOut: true, hasShortcut: true)
        let history = SearchDiscoveryPolicy.History(hasSearched: true, exposures: 3, lastExposure: now)
        let preview = SearchDiscoveryPolicy.Opportunity()
        preview.isPreview = true
        XCTAssertTrue(preview.isEligible(context: c, history: history))
        XCTAssertFalse(preview.recordsHistory)
        let next = SearchDiscoveryPolicy.Opportunity()
        XCTAssertFalse(next.isEligible(context: c, history: history))
        XCTAssertTrue(next.recordsHistory)
        XCTAssertTrue(preview.schedule())
        XCTAssertFalse(preview.isReady(current: next, now: 100))
        preview.cancel()
        XCTAssertFalse(preview.isReady(current: preview, now: 100))
    }

    func testQAPreviewStillYieldsToSearchAndCompetingUI() {
        let preview = SearchDiscoveryPolicy.Opportunity()
        preview.isPreview = true
        let mutations: [(inout SearchDiscoveryPolicy.Context) -> Void] = [
            { $0.searchActive = true }, { $0.blockedByOtherUI = true }, { $0.hasShortcut = false },
        ]
        for mutate in mutations {
            var c = context
            mutate(&c)
            XCTAssertFalse(preview.isEligible(context: c, history: .init()))
        }
    }
    #endif

    func testDelayedHintCannotCrossIntoAnotherSession() {
        let old = SearchDiscoveryPolicy.Opportunity()
        let current = SearchDiscoveryPolicy.Opportunity()
        XCTAssertTrue(old.schedule())
        XCTAssertFalse(old.isReady(current: nil, now: 100))
        XCTAssertFalse(old.isReady(current: current, now: 100))
        XCTAssertTrue(current.schedule())
        XCTAssertTrue(current.isReady(current: current, now: 100))
    }

    func testQuietPeriodIncludesNavigationThatDidNotChangeIndex() {
        let opportunity = SearchDiscoveryPolicy.Opportunity()
        XCTAssertTrue(opportunity.schedule())
        opportunity.lastNavigationAt = 100
        XCTAssertFalse(opportunity.isReady(current: opportunity, now: 100.499))
        XCTAssertTrue(opportunity.isReady(current: opportunity, now: 100.5))
    }

    func testPlacementAboveSwitcherWhenItFits() throws {
        let size = CGSize(width: 470, height: 88)
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let switcher = CGRect(x: 100, y: 200, width: 800, height: 400)
        let above = try XCTUnwrap(SearchDiscoveryPolicy.frame(size: size, switcher: switcher, visibleScreen: screen))
        XCTAssertEqual(above.minY, switcher.maxY + 8)
        XCTAssertEqual(above.midX, switcher.midX)
    }

    func testPlacementOverBottomOfSwitcherWhenAboveDoesNotFit() throws {
        let size = CGSize(width: 470, height: 88)
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let switcher = CGRect(x: 100, y: 100, width: 1000, height: 720)
        let bottom = try XCTUnwrap(SearchDiscoveryPolicy.frame(size: size, switcher: switcher, visibleScreen: screen))
        XCTAssertEqual(bottom.minY, switcher.minY + 16)
        XCTAssertEqual(bottom.midX, switcher.midX)
        XCTAssertTrue(switcher.contains(bottom))
    }

    func testPlacementOverBottomStaysOnScreenWhenSwitcherExtendsBelowIt() throws {
        let screen = CGRect(x: 0, y: 100, width: 800, height: 600)
        let result = try XCTUnwrap(SearchDiscoveryPolicy.frame(size: CGSize(width: 470, height: 88),
            switcher: CGRect(x: 0, y: 0, width: 800, height: 800), visibleScreen: screen))
        XCTAssertEqual(result.minY, screen.minY + 8)
        XCTAssertTrue(screen.contains(result))
    }

    func testPlacementUsesActualScreenOriginAndClampsHorizontally() throws {
        let screen = CGRect(x: -1600, y: 300, width: 1600, height: 900)
        let result = try XCTUnwrap(SearchDiscoveryPolicy.frame(size: CGSize(width: 470, height: 44),
            switcher: CGRect(x: -1600, y: 700, width: 300, height: 200), visibleScreen: screen))
        XCTAssertEqual(result.minX, -1592)
        XCTAssertEqual(result.minY, 908)
        XCTAssertTrue(screen.contains(result))
    }

    func testNoHintWhenWiderOrTallerThanScreen() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        XCTAssertNil(SearchDiscoveryPolicy.frame(size: CGSize(width: 900, height: 44), switcher: .zero, visibleScreen: screen))
        XCTAssertNil(SearchDiscoveryPolicy.frame(size: CGSize(width: 470, height: 700), switcher: .zero, visibleScreen: screen))
    }

    func testPanelDoesNotTakeFocusAndCloseButtonIsAccessible() {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.dismissButton.acceptsFirstResponder)
        XCTAssertTrue(panel.dismissButton.acceptsFirstMouse(for: nil))
        XCTAssertEqual(panel.dismissButton.accessibilityLabel(), SearchDiscoveryPanel.dismissLabel)
        var dismissed = false
        panel.onDismiss = { dismissed = true }
        panel.dismissButton.performClick(nil)
        XCTAssertTrue(dismissed)
    }

    func testHintClickAndDragDoNotDismissTheSwitcher() {
        var click = SearchDiscoveryPolicy.Click()
        XCTAssertTrue(click.begin(inside: true))
        XCTAssertTrue(click.end(inside: true))
        XCTAssertTrue(click.begin(inside: true))
        XCTAssertTrue(click.end(inside: false))
        XCTAssertFalse(click.begin(inside: false))
        XCTAssertFalse(click.end(inside: false))
        XCTAssertTrue(click.end(inside: true))
        XCTAssertFalse(click.end(inside: false))
    }

    func testPanelFitsCustomShortcutAndNarrowScreenInBothThemes() throws {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        for dark in [false, true] {
            let size = panel.prepare(shortcut: "⌘⇧F", spokenShortcut: "Command Shift F",
                                     dark: dark, highContrast: true, maxWidth: 250)
            XCTAssertEqual(size.width, 250)
            XCTAssertGreaterThan(size.height, 44)
            let text = panel.hintLabel.attributedStringValue
            let index = (text.string as NSString).range(of: "\u{FFFC}").location
            let attachment = try XCTUnwrap(text.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)
            let cell = try XCTUnwrap(attachment.attachmentCell as? SearchDiscoveryKeycapCell)
            XCTAssertGreaterThan(cell.cellSize().width, 24)
            XCTAssertEqual(cell.cellSize().height, 24)
            XCTAssertFalse(cell.wantsToTrackMouse())
            XCTAssertFalse(panel.hintLabel.isEditable)
            XCTAssertFalse(panel.hintLabel.isSelectable)
            XCTAssertFalse(panel.hintLabel.cell!.usesSingleLineMode)
            XCTAssertTrue(try XCTUnwrap(panel.hintLabel.accessibilityLabel()?.contains("Command Shift F")))
            XCTAssertFalse(panel.hintLabel.stringValue.contains("Pro"))
            XCTAssertFalse(panel.hintLabel.frame.intersects(panel.dismissButton.frame))
            XCTAssertTrue(NSRect(origin: .zero, size: size).contains(panel.hintLabel.frame))
            XCTAssertEqual(panel.background.layer?.borderWidth, 0)
            XCTAssertTrue((panel.background as? SpeechBubbleView)?.highContrast == true)
            XCTAssertEqual(panel.dismissButton.frame.size, NSSize(width: 24, height: 24))
        }
    }

    func testTipInsetsKeepCloseControlInsideBodyAndClearOfText() {
        let panel = SearchDiscoveryPanel()
        for width: CGFloat in [250, 560] {
            _ = panel.prepare(shortcut: "S", spokenShortcut: "S", dark: false,
                highContrast: false, maxWidth: width, title: "Find a window by typing")
            XCTAssertEqual(panel.hintLabel.alignmentRect(forFrame: panel.hintLabel.frame).minX, 29)
            XCTAssertEqual(panel.hintLabel.frame.minY, 19)
            XCTAssertEqual(panel.titleLabel.frame.minY - panel.hintLabel.frame.maxY, 4)
            XCTAssertEqual(panel.background.bounds.maxX - panel.dismissButton.frame.maxX, 19)
            XCTAssertEqual(panel.background.bounds.maxY - panel.titleLabel.frame.maxY, 19)
            XCTAssertFalse(panel.hintLabel.frame.intersects(panel.dismissButton.frame))
            XCTAssertFalse(panel.dismissButton.acceptsFirstResponder)
        }
    }

    func testBubbleHugsShortContentAndCapsLongContent() {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        let short = panel.prepare(shortcut: "S", spokenShortcut: "S", dark: false,
            highContrast: false, maxWidth: 900, title: "Find", instruction: "Press %@.")
        XCTAssertLessThan(short.width, 350)
        let long = panel.prepare(shortcut: "⌘⇧F", spokenShortcut: "Command Shift F", dark: false,
            highContrast: false, maxWidth: 900, title: String(repeating: "Window title ", count: 15))
        XCTAssertEqual(long.width, 560)
        XCTAssertEqual(long.height, short.height)
        XCTAssertEqual(panel.titleLabel.maximumNumberOfLines, 1)
        XCTAssertEqual(panel.hintLabel.maximumNumberOfLines, 1)
        XCTAssertEqual(panel.titleLabel.lineBreakMode, .byTruncatingTail)
        XCTAssertEqual(panel.hintLabel.lineBreakMode, .byTruncatingTail)
        XCTAssertFalse(panel.hintLabel.frame.intersects(panel.dismissButton.frame))
    }

    func testLongTipKeepsTwoSingleLinesAndFullAccessibleInstructions() {
        let panel = SearchDiscoveryPanel()
        let title = "Show only A very long application name windows (active app)"
        let instruction = String(repeating: "Hold ", count: 20) + "%@ then press %@"
        for width: CGFloat in [250, 560] {
            let size = panel.prepare(shortcut: "`", spokenShortcut: "Grave", dark: false, highContrast: false,
                maxWidth: width, title: title, instruction: instruction, holdKey: (label: "⌥", spoken: "Option"))
            XCTAssertEqual(panel.background.bounds.maxY - panel.titleLabel.frame.maxY, panel.hintLabel.frame.minY)
            XCTAssertLessThanOrEqual(size.width, width)
            XCTAssertEqual(panel.titleLabel.stringValue, title)
            XCTAssertEqual(panel.hintLabel.accessibilityLabel(), String(format: instruction, "Option", "Grave"))
            XCTAssertEqual(panel.titleLabel.frame.height, ceil(panel.titleLabel.intrinsicContentSize.height))
            XCTAssertEqual(panel.hintLabel.frame.height, 24)
            XCTAssertFalse(panel.titleLabel.frame.intersects(panel.dismissButton.frame))
            XCTAssertFalse(panel.hintLabel.frame.intersects(panel.dismissButton.frame))
        }
    }

    /// Translations may reorder the two placeholders; each keycap and its spoken name follow its argument.
    func testExtraShortcutInstructionShowsHoldAndKeyAsKeycaps() {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        for (instruction, spoken) in [("Keep holding %@ then press %@", "Keep holding Option then press `"),
                                      ("Press %2$@ while holding %1$@.", "Press ` while holding Option.")] {
            _ = panel.prepare(shortcut: "`", spokenShortcut: "`", dark: false, highContrast: false, maxWidth: 560,
                              title: "Show only Safari windows (active app)", instruction: instruction,
                              holdKey: (label: "⌥", spoken: "Option"))
            let text = panel.hintLabel.attributedStringValue
            var attachments = 0
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if value is NSTextAttachment { attachments += 1 }
            }
            XCTAssertEqual(attachments, 2)
            XCTAssertFalse(text.string.contains("%"))
            XCTAssertEqual(panel.hintLabel.accessibilityLabel(), spoken)
        }
    }

    func testShortcutCardsCombineConfiguredHoldAndNextKeys() throws {
        let hold = Shortcut(code: .none, modifierFlags: [.option], characters: nil, charactersIgnoringModifiers: nil)
        let next = try XCTUnwrap(Shortcut(keyEquivalent: "⇥"))
        XCTAssertEqual(SearchDiscoveryShortcut.combinedLabel(hold: hold, next: next), "⌥⇥")
        XCTAssertNil(SearchDiscoveryShortcut.combinedLabel(hold: hold, next: nil))
        XCTAssertNil(SearchDiscoveryShortcut.combinedLabel(hold: hold, next: hold))
    }

    func testMessageAndTipUseEqualSharedBodyInsets() throws {
        _ = NSApplication.shared
        for emphasized in [false, true] {
            let message = MascotMessageView(title: "Trial status", message: "Get Pro to keep these features",
                emphasizeMessage: emphasized)
            let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
            window.contentView = message
            window.setContentSize(message.fittingSize)
            message.layoutSubtreeIfNeeded()
            let bubble = try XCTUnwrap(message.arrangedSubviews.last as? SpeechBubbleView)
            let content = try XCTUnwrap(bubble.subviews.first)
            XCTAssertEqual(content.frame.minX - 11, 18, accuracy: 0.5)
            XCTAssertEqual(bubble.bounds.maxX - content.frame.maxX - 1, 18, accuracy: 0.5)
            XCTAssertEqual(content.frame.minY - 1, 18, accuracy: 0.5)
            XCTAssertEqual(bubble.bounds.maxY - content.frame.maxY - 1, 18, accuracy: 0.5)
        }
        let panel = SearchDiscoveryPanel()
        _ = panel.prepare(shortcut: "S", spokenShortcut: "S", dark: false, highContrast: false, maxWidth: 560)
        XCTAssertEqual(panel.hintLabel.alignmentRect(forFrame: panel.hintLabel.frame).minX - 11, 18)
        XCTAssertEqual(panel.background.bounds.maxX - panel.hintLabel.alignmentRect(forFrame: panel.hintLabel.frame).maxX - 1, 18)
        XCTAssertEqual(panel.hintLabel.frame.minY - 1, 18)
        XCTAssertEqual(panel.background.bounds.maxY - panel.titleLabel.frame.maxY - 1, 18)
    }

    func testBubbleTailHasOneClosedOutlineInBothDirections() {
        let bubble = SpeechBubbleView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
        for rtl in [false, true] {
            bubble.pointsRight = rtl
            let path = bubble.bubblePath()
            var points = [NSPoint](repeating: .zero, count: 3)
            let elements = (0..<path.elementCount).map { path.element(at: $0, associatedPoints: &points) }
            XCTAssertEqual(elements.prefix(while: { $0 != .closePath }).filter { $0 == .moveTo }.count, 1)
            XCTAssertEqual(elements.filter { $0 == .closePath }.count, 1)
            XCTAssertTrue(path.contains(NSPoint(x: rtl ? 296 : 4, y: 45)))
            XCTAssertFalse(path.contains(NSPoint(x: rtl ? 296 : 4, y: 20)))
        }
    }

    func testPanelTakesSwitcherBackgroundAndCloseButtonHovers() {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        let background = NSView()
        let host = NSView()
        background.addSubview(host)
        panel.setBackground(background, host: host)
        let size = panel.prepare(shortcut: "S", spokenShortcut: "S", dark: true, highContrast: false, maxWidth: 470)
        XCTAssertTrue(background.superview === panel.contentView)
        XCTAssertTrue(panel.hintLabel.superview === host)
        XCTAssertTrue(panel.dismissButton.superview === host)
        XCTAssertEqual(host.frame.size, NSSize(width: size.width - 88, height: size.height))
        XCTAssertEqual(panel.cornerRadius, 24)
        XCTAssertEqual(background.layer?.borderWidth, 0)
        XCTAssertNil(panel.dismissButton.layer?.backgroundColor)
        panel.dismissButton.isHovered = true
        XCTAssertNotNil(panel.dismissButton.layer?.backgroundColor)
        panel.orderOut(nil)
        XCTAssertNil(panel.dismissButton.layer?.backgroundColor)
    }

    func testShortcutLabelReflectsBindingWithoutInventingHoldModifiers() throws {
        let bare = try XCTUnwrap(Shortcut(keyEquivalent: "S"))
        let modified = Shortcut(code: bare.keyCode, modifierFlags: [.command, .shift], characters: nil, charactersIgnoringModifiers: nil)
        XCTAssertEqual(SearchDiscoveryShortcut.label(bare),
                       SymbolicKeyCodeTransformer.shared.transformedValue(NSNumber(value: bare.carbonKeyCode))?.uppercased())
        XCTAssertEqual(SearchDiscoveryShortcut.label(modified), "⇧⌘" + SearchDiscoveryShortcut.label(bare)!)
        XCTAssertNil(SearchDiscoveryShortcut.label(Shortcut(code: .none, modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil)))
    }

    func testActiveAppTipRequiresBothAUsefulGroupAndOtherAppsToExclude() {
        XCTAssertFalse(SearchDiscoveryPolicy.canDemonstrateActiveApp(activeWindows: 0, totalWindows: 8))
        XCTAssertFalse(SearchDiscoveryPolicy.canDemonstrateActiveApp(activeWindows: 1, totalWindows: 8))
        XCTAssertFalse(SearchDiscoveryPolicy.canDemonstrateActiveApp(activeWindows: 3, totalWindows: 3))
        XCTAssertTrue(SearchDiscoveryPolicy.canDemonstrateActiveApp(activeWindows: 2, totalWindows: 3))
    }

    func testSearchAndExtraShortcutShareExposureBudgetAndCooldown() {
        var history = SearchDiscoveryPolicy.History(hasSearched: false)
        history.hasUsedExtraShortcut = false
        var context = SearchDiscoveryPolicy.Context(
            access: .trial(day: 5),
            windowCount: 3,
            hasShortcut: true,
            extraShortcut: true
        )
        XCTAssertTrue(context.isEligible(history: history))
        let now = Date(timeIntervalSince1970: 10000)
        history.recordExposure(at: now)
        context.extraShortcut = false
        context.windowCount = 8
        XCTAssertTrue(context.isEligible(history: history))
        XCTAssertFalse(history.canPresent(at: now.addingTimeInterval(60)))
        history.recordExposure(at: now.addingTimeInterval(SearchDiscoveryPolicy.cooldown))
        history.recordExposure(at: now.addingTimeInterval(2 * SearchDiscoveryPolicy.cooldown))
        XCTAssertFalse(history.canPresent(at: now.addingTimeInterval(3 * SearchDiscoveryPolicy.cooldown)))
        history.recordSearch()
        XCTAssertFalse(context.isEligible(history: history))
        context.extraShortcut = true
        XCTAssertTrue(context.isEligible(history: history))
        history.hasUsedExtraShortcut = true
        XCTAssertFalse(context.isEligible(history: history))
    }

    func testNativeHintRendering() throws {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        for dark in [false, true] {
            let size = panel.prepare(shortcut: "S", spokenShortcut: "S", dark: dark, highContrast: false, maxWidth: 470)
            let text = panel.hintLabel.attributedStringValue
            let index = (text.string as NSString).range(of: "\u{FFFC}").location
            let attachment = try XCTUnwrap(text.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment)
            XCTAssertEqual(attachment.attachmentCell?.cellSize(), NSSize(width: 24, height: 24))
            XCTAssertEqual(panel.hintLabel.accessibilityLabel(), String(format: SearchDiscoveryPanel.message, "S"))
            panel.setContentSize(size)
            let view = try XCTUnwrap(panel.contentView)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let snapshot = try XCTAttachment(
                data: XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                                           uniformTypeIdentifier: "public.png")
            snapshot.name = dark ? "Search hint - dark" : "Search hint - light"
            snapshot.lifetime = .keepAlways
            add(snapshot)
            XCTAssertEqual(panel.background.bounds.maxY - panel.titleLabel.frame.maxY, panel.hintLabel.frame.minY)
        }
    }
}
