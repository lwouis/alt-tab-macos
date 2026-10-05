import XCTest

final class WindowAdmissionResolverTests: XCTestCase {
    private func physical(wid: CGWindowID = 1, y: CGFloat = 0, width: CGFloat = 800, height: CGFloat = 600,
                          level: CGWindowLevel = 0, parentWid: CGWindowID = 0, isVisible: Bool = true,
                          isFullscreen: Bool = false) -> PhysicalSurface {
        PhysicalSurface(wid: wid, pid: 7, bounds: CGRect(x: 0, y: y, width: width, height: height),
            level: level, parentWid: parentWid, isVisible: isVisible, isFullscreen: isFullscreen)
    }

    private func semantic(title: String? = "Document", subrole: String? = kAXStandardWindowSubrole,
                          role: String? = kAXWindowRole, isMain: Bool? = false) -> SemanticSurface {
        SemanticSurface(title: title, subrole: subrole, role: role, isMain: isMain)
    }

    func testWidZeroIsRejected() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(wid: 0), semantic()), .reject(.invalidWindowId))
    }

    func testSheetRepresentsParentBeforeAttentionCanAcceptIt() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(parentWid: 9), semantic(), evidence: .attention),
            .represent(parentWid: 9, .attachedSurface))
    }

    func testExactAttentionAcceptsAxUnavailableOrdinaryLevelSurface() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 20, height: 20), nil,
            evidence: .attention), .destination(.exactAttention))
    }

    /// ChatGPT's voice-recording HUD while accessibility has not described it: a 720x84 strip at the floating
    /// level. Toggling it moves the app's key focus onto it, and `kAXFocusedWindow` reports it, so attention
    /// is the only thing that ever names it as a destination.
    func testExactAttentionDoesNotAdmitAnUndescribedFloatingHud() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 720, height: 84, level: 3), nil,
            evidence: .attention), .reject(.auxiliarySurface))
    }

    func testExactAttentionAdmitsAnUndescribedFullscreenSurface() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 101, isFullscreen: true), nil,
            evidence: .attention), .destination(.exactAttention))
    }

    /// Chrome's fullscreen toolbar strip and its content window, as logged in #6094.
    private func chromeToolbar(isVisible: Bool = true) -> PhysicalSurface {
        physical(wid: 192, width: 2560, height: 158, isVisible: isVisible, isFullscreen: true)
    }

    private func chromeContent(isVisible: Bool = true) -> PhysicalSurface {
        physical(wid: 160, y: 122, width: 2560, height: 1318, isVisible: isVisible, isFullscreen: true)
    }

    /// Accessibility cannot describe the strip, and clicking into it named it on attention: it showed as a
    /// second, short-lived Chrome tile, preselected.
    func testExactAttentionTakesAnUndescribedFullscreenToolbarForItsWindow() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(chromeToolbar(), nil, evidence: .attention,
            describedSiblings: [chromeContent()]), .represent(parentWid: 160, .fullscreenChrome))
    }

    /// A window AppKit lets onto a fullscreen Space reads Space mask 0x40 there, so the strip may not carry
    /// the fullscreen bit its window does.
    func testExactAttentionTakesAnUndescribedFullscreenToolbarForItsWindowWhateverItsSpaceType() {
        let strip = physical(wid: 78, y: 30, width: 1280, height: 150)
        let content = physical(wid: 62, width: 1280, height: 832, isFullscreen: true)
        XCTAssertEqual(WindowAdmissionResolver.resolve(strip, nil, evidence: .attention,
            describedSiblings: [content]), .represent(parentWid: 62, .fullscreenChrome))
    }

    /// The content window ordered out means it is on a Space the display is not showing, so the strip is not
    /// its toolbar.
    func testExactAttentionAdmitsAnUndescribedFullscreenSurfaceBesideAnOrderedOutWindow() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(chromeToolbar(), nil, evidence: .attention,
            describedSiblings: [chromeContent(isVisible: false)]), .destination(.exactAttention))
    }

    /// A native tab of a fullscreen window shares its frame exactly, and the tab the user just switched to
    /// is named on attention before accessibility describes it.
    func testExactAttentionAdmitsAnUndescribedFullscreenTabOfADescribedWindow() {
        let tab = physical(wid: 2, width: 2560, height: 1440, isFullscreen: true)
        let active = physical(wid: 1, width: 2560, height: 1440, isFullscreen: true)
        XCTAssertEqual(WindowAdmissionResolver.resolve(tab, nil, evidence: .attention,
            describedSiblings: [active]), .destination(.exactAttention))
    }

    /// Two windows of one app side by side in Split View share a fullscreen Space without overlapping.
    func testExactAttentionAdmitsAnUndescribedSplitViewNeighbour() {
        let left = PhysicalSurface(wid: 1, pid: 7, bounds: CGRect(x: 0, y: 0, width: 1276, height: 1440),
            level: 0, isFullscreen: true)
        let right = PhysicalSurface(wid: 2, pid: 7, bounds: CGRect(x: 1284, y: 0, width: 1276, height: 1440),
            level: 0, isFullscreen: true)
        XCTAssertEqual(WindowAdmissionResolver.resolve(right, nil, evidence: .attention,
            describedSiblings: [left]), .destination(.exactAttention))
    }

    /// Once described, the surface is judged on what accessibility says about it, like any other.
    func testFullscreenToolbarRuleOnlyAppliesToAnUndescribedSurface() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(chromeToolbar(), semantic(), evidence: .attention,
            describedSiblings: [chromeContent()]), .destination(.exactAttention))
    }

    /// The gate binds attention too. ChatGPT's dictation strip takes the app's key focus the moment it
    /// appears, so a placement rule attention could walk past would hold for one focus event and no longer.
    func testExactAttentionDoesNotAdmitADescribedFloatingNonMainSurface() {
        let s = semantic(title: "ChatGPT", subrole: kAXDialogSubrole)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 720, height: 84, level: 3), s,
            evidence: .attention), .reject(.auxiliarySurface))
    }

    /// `kAXMain` is the positive vouch that survives the gate, on this channel like the other one.
    func testExactAttentionKeepsADescribedFloatingMainWindow() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 3), semantic(isMain: true),
            evidence: .attention), .destination(.exactAttention))
    }

    /// The same HUD at the ORDINARY window level, once accessibility has described it. Placement cannot
    /// separate it from a window any more, so the app's own answer has to: a group is not a destination
    /// however the focus reached it. Without this, attention outranked the refusal for the life of the wid.
    func testExactAttentionDoesNotSurviveANonWindowRole() {
        let s = semantic(title: "Recording", subrole: kAXUnknownSubrole, role: kAXGroupRole)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 720, height: 84), s,
            evidence: .attention), .reject(.nonWindowRole))
    }

    /// Emacs 29.4's frame as read in #6072. Discovery admits it on the subrole, so focusing it must not
    /// remove it: each removal re-added the window at the end of the switching order.
    func testExactAttentionKeepsAStandardWindowWithATextFieldRole() {
        let s = semantic(title: "emacs@host : main.tex", role: kAXTextFieldRole, isMain: true)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), s), .destination(.conventionalWindow))
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), s, evidence: .attention),
            .destination(.conventionalWindow))
    }

    /// A role accessibility FAILED to read is not a refusal. Attention still speaks for the surface, which is
    /// what keeps a window alive through an app that answers some attributes and not others.
    func testExactAttentionSurvivesARoleAccessibilityCouldNotRead() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(role: nil),
            evidence: .attention), .destination(.exactAttention))
    }

    func testMainWindowAcceptsUnknownSubroleAtAnyLevel() {
        let s = semantic(title: nil, subrole: kAXUnknownSubrole, isMain: true)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 1, height: 1, level: 3), s),
            .destination(.mainWindow))
    }

    func testStandardWindowDoesNotDependOnSize() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 1, height: 1), semantic()),
            .destination(.conventionalWindow))
    }

    func testStandardSubroleSurvivesMissingRole() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(role: nil)),
            .destination(.conventionalWindow))
    }

    func testTitledDialogIsDestination() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(subrole: kAXDialogSubrole)),
            .destination(.conventionalWindow))
    }

    /// ChatGPT's dictation strip once accessibility describes it, which is how it actually arrives: wid at
    /// level 3, 720x84 at the bottom of the screen, `AXWindow`/`AXDialog`, titled "ChatGPT", `AXMain` false
    /// (measured 2026-09-03). Nothing in that answer says HUD; only where the app put it does (#5565).
    func testChatGptDictationStripIsAuxiliary() {
        let s = semantic(title: "ChatGPT", subrole: kAXDialogSubrole)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 720, height: 84, level: 3), s),
            .reject(.auxiliarySurface))
    }

    /// The same gate over the other conventional subrole, so the fix does not depend on which of the two
    /// Chromium happens to report for a given overlay.
    func testFloatingNonMainStandardWindowIsAuxiliary() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 3), semantic()),
            .reject(.auxiliarySurface))
    }

    /// A window an app floats above the others and marks main is where the user would be restored to, so it
    /// keeps its place. This is what stops the gate from hiding an always-on-top document window.
    func testFloatingMainWindowKeepsItsPlace() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 3), semantic(isMain: true)),
            .destination(.mainWindow))
    }

    /// Covering the screen is the other positive vouch: the user is already there, whatever level the
    /// WindowServer parks the surface at.
    func testFullscreenSurfaceKeepsItsPlaceAboveTheOrdinaryLevel() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 101, isFullscreen: true), semantic()),
            .destination(.conventionalWindow))
    }

    func testUntitledDialogRemainsLatent() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(title: "", subrole: kAXDialogSubrole)),
            .latent(.untitledDialog))
    }

    func testFloatingPanelIsRejected() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(subrole: kAXFloatingWindowSubrole)),
            .reject(.auxiliarySurface))
    }

    func testMainFloatingPanelIsRejected() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(subrole: kAXFloatingWindowSubrole, isMain: true)),
            .reject(.auxiliarySurface))
    }

    func testAttentionDoesNotTurnFloatingPanelIntoDestination() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(subrole: kAXFloatingWindowSubrole),
            evidence: .attention), .reject(.auxiliarySurface))
    }

    func testNonMainCustomRootAtFloatingLevelIsAuxiliary() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 3), semantic(subrole: kAXUnknownSubrole)),
            .reject(.auxiliarySurface))
    }

    func testCustomRootWithUnknownMainFlagAtFloatingLevelIsAuxiliary() {
        let s = semantic(subrole: kAXUnknownSubrole, isMain: nil)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 3), s), .reject(.auxiliarySurface))
    }

    func testSteamLikeCustomRootNeedsNoAppException() {
        let s = semantic(title: "Steam", subrole: kAXUnknownSubrole)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), s), .destination(.customWindowRoot))
    }

    func testPowerPointLikePresentationNeedsNoAppException() {
        let s = semantic(title: "Slide Show", subrole: kAXUnknownSubrole, isMain: true)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(level: 3), s), .destination(.mainWindow))
    }

    func testCustomRootAtExactSizeBoundaryIsDestination() {
        let s = semantic(subrole: kAXUnknownSubrole)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 100, height: 50), s),
            .destination(.customWindowRoot))
    }

    func testUndersizedCustomRootRemainsLatent() {
        let s = semantic(subrole: kAXUnknownSubrole)
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(width: 99, height: 50), s),
            .latent(.undersizedCustomSurface))
    }

    func testNonWindowRoleIsRejected() {
        XCTAssertEqual(WindowAdmissionResolver.resolve(physical(), semantic(subrole: kAXUnknownSubrole, role: kAXButtonRole)),
            .reject(.nonWindowRole))
    }

    func testLevelZeroAndSubstantialNonZeroLevelAcquireSemantics() {
        XCTAssertTrue(WindowAdmissionResolver.shouldAcquireSemantics(physical(width: 1, height: 1)))
        XCTAssertTrue(WindowAdmissionResolver.shouldAcquireSemantics(physical(level: 3)))
    }

    func testSmallNonZeroLevelAndAttachedSurfacesSkipOrdinaryAcquisition() {
        XCTAssertFalse(WindowAdmissionResolver.shouldAcquireSemantics(physical(width: 20, height: 20, level: 3)))
        XCTAssertFalse(WindowAdmissionResolver.shouldAcquireSemantics(physical(parentWid: 2)))
    }

    func testMutableEvidenceIsReevaluatedWithoutLatching() {
        let p = physical()
        XCTAssertEqual(WindowAdmissionResolver.resolve(p, semantic()), .destination(.conventionalWindow))
        XCTAssertEqual(WindowAdmissionResolver.resolve(p, semantic(title: nil, subrole: kAXUnknownSubrole)),
            .latent(.unsupportedSemantics))
        XCTAssertEqual(WindowAdmissionResolver.resolve(p, semantic(title: nil, subrole: kAXUnknownSubrole, isMain: true)),
            .destination(.mainWindow))
    }
}

