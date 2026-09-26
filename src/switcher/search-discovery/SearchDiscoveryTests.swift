import Cocoa
import XCTest
import ShortcutRecorder

final class SearchDiscoveryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var context: SearchDiscoveryPolicy.Context {
        .init(access: .pro, windowCount: 8, hasShortcut: true)
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

    func testProCanDiscoverSearchButLockedUsersCannot() {
        var c = context
        XCTAssertTrue(c.isEligible(history: .init(hasSearched: false)))
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

    func testPlacementAboveAndBelowWithoutMovingSwitcher() {
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let size = CGSize(width: 470, height: 44)
        let switcher = CGRect(x: 100, y: 200, width: 1000, height: 400)
        let above = SearchDiscoveryPolicy.frame(size: size, switcher: switcher, visibleScreen: screen, obstruction: nil)!
        XCTAssertEqual(above, CGRect(x: 365, y: 608, width: 470, height: 44))
        let below = SearchDiscoveryPolicy.frame(size: size, switcher: switcher, visibleScreen: screen, obstruction: above)!
        XCTAssertEqual(below, CGRect(x: 365, y: 148, width: 470, height: 44))
    }

    func testPlacementUsesActualScreenOriginAndClampsHorizontally() {
        let screen = CGRect(x: -1600, y: 300, width: 1600, height: 900)
        let result = SearchDiscoveryPolicy.frame(size: CGSize(width: 470, height: 44),
            switcher: CGRect(x: -1600, y: 700, width: 300, height: 200), visibleScreen: screen, obstruction: nil)!
        XCTAssertEqual(result.minX, -1592)
        XCTAssertEqual(result.minY, 908)
        XCTAssertTrue(screen.contains(result))
    }

    func testNoHintWhenNeitherSideFitsOrPreviewCoversBoth() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: 470, height: 44)
        XCTAssertNil(SearchDiscoveryPolicy.frame(size: size,
            switcher: screen.insetBy(dx: 20, dy: 20), visibleScreen: screen, obstruction: nil))
        XCTAssertNil(SearchDiscoveryPolicy.frame(size: size,
            switcher: CGRect(x: 100, y: 200, width: 600, height: 200), visibleScreen: screen, obstruction: screen))
        XCTAssertNil(SearchDiscoveryPolicy.frame(size: CGSize(width: 900, height: 44),
            switcher: .zero, visibleScreen: screen, obstruction: nil))
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
            XCTAssertTrue(panel.hintLabel.accessibilityLabel()!.contains("Command Shift F"))
            XCTAssertFalse(panel.hintLabel.stringValue.contains("Pro"))
            XCTAssertFalse(panel.hintLabel.frame.intersects(panel.dismissButton.frame))
            XCTAssertTrue(NSRect(origin: .zero, size: size).contains(panel.hintLabel.frame))
            XCTAssertEqual(panel.contentView?.layer?.borderWidth, 2)
            XCTAssertEqual(panel.dismissButton.frame.size, NSSize(width: 24, height: 24))
        }
    }

    func testPanelTakesSwitcherBackgroundAndCloseButtonHovers() throws {
        _ = NSApplication.shared
        let panel = SearchDiscoveryPanel()
        let background = NSView()
        let host = NSView()
        background.addSubview(host)
        panel.setBackground(background, host: host)
        let size = panel.prepare(shortcut: "S", spokenShortcut: "S", dark: true, highContrast: false, maxWidth: 470,
                                 maxCornerRadius: 50)
        XCTAssertTrue(panel.contentView === background)
        XCTAssertTrue(panel.hintLabel.superview === host)
        XCTAssertTrue(panel.dismissButton.superview === host)
        XCTAssertEqual(host.frame.size, size)
        XCTAssertEqual(panel.cornerRadius, size.height / 2)
        XCTAssertEqual(background.layer?.borderWidth, 0)
        XCTAssertNil(panel.dismissButton.layer?.backgroundColor)
        panel.dismissButton.isHovered = true
        XCTAssertNotNil(panel.dismissButton.layer?.backgroundColor)
        panel.orderOut(nil)
        XCTAssertNil(panel.dismissButton.layer?.backgroundColor)
    }

    func testShortcutLabelReflectsBindingWithoutInventingHoldModifiers() {
        let bare = Shortcut(keyEquivalent: "S")!
        let modified = Shortcut(code: bare.keyCode, modifierFlags: [.command, .shift], characters: nil, charactersIgnoringModifiers: nil)
        XCTAssertEqual(SearchDiscoveryShortcut.label(bare),
                       SymbolicKeyCodeTransformer.shared.transformedValue(NSNumber(value: bare.carbonKeyCode))?.uppercased())
        XCTAssertEqual(SearchDiscoveryShortcut.label(modified), "⇧⌘" + SearchDiscoveryShortcut.label(bare)!)
        XCTAssertNil(SearchDiscoveryShortcut.label(Shortcut(code: .none, modifierFlags: [], characters: nil, charactersIgnoringModifiers: nil)))
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
            let snapshot = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
                                           uniformTypeIdentifier: "public.png")
            snapshot.name = dark ? "Search hint - dark" : "Search hint - light"
            snapshot.lifetime = .keepAlways
            add(snapshot)
            XCTAssertEqual(size.height, 44)
        }
    }
}
