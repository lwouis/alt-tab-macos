import Cocoa

/// What we have learned about whether an app uses OS tabs at all.
enum AppTabCapability: Equatable {
    /// no window of this app has been read yet
    case unknown
    /// an `AXTabGroup` was found on one of its windows at least once
    case seenTabGroup
    /// every read so far found no `AXTabGroup`
    case neverSeenTabGroup
}

/// One tracked window, as the policy sees it.
struct TabReadCandidate: Equatable {
    let wid: CGWindowID
    let capability: AppTabCapability
    /// the owning app gained or lost a window since this window's tabs were last read
    let appWindowsChangedSinceLastRead: Bool
    /// nil = tabs have never been read for this window. Lower = read longer ago; the backstop's ordering.
    let lastReadGeneration: UInt64?
}

/// **Which windows pay for a tab read on a given switcher show.**
///
/// The tab read is the most expensive thing AltTab asks of other processes. `tabGroupObservation` hunts for
/// an `AXTabGroup` among bounded pages of a window's DIRECT children, and there is no OS batch across
/// elements, so it costs one Mach round trip per child — and a window with no tabs pays for every one of them
/// before concluding there is no tab bar. An ordinary AppKit window has several children (the close/minimize/zoom
/// buttons, a toolbar, a split group), so reading every tracked window on every show ran to several hundred
/// round trips per summon on an ordinary desktop, into as many processes, each capable of stalling a bounded
/// worker for the full 1s messaging timeout.
///
/// **The per-show read was never the mechanism, only the backstop.** Everything that actually changes a tab
/// group announces itself: opening or closing a tab creates or destroys a window (WindowServer 811/804), a
/// tab switch arrives as `AXMainWindowChanged` naming the wid, a rename arrives as `AXTitleChanged`, and a
/// tab dragged out is the reducer's own drag-out check. So the read is owed when something structural
/// happened, when we know nothing yet, or as a slow rolling sweep that re-checks everything eventually —
/// never for every window every time.
///
/// Deliberately NOT a rule: "this app has tabs, so read it every show". Finder and Terminal are exactly the
/// apps whose windows are most numerous and whose children are most plentiful, and they are the ones the
/// event signals cover best. Capability only orders the backstop, so a missed notification is noticed sooner
/// where tabs actually exist.
enum TabReadPolicy {
    /// How many otherwise-skipped windows are re-read per pass, oldest first. Small on purpose: it exists so
    /// a notification that never arrived is corrected within a few summons, not so the sweep stays cheap by
    /// accident. At 5, a 40-window desktop is fully re-checked inside ~8 shows while costing ~1/8 of what
    /// reading all of them did.
    static let backstopReadsPerPass = 5

    static func windowsToRead(_ candidates: [TabReadCandidate]) -> Set<CGWindowID> {
        var read = Set<CGWindowID>()
        var backstopEligible = [TabReadCandidate]()
        for candidate in candidates {
            if candidate.lastReadGeneration == nil || candidate.capability == .unknown
                   || candidate.appWindowsChangedSinceLastRead {
                read.insert(candidate.wid)
            } else {
                backstopEligible.append(candidate)
            }
        }
        // oldest read first; among equally stale windows, the ones whose app actually has tabs go first
        let ordered = backstopEligible.sorted {
            let a = $0.lastReadGeneration ?? 0, b = $1.lastReadGeneration ?? 0
            if a != b { return a < b }
            if ($0.capability == .seenTabGroup) != ($1.capability == .seenTabGroup) {
                return $0.capability == .seenTabGroup
            }
            return $0.wid < $1.wid
        }
        for candidate in ordered.prefix(backstopReadsPerPass) { read.insert(candidate.wid) }
        return read
    }
}

/// Page size bounds each allocation, not the number of children a window may expose. All pages share
/// the caller's time budget; partial reads are unknown and cannot prove a window has no tab group.
enum AxChildrenTraversal {
    enum Result: Equatable {
        case complete
        case stopped
        case unknown
    }

    static func walk<Element>(pageSize: Int, mayRead: () -> Bool, count: () -> Int?,
                              page: (Int, Int) -> [Element]?, visit: (Element) -> Bool?) -> Result {
        guard pageSize > 0, mayRead(), let total = count(), total >= 0 else { return .unknown }
        var offset = 0
        while offset < total {
            let amount = min(pageSize, total - offset)
            guard mayRead(), let elements = page(offset, amount), elements.count == amount else { return .unknown }
            for element in elements {
                guard mayRead(), let stop = visit(element) else { return .unknown }
                if stop { return .stopped }
            }
            offset += amount
        }
        // A shrinking or growing tree between page IPCs is not a complete observation.
        if total > pageSize {
            guard mayRead(), count() == total else { return .unknown }
        }
        return .complete
    }
}
