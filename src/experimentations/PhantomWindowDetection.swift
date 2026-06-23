// Phantom Window Detection — Investigation Results
// =================================================
//
// "Phantom windows" are windows that exist in macOS APIs (AX returns them as standard
// windows with valid CGWindowIDs) but are invisible to the user. Common producers:
//
//   - Microsoft Outlook reminders (alpha=0 NSWindow kept alive after dismissal)
//   - Electron BrowserWindow({show: false}) and BrowserWindow.hide() — calls
//     [window_ orderOut:nil] in shell/browser/native_window_mac.mm; the NSWindow
//     is preserved, AX still hands it back, but kCGWindowIsOnscreen flips false
//   - Electron BrowserWindow.setOpacity(0) — calls [window_ setAlphaValue:0.0]
//   - WeChat / Teams / DingTalk — hide windows via alpha=0 + size manipulation,
//     never destroying the NSWindow
//
// Reported instances: #5170 #5448 (Outlook), #5495 (Joplin), #5496 (Sprig),
// #5530 (Zoom, Shottr), #5508 (WeChat, DingTalk). Tracked under #5509.
//
// MARK: - The detection signal we use
//
// Two CGS queries via Spaces.windowsInSpaces (src/switcher/state/Spaces.swift —
// wraps CGSCopyWindowsWithOptionsAndTags):
//
//   visibleCgsWindowIds = windowsInSpaces(allSpaces, false)  // excludes .invisible1/.invisible2
//   allCgsWindowIds     = windowsInSpaces(allSpaces, true)   // includes them
//
// Two strengths of "phantom":
//
//   1. Strongest: WID is missing from BOTH queries. CGS has dropped the window
//      entirely from every space. Empirically this is what Joplin's invisible
//      windows look like — wid=26854 inVisible=false inAll=false spaceIds=[].
//      Likely Electron BrowserWindow.hide() / show:false → orderOut: + the
//      WindowServer eventually evicts the WID from its tracking entirely.
//
//   2. Weaker: WID present in allCgsWindowIds but missing from visibleCgsWindowIds.
//      This is the "tagged invisible" v10.9 signal. Catches alpha=0 windows (Outlook
//      reminders) that CGS still tracks but tags as invisible. Needs disambiguation
//      against tabs / minimized / hidden / other-Space (those also live here).
//
// MARK: - Why it wasn't safe in v10.9, and is now
//
// In v10.9, the same signal was used to classify tabs:
//   isTabbed = !visibleCgsWindowIds.contains(wid)
// The CGS "invisible" bucket is a SUPERSET of:
//
//   { phantom windows ∪ inactive OS tabs ∪ minimized ∪ other-Space ∪ hidden-app }
//
// So that v10.9 heuristic produced false positives — Teams/WeChat windows that
// hide themselves were misclassified as tabs (see TabbedWindowDetection.swift
// lines 14-21 for the original write-up).
//
// v10.10 replaced the tab heuristic with AX-based AXTabGroup walking
// (src/switcher/state/TabGroup.swift). isTabbed is now definitive and authoritative.
//
// With AX carving tabs out of the bucket, the remaining members of the CGS
// invisible bucket are exactly { minimized, other-Space, hidden-app, phantom }.
// We already track the first three on Window — so subtracting them leaves
// phantom windows alone.
//
// MARK: - Disambiguation table (in order)
//
//   wid not in allCgsWindowIds?              →  PHANTOM (strongest signal — Joplin et al.)
//   wid in visibleCgsWindowIds?              →  not a phantom (currently rendered)
//   isMinimized?                             →  not a phantom (legitimate, showMinimizedWindows)
//   application.isHidden?                    →  not a phantom (legitimate, showHiddenWindows)
//   isTabbed?                                →  not a phantom (legitimate inactive tab; AX-confirmed)
//   spaceIds non-empty AND ∩ visibleSpaces == ∅?  →  not a phantom (other-Space window)
//   else                                     →  phantom (alpha=0 case)
//
// Important: empty spaceIds is NOT "on another Space" — it's "CGS doesn't know where it
// is", which itself is a phantom signal. The earlier draft of this code conflated the two
// and let Joplin's phantoms through.
//
// MARK: - Why we run the check post-show, off-main
//
// The check is wired into Applications.manuallyRefreshAllWindows() — armed by a one-shot
// kCFRunLoopObserver(.beforeWaiting) right after the switcher shows. It runs alongside:
//   syncSpacesState()                — re-derives per-window Space membership
//   refreshWindowsViaWindowServer()  — discovers new windows + computes the phantom verdict
//   reviewExistingWindows()          — refreshes the AX-only attrs (title/subrole/tabs/minimized)
//   discardDeadPhantomWindows()      — drops phantoms the OS confirms are gone
//
// This way:
//   - the synchronous show path (Windows.updatesBeforeShowing) is untouched
//   - by the time we read isTabbed, the AX reads have landed on main
//   - the WindowServer/CGS queries happen off-main via CGSCallScheduler
//
// First show may briefly include a phantom; the next show clears it.
//
// MARK: - Approaches considered and rejected
//
// 1. kCGWindowAlpha < 0.01 (per-window CGWindowListCopyWindowInfo)
//    Catches the alpha=0 case (Outlook) but misses every Electron orderOut:
//    case (Joplin, Sprig, DingTalk). Also costs N CG calls per show.
//
// 2. kCGWindowIsOnscreen via batched CGWindowListCopyWindowInfo
//    Equivalent signal to the CGS list but uses public API. We use the CGS list
//    instead because it's already what Spaces.windowsInSpaces returns and what
//    other parts of the codebase trust.
//
// 3. Filtering at WindowDiscriminator.isActualWindow (one-time at discovery)
//    Doesn't work — phantom state often appears AFTER discovery (e.g. an Outlook
//    reminder that fires hours after launch).
//
// 4. Per-app exception list expansion only
//    Status quo. Issue #5509 exists because per-app config doesn't scale to the
//    long tail of Electron / Office / IM apps.
