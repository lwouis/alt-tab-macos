import XCTest

/// Pins exactly when the menubar "AltTab is running without Screen Recording permissions" callout
/// shows vs. stays hidden, and which feature(s) it names (see #5623). The callout used to appear
/// whenever the permission was missing and always blamed Thumbnails; it now only appears when the
/// permission is missing AND the user's settings actually use it (Thumbnails appearance style or the
/// preview-selected-window overlay), and its copy names whichever of the two are affected.
///
/// `PermissionCalloutResolver` is the pure decision kernel, split in two:
///   - `dependentFeatures` — which Screen-Recording features do the settings rely on (none / thumbnails
///     / previews / both)?
///   - `shouldShowCallout` — given the permission state and the affected features, show?
///
/// Production wires these to real state: `screenRecordingGranted` is `ScreenRecordingPermission.status
/// == .granted` (so both `.skipped` and `.notGranted` map to `false`), and `dependentFeatures` is
/// `Preferences.screenRecordingDependentFeatures`, which OR-s each feature flag over every shortcut
/// slot — so a per-shortcut override that enables Thumbnails/Preview on any one slot flips it on.
/// The shown copy reuses the existing "Thumbnails" translation; only the subject of the sentence varies.
final class PermissionCalloutResolverTests: XCTestCase {

    // MARK: - Which features the settings depend on

    /// Thumbnails style on, Preview off → only Thumbnails depends on the permission.
    func testThumbnailsOnlyClassifiedAsThumbnails() {
        XCTAssertEqual(PermissionCalloutResolver.dependentFeatures(
            usesThumbnails: true, usesPreviews: false), .thumbnails)
    }

    /// Preview on, Thumbnails off (e.g. Titles/App Icons + Preview) → only Previews depend on it.
    func testPreviewsOnlyClassifiedAsPreviews() {
        XCTAssertEqual(PermissionCalloutResolver.dependentFeatures(
            usesThumbnails: false, usesPreviews: true), .previews)
    }

    /// Both features on → both depend on it; the callout names both.
    func testBothFeaturesClassifiedAsBoth() {
        XCTAssertEqual(PermissionCalloutResolver.dependentFeatures(
            usesThumbnails: true, usesPreviews: true), .both)
    }

    /// Neither feature on (Titles/App Icons, Preview off) → nothing depends on the permission. This is
    /// the issue-#5623 case: no screenshots are ever taken, so the callout must stay hidden.
    func testNeitherFeatureClassifiedAsNone() {
        XCTAssertEqual(PermissionCalloutResolver.dependentFeatures(
            usesThumbnails: false, usesPreviews: false), .none)
    }

    // MARK: - When the callout shows vs. stays hidden

    /// Permission granted → never show, even if features use Screen Recording (they work fine).
    func testGrantedNeverShowsEvenWhenUsed() {
        XCTAssertFalse(PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: true, dependentFeatures: .both))
    }

    /// Permission granted and nothing uses it → still never show.
    func testGrantedNeverShowsWhenUnused() {
        XCTAssertFalse(PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: true, dependentFeatures: .none))
    }

    /// Permission missing (skipped or never granted) and Thumbnails is used → SHOW (names Thumbnails).
    func testMissingPermissionShowsForThumbnails() {
        XCTAssertTrue(PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: false, dependentFeatures: .thumbnails))
    }

    /// Permission missing and only Preview is used → SHOW (names Window previews).
    func testMissingPermissionShowsForPreviews() {
        XCTAssertTrue(PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: false, dependentFeatures: .previews))
    }

    /// Permission missing and both features are used → SHOW (names both).
    func testMissingPermissionShowsForBoth() {
        XCTAssertTrue(PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: false, dependentFeatures: .both))
    }

    /// Permission missing but no feature uses it → HIDE. The user skipped the permission and uses
    /// neither Thumbnails nor Preview, so nagging them is pointless (the regression #5623 fixes).
    func testMissingPermissionHiddenWhenUnused() {
        XCTAssertFalse(PermissionCalloutResolver.shouldShowCallout(
            screenRecordingGranted: false, dependentFeatures: .none))
    }
}