/// Pins the two rules that keep a remembered refusal from becoming a bug (`ApplicationVerdictCache`): it
/// must not answer for an attention lookup, and it must not outlive the process it described.
final class ApplicationVerdictCacheTests: XCTestCase {
    private let recorded = RefusedApplication(bundleId: "com.apple.appkit.xpc.ThemeWidgetControlViewService")

    func testNoRecordAlwaysAsksAgain() {
        XCTAssertFalse(ApplicationVerdictCache.refusalStillAnswers(nil, bundleId: "com.acme.app",
            evidence: .discovery))
    }

    func testSameProcessRefusedAgainWithoutAsking() {
        XCTAssertTrue(ApplicationVerdictCache.refusalStillAnswers(recorded,
            bundleId: "com.apple.appkit.xpc.ThemeWidgetControlViewService", evidence: .discovery))
    }

    /// The user went to it, and `ApplicationAdmissionResolver` admits an XPC process on attention. Inheriting
    /// the discovery refusal here would drop the window they just clicked.
    func testAttentionNeverInheritsADiscoveryRefusal() {
        XCTAssertFalse(ApplicationVerdictCache.refusalStillAnswers(recorded,
            bundleId: "com.apple.appkit.xpc.ThemeWidgetControlViewService", evidence: .attention))
    }

