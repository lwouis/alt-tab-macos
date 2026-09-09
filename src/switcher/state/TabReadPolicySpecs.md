# TabReadPolicy

Decides which tracked windows pay for an OS-tab read (`AXTabGroup`) on a given switcher show.

## Why it exists

`AXUIElement.tabGroupInfo` looks for an `AXTabGroup` among a window's **direct children**. There is no OS
batch across elements, so it costs **one Mach round trip per child**, and a window with no tabs pays for all
of them before concluding there is no tab bar. An ordinary AppKit window exposes several children (window
buttons, a toolbar, a split group), so reading every tracked window on every show ran to several hundred
round trips per summon, spread across as many processes — each able to stall a bounded worker for the whole
1s messaging timeout.

The per-show read was never the mechanism that keeps tab groups correct. Every real change already
announces itself:

| change | signal that already exists |
|---|---|
| tab opened / closed | WindowServer 811 / 804 (a tab is a window) |
| active tab switched | `AXMainWindowChanged` naming the wid |
| tab renamed | `AXTitleChanged` → `Applications.applyObservedTitle` |
| tab dragged out | the reducer's own drag-out re-check |

So the read is a **backstop**, and this policy sizes it like one.

## The rules, in order

1. **Never read before** (`lastReadGeneration == nil`) → read. Nothing is known about this window's tabs.
2. **App capability unknown** → read. No window of this app has answered yet, so we cannot even say whether
   it is a tabbing app.
3. **The app gained or lost a window since this window's last read** → read. That is the shape of every tab
   open, close, tear-off and merge, so the grouping may be stale.
4. **Otherwise** → skip, except for the `backstopReadsPerPass` (5) stalest windows, which are re-read so a
   notification that never arrived is corrected within a few summons.

Ties in staleness break towards apps that have actually shown a tab group, then by wid so the order is
total and the tests are deterministic.

### Deliberately not a rule

"This app has tabs, so read all its windows every show." Finder and Terminal are precisely the apps with the
most windows and the most children per window, and they are also the apps the event signals cover best.
Capability only **orders** the backstop; it never forces a read on its own.

## Why the app's window set is a version, not a count

Closing one tab and opening another between two shows leaves the count unchanged while the grouping has
entirely moved. `Windows.appWindowSetVersion` is bumped on every append and every removal, and
`Applications.noteTabRead` records the version a read was ISSUED against (not the one current when its
answer lands, which would mark a window up to date with a window set that changed mid-flight).

## What the caller does with a skip

`Applications.refreshWindowTitleAndTabs(_:_:_:reconcileTabs:)` reads `reconcileTabs: false` as "drop
`kAXChildren` from the attribute batch and skip the child walk". When the app also holds a live
`AXTitleChanged` subscription it skips **the whole call**, because a title-only read is work the notification
has already done. So a skipped window costs either one round trip (title) or zero.

That second skip makes this policy the **title** backstop as well: for an app that pushes titles, the windows
elected here are the only ones whose title a show re-reads. The push is the mechanism
(`AxObserverRegistry.refreshTitle`), and it only trusts a `kAXWindowRole` element: a rename announced on an
inner node is dropped, so the window is never labelled with that node's empty title (#6011).

## Test scenarios

### A. Always read (rules 1-3)
- **testNeverReadIsRead** — a window whose tabs have never been read is always read.
- **testUnknownCapabilityIsRead** — a window of an app we have learned nothing about yet is always read.
- **testStructuralChangeIsRead** — the app gained or lost a window since this window's last read, so its
  grouping may be stale.

### B. Settled windows are skipped
- **testSettledNonTabbingWindowIsSkipped** — a settled window of an app that has never shown tabs is skipped
  once the backstop budget is spent.
- **testSettledTabbingWindowIsSkipped** — the same for a tabbing app: capability alone never forces a read,
  which is the rule that makes Finder and Terminal cheap.

### C. The rolling backstop
- **testBackstopReadsTheStalestOnly** — exactly `backstopReadsPerPass` windows are re-read, stalest first.
- **testBackstopPrefersTabbingApps** — among equally stale windows, the ones whose app actually has tabs are
  re-checked first, so a missed notification is noticed sooner where tabs exist.
- **testBackstopBudgetLargerThanCandidateSet** — fewer settled windows than the budget means all of them are
  re-read.

### D. Edges
- **testEmptyInput** — no candidates, nothing read.
- **testAllQualifyingNeedsNoBackstop** — when every window already qualifies under rules 1-3, the backstop
  has nothing left to add.
