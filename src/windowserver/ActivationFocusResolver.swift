import CoreGraphics
import Foundation

/// The per-app state tracked from a `didActivateApplication` notification: which windows the activation may
/// raise (each raise 808 consumes its entry), until when the activation is considered in flight, and whether
/// the activation's focus 808 has already bumped the MRU.
struct ActivationEntry: Equatable {
    var wids: Set<CGWindowID>
    var until: TimeInterval
    var focusBumped = false
}

/// Pure decisions for MRU focus around app activation, extracted from `WindowServerEvents` after two
/// regressions in a row (#5596). The recorded ground truth (TextEdit, iTerm; Cmd+Tab and click activations):
/// on activation macOS emits 808s for the app's on-Space windows — the FIRST is the genuinely FOCUSED window,
/// the rest (when there is a storm at all) are RAISES front-to-back; sometimes there is NO storm, just the
/// single focus 808. So the first 808 of an activation must bump (it is the truth, and
/// `NSRunningApplication.isActive` can still read false at that instant), the raise tail must be swallowed
/// (re-fronting it reverses the app's MRU), and the async AX focused-window read (the backstop for
/// activations that emit no 808) must YIELD once a real 808 has spoken — it races the app's internal focus
/// update and can return the PREVIOUS window (iTerm). See `ActivationFocusResolverSpecs.md`.
enum ActivationFocusResolver {
    /// The verdict for one focus event (808): whether to bump the MRU, and the entry state to store back.
    struct FocusDecision: Equatable {
        var bump: Bool
        var entry: ActivationEntry?
    }

    /// Decide a tracked window's 808. `entry` is the app's activation state (nil when no activation is in
    /// flight); an expired entry is pruned (returned nil) and ignored. A brand-new window's first focus always
    /// bumps (it may arrive while the app already went background — cmd-N spam). The first 808 of a live
    /// activation bumps regardless of `appIsActive` (separate clocks); a subsequent 808 for a wid still in the
    /// snapshot is a raise and is swallowed; anything else falls to the normal rule: bump iff the app is active.
    static func onFocusEvent(_ entry: ActivationEntry?, wid: CGWindowID, now: TimeInterval,
                             wasJustCreated: Bool, appIsActive: Bool) -> FocusDecision {
        guard var entry, entry.until > now else {
            return FocusDecision(bump: wasJustCreated || appIsActive, entry: nil)
        }
        let isFirstFocusOfActivation = !entry.focusBumped
        let isActivationRaise = entry.focusBumped && entry.wids.contains(wid)
        entry.wids.remove(wid)
        if isFirstFocusOfActivation { entry.focusBumped = true }
        let bump = wasJustCreated || isFirstFocusOfActivation || (appIsActive && !isActivationRaise)
        return FocusDecision(bump: bump, entry: entry)
    }

    /// Build the activation entry when an app activates. When the activation was ALTTAB-INITIATED (the
    /// switcher just focused `altTabTarget`, same app, fresh), the target is KNOWN — no need to divine it
    /// from events: bump it directly and mark the entry `focusBumped`, so the raise tail is swallowed and the
    /// stale-prone AX backstop yields. Without a known target, a plain entry is returned and the focus comes
    /// from the first 808 (or the AX backstop when none arrives). This closes the last race for the app's own
    /// switches: with no 808 and a stale AX read, the freshly-focused window's bump was otherwise lost.
    static func onActivation(snapshotWids: Set<CGWindowID>, until: TimeInterval,
                             altTabTarget: CGWindowID?) -> (entry: ActivationEntry, bumpWid: CGWindowID?) {
        if let target = altTabTarget {
            return (ActivationEntry(wids: snapshotWids, until: until, focusBumped: true), target)
        }
        return (ActivationEntry(wids: snapshotWids, until: until), nil)
    }

    /// Whether the AX focused-window backstop may apply its result. It is the WEAK signal — the read races the
    /// app's internal focus update and can return the previous window — so it only applies while the
    /// activation's focus 808 hasn't spoken. (No entry ⇒ apply: the backstop also serves activations whose
    /// entry already expired or was never created.)
    static func axBackstopShouldApply(_ entry: ActivationEntry?) -> Bool {
        entry?.focusBumped != true
    }
}