    /// macOS reuses pids. A refusal that outlived its process would make a real app permanently invisible.
    func testReusedPidWithADifferentBundleIdIsAskedProperly() {
        XCTAssertFalse(ApplicationVerdictCache.refusalStillAnswers(recorded, bundleId: "com.acme.app",
            evidence: .discovery))
    }

    /// Both nil is a match: two nil-bundle processes are indistinguishable here, and the per-pid drop on
    /// termination is what bounds that.
    func testNilBundleIdsMatchEachOther() {
        XCTAssertTrue(ApplicationVerdictCache.refusalStillAnswers(RefusedApplication(bundleId: nil),
            bundleId: nil, evidence: .discovery))
        XCTAssertFalse(ApplicationVerdictCache.refusalStillAnswers(RefusedApplication(bundleId: nil),
            bundleId: "com.acme.app", evidence: .discovery))
    }
}

final class ApplicationAdmissionResolverTests: XCTestCase {
    func testOrdinaryApplicationIsAdmittedDuringDiscovery() {
        XCTAssertTrue(ApplicationAdmissionResolver.accepts(isXpc: false, isZombie: false,
            isKnownUserFacingException: false, evidence: .discovery))
    }

    func testUnengagedXpcProcessIsNotAdmittedDuringDiscovery() {
        XCTAssertFalse(ApplicationAdmissionResolver.accepts(isXpc: true, isZombie: false,
            isKnownUserFacingException: false, evidence: .discovery))
    }

