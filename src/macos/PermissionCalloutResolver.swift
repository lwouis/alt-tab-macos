import Foundation

/// Pure decisions for the menubar "AltTab is running without Screen Recording permissions" callout
/// (see #5623): both whether to surface it and which feature(s) it should name.
/// `PermissionCalloutResolver` is callable in tests with no AppKit / Preferences / UserDefaults
/// dependencies, so we can pin exactly when the callout shows vs. stays hidden and which message it
/// shows.
///
/// Screen Recording is consumed by exactly two features: the Thumbnails appearance style (window
/// screenshots) and the "preview selected window" overlay. So the callout is only worth showing to a
/// user who lacks the permission AND has at least one shortcut configured to use one of them — and
/// its copy names whichever of the two are actually affected, so it never promises back a feature the
/// user doesn't use. A user who skipped the permission but uses neither gains nothing by granting it,
/// so we don't nag them.
enum PermissionCalloutResolver {
    /// The Screen-Recording-dependent feature(s) the user's settings rely on, aggregated across all
    /// shortcuts. Drives both whether the callout shows (`.none` → never) and which message it shows.
    enum DependentFeatures: Equatable {
        /// No shortcut uses Thumbnails or Preview — the permission is irrelevant, callout stays hidden.
        case none
        /// At least one shortcut uses the Thumbnails appearance style; none uses Preview.
        case thumbnails
        /// At least one shortcut uses the preview-selected-window overlay; none uses Thumbnails.
        case previews
        /// Both features are used across the user's shortcuts.
        case both
    }

    /// Classify the two independent "used by any shortcut" flags into the affected feature set.
    /// - `usesThumbnails`: any shortcut's effective appearance style is Thumbnails (`.thumbnails`).
    ///   The other two styles (`.titles`, `.appIcons`) render no window screenshots, so they pass `false`.
    /// - `usesPreviews`: any shortcut shows the preview-selected-window overlay.
    static func dependentFeatures(usesThumbnails: Bool, usesPreviews: Bool) -> DependentFeatures {
        switch (usesThumbnails, usesPreviews) {
            case (true, true): return .both
            case (true, false): return .thumbnails
            case (false, true): return .previews
            case (false, false): return .none
        }
    }

    /// Whether the menubar permission callout should be shown.
    /// - `screenRecordingGranted`: the OS permission is granted. When `true` the callout is pointless
    ///   and is never shown, regardless of settings. When `false` the permission is missing — whether
    ///   the user actively skipped it or simply never granted it (both map to `false` here).
    /// - `dependentFeatures`: which features the user's settings rely on (the OR across all shortcuts).
    ///   `.none` means no shortcut needs the permission, so the callout is suppressed even though the
    ///   permission is missing — the user gains nothing by granting it.
    static func shouldShowCallout(screenRecordingGranted: Bool, dependentFeatures: DependentFeatures) -> Bool {
        !screenRecordingGranted && dependentFeatures != .none
    }
}
