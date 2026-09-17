import Cocoa

/// Pure decision kernel for `AXUIElement.windowsByBruteForce`: given one remote AX element found during the
/// brute-force scan, is it the ROOT window element for its requested wid — or merely one of that window's
/// descendants that happens to resolve to the same wid?
///
/// `_AXUIElementGetWindow` returns the CONTAINING window's id for a window's descendants too, so every
/// button, outline, tab bar, and menu of the target window also matches its wid. Those descendants often sit
/// at a LOWER AXUIElementID than the window element itself, so a scan that stopped at the first wid match
/// handed admission a descendant (role `AXOutline` / `AXGroup` / `AXTabGroup` / `AXMenuButton`,
/// subrole nil), which was rightly rejected — and the window vanished from the switcher entirely (#5849, the
/// v11.4 WindowServer-migration regression: the old fallback filtered by subrole, the migration dropped it).
///
/// The fix is a root check: the target's root window element is the one whose role is `AXWindow`. Subrole is
/// judged downstream by `WindowAdmissionResolver` (a real window can be `AXStandardWindow` or `AXDialog`), so we
/// gate on ROLE here, not subrole — filtering by standard subrole alone would drop apps with nonstandard
/// trees. `windowsByBruteForce` is the thin impure adapter: it keeps the cheap requested-wid gate first (so
/// the role read costs IPC only on target windows' descendants) and routes each verdict through this kernel.
enum BruteForceWindowMatch {
    /// True iff `candidate` is the target's root window element: it owns the target wid AND its role is
    /// `AXWindow`. A descendant sharing the wid (any non-`AXWindow` role) returns false, so the scan keeps
    /// going until it reaches the real window element.
    static func isTargetWindowRoot(candidateWid: CGWindowID?, candidateRole: String?, targetWid: CGWindowID) -> Bool {
        candidateWid == targetWid && candidateRole == kAXWindowRole
    }

    /// WHOSE tab is this? The inactive-tab scan is run for ONE window's missing tabs and matches candidates on
    /// TITLE alone, which cannot tell two windows apart at all: two Finder windows browsing the same folders
    /// each have a tab called "lwouis". Captured live (2026-08-01) — the scan run for window A adopted a tab
    /// of window B, and when the user later switched to that tab it became the REPRESENTATIVE of A's group, so
    /// every real member of A stopped being drawn and A vanished from the switcher entirely.
    ///
    /// `WindowAdmissionResolver`'s physical acquisition gate does not reach this: an inactive tab of another window is not on
    /// screen either, so it looks exactly like one of ours.
    ///
    /// The separating fact is where the candidate SITS. A tab is positioned by its parent window, so a
    /// candidate parked exactly on another of this app's tracked windows is that window's tab, not the
    /// requester's. Deliberately one-sided rather than "it must match the requester": Merge All Windows never
    /// converges the absorbed windows' frames — they keep their own cascade positions, frozen — so demanding a
    /// match would make a merged group's tabs permanently un-adoptable. Those frozen frames sit on
    /// top of nothing, so this rule waves them through.
    ///
    /// Position only, not size: a tabbed window's members diverge in size as the tab bar resizes them, which is
    /// the same reason `TabGroupResolver.framePartitions` keys on position.
    ///
    /// **A candidate is never its own blocker**, which is why the frames carry wids rather than being bare
    /// rectangles. The caller reads `otherWindowsOfApp` from the surface inventory, whose rows go stale in
    /// exactly the situation this gate runs in: Merge All Windows orders the absorbed windows out, the
    /// inventory keeps their last-known `visible` bit until a full sweep refreshes it, and the candidate's
    /// own stale row then sits at the candidate's own frozen frame. Without the wid the rule read "parked on
    /// another window" off the candidate itself and deferred it to a window that no longer exists, so the
    /// tab was never adopted and its row never refreshed — a deadlock, measured live 2026-09-17 on a 6-tab
    /// merge where two tabs were lost from the group for good.
    static func isPlausibleInactiveTab(candidateWid: CGWindowID, candidate: CGRect, requester: CGRect?,
                                       otherWindowsOfApp: [(wid: CGWindowID, frame: CGRect)]) -> Bool {
        guard let requester else { return true }
        if samePosition(candidate, requester) { return true }
        return !otherWindowsOfApp.contains { $0.wid != candidateWid && samePosition(candidate, $0.frame) }
    }

    /// Rounded exact equality, the same test `TabGroupResolver.samePosition` applies — tabs of one window are
    /// at their parent's origin, so any offset means a different window.
    private static func samePosition(_ a: CGRect, _ b: CGRect) -> Bool {
        Int(a.origin.x.rounded()) == Int(b.origin.x.rounded()) && Int(a.origin.y.rounded()) == Int(b.origin.y.rounded())
    }
}