    func testExactAttentionAdmitsItsXpcOwner() {
        XCTAssertTrue(ApplicationAdmissionResolver.accepts(isXpc: true, isZombie: false,
            isKnownUserFacingException: false, evidence: .attention))
    }

    func testKnownUserFacingXpcExceptionStillWorksDuringDiscovery() {
        XCTAssertTrue(ApplicationAdmissionResolver.accepts(isXpc: true, isZombie: false,
            isKnownUserFacingException: true, evidence: .discovery))
    }

    func testZombieIsRejectedEvenWhenAttentionNamesIt() {
        XCTAssertFalse(ApplicationAdmissionResolver.accepts(isXpc: false, isZombie: true,
            isKnownUserFacingException: false, evidence: .attention))
    }

    /// The window manager is a regular process, so nothing else refuses it; and a click on the desktop is
    /// exact attention on one of its surfaces, so the refusal has to hold for attention too.
    func testWindowManagerIsRejectedEvenWhenAttentionNamesIt() {
        XCTAssertFalse(ApplicationAdmissionResolver.accepts(isXpc: false, isZombie: false,
            isKnownUserFacingException: false, isWindowManager: true, evidence: .discovery))
        XCTAssertFalse(ApplicationAdmissionResolver.accepts(isXpc: false, isZombie: false,
            isKnownUserFacingException: false, isWindowManager: true, evidence: .attention))
    }
}

