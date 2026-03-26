// Tabbed Window Detection — Investigation Results
// =================================================
//
// macOS provides no public API to detect whether a window is an inactive OS tab.
// This file documents all approaches tested and their results.
//
// Test setup: Finder with 2 tabbed windows ("lwouis" inactive tab, "git" active tab)
// and 1 non-tabbed window ("Movies").
//
// MARK: - Approaches that DON'T work
//
// 1. CGWindowListCopyWindowInfo
//    Returns the fewest windows. Inactive tabs don't appear at all.
//    Can't distinguish "absent because tabbed" from "absent for other reasons."
//
// 2. CGSCopyWindowsWithOptionsAndTags (current heuristic)
//    Comparing include-invisible vs exclude-invisible lists: inactive tabs appear
//    in the include-invisible list but not the exclude-invisible list. However, so
//    do windows from apps like Teams/WeChat that hide windows without destroying
//    them. This is the source of false positives in the current detection.
//
// 3. SCShareableContent (macOS 13+)
//    Returns the most windows (including inactive tabs). However isActive=false and
//    isOnScreen=false for inactive tabs — same as for hidden, minimized, and
//    other-space windows. No distinguishing signal.
//
// 4. SLSWindowIterator (parentId, tags, attributes, attachedWindows, spaceAttributes)
//    - parentId: returns 0 for all tested windows (tabbed and non-tabbed)
//    - attachedCount/attachedWindows: always 0/empty for tabbed windows
//    - spaceAttributes/spaceTypeMask: no difference between tabbed and non-tabbed
//    - tags (UInt from iterator): different patterns exist between visible and invisible
//      windows, but the same pattern applies to both inactive tabs AND other invisible
//      windows (hidden apps, other-space windows). No tab-specific bit.
//
// 5. SLSGetWindowTags (64-bit tags)
//    Compared binary tag patterns across window states:
//      Active tab (git):    1100000000000000000000000100000000010010000010000000000001
//      Non-tabbed (Movies): 1100000000000000000000000100000000010010000010000000000001
//      Inactive tab (lwouis): 1100000000000000000000000100000000010010000000000000000001
//    The inactive tab differs in a few bits, but the same pattern appears for hidden
//    and other-space windows. Not a reliable tab-specific signal.
//
// 6. SLSGetWindowSubLevel
//    Returns 0 for all normal layer-0 windows regardless of tab state.
//
// 7. CGSCopyWindowGroup (movementGroup, orderingGroup, tabGroup, tabbingGroup)
//    - movementGroup: empty for tabbed windows
//    - orderingGroup: empty for tabbed windows
//    - tabGroup: empty (speculative key, doesn't exist)
//    - tabbingGroup: empty (speculative key, doesn't exist)
//
// 8. CGSCopyWindowProperty (broad key sweep)
//    Tested ~40 speculative keys including kCGSWindowTabGroupID, kCGSWindowIsTab,
//    kCGSWindowTabParent, kCGSWindowTabIndex, kCGSWindowTabbingIdentifier,
//    kCGSWindowContainerID, TabGroupID, IsTab, etc.
//    Only kCGSWindowTitle returned values. No tab-related properties exist.
//
// 9. SLSCopyAssociatedWindows
//    Returns only the queried window itself. No sibling information.
//
// 10. Frame-based clustering (CGWindowListCopyWindowInfo frame comparison)
//     Grouping same-pid windows by identical frame: the active tab's frame is known,
//     but inactive tabs have a DIFFERENT frame (their last known position before being
//     tabbed). Only works if tabs were at the same position before merging, which is
//     not guaranteed. Unreliable.
//
// MARK: - Approach that WORKS: AXTabGroup (Accessibility API)
//
// Querying kAXChildrenAttribute on a window's AXUIElement reveals an AXTabGroup child
// element when the window has OS-level tabs. The AXTabGroup's children are the individual
// tab buttons. This provides a definitive, reliable signal.
//
// How it works:
// 1. Get kAXChildrenAttribute on the window's AXUIElement
// 2. Find the child with kAXRoleAttribute == "AXTabGroup"
// 3. Get that child's kAXChildrenAttribute
// 4. Filter children to those with kAXSubroleAttribute == "AXTabButton"
//    (this excludes the "+" button which has role=AXButton, subrole=nil)
// 5. Each AXTabButton has:
//    - kAXTitleAttribute: the tab's title (matches the window title)
//    - kAXValueAttribute: 1 for active tab, 0 for inactive tab
//    - _AXUIElementGetWindow: returns the parent window's WID (not individual tab WIDs)
//
// Example output for Finder with tabs "lwouis" and "git" (git is active):
//   AXTabGroup has 3 children:
//     [0] role=AXRadioButton subrole=AXTabButton title='lwouis' value=0
//     [1] role=AXRadioButton subrole=AXTabButton title='git'    value=1
//     [2] role=AXButton      subrole=nil          title=''      value=nil  ← "+" button
//
// Non-tabbed windows (e.g. "Movies") have no AXTabGroup child at all.
//
// Properties:
// - Definitive: presence of AXTabGroup = tabbed, absence = not tabbed
// - Rich: provides tab count and all tab titles
// - Public API: uses standard Accessibility framework (no private APIs needed)
// - Works cross-space: querying via an existing AXUIElement reference works even
//   when the window is on a different Space (unlike kAXWindowsAttribute on the app
//   element, which only returns windows on the current Space)
// - Limitation: _AXUIElementGetWindow on tab buttons returns the parent window WID,
//   not individual tab WIDs. Matching tabs to windows must use title comparison.
//
// Implementation: see AXUIElement.tabGroupInfo() in src/api-wrappers/AXUIElement.swift