final class ApplicationPidResolverTests: XCTestCase {
    func testWindowServerPidSurvivesAnInvalidRunningApplicationPid() {
        XCTAssertEqual(ApplicationPidResolver.resolve(discoveredPid: 42, reportedPid: -1), 42)
    }

    func testDiscoveredPidRemainsCanonicalWhenLaunchServicesChanges() {
        XCTAssertEqual(ApplicationPidResolver.resolve(discoveredPid: 42, reportedPid: 99), 42)
    }

    func testRunningApplicationPidIsUsedWithoutDiscoveryEvidence() {
        XCTAssertEqual(ApplicationPidResolver.resolve(discoveredPid: nil, reportedPid: 42), 42)
    }

    func testInvalidPidsDoNotCreateAnApplicationIdentity() {
        XCTAssertNil(ApplicationPidResolver.resolve(discoveredPid: nil, reportedPid: -1))
        XCTAssertNil(ApplicationPidResolver.resolve(discoveredPid: 0, reportedPid: 0))
    }
}

final class WindowlessApplicationResolverTests: XCTestCase {
    private func accepts(isRegular: Bool = false, isTerminated: Bool = false,
                         hasPlaceholder: Bool = false, hasWindow: Bool = false) -> Bool {
        WindowlessApplicationResolver.shouldCreate(isRegular: isRegular, isTerminated: isTerminated,
            hasExistingPlaceholder: hasPlaceholder, hasNonPhantomWindow: hasWindow)
    }

    func testRegularWindowlessApplicationGetsPlaceholder() {
        XCTAssertTrue(accepts(isRegular: true))
    }

    func testAccessoryApplicationNeverGetsPlaceholder() {
        XCTAssertFalse(accepts())
    }

    func testExistingPlaceholderRealWindowAndTerminationPreventPlaceholder() {
        XCTAssertFalse(accepts(isRegular: true, hasPlaceholder: true))
        XCTAssertFalse(accepts(isRegular: true, hasWindow: true))
        XCTAssertFalse(accepts(isRegular: true, isTerminated: true))
    }
}
