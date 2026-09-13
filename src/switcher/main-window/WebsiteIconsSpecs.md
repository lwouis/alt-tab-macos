# Website icons

Browser windows can show the icon of the website they display instead of the browser's icon. Off by default:
Settings > Appearance > Show website icons.

## Finding the page

- Reads the standard accessibility URL: `AXDocument` on the window, or `AXURL` on the tab's `AXWebArea`. No browser
  extensions, Apple Events, JavaScript or browser-specific code. Verified in Safari, Safari Technology Preview, Chrome,
  Orion and Firefox.
- The search stops at the first web area and never walks page content: at most 128 elements, depth 8, 1 second, 100ms
  per call, 4 background workers. AltTab's own windows are skipped.
- A browser's first-run dialog can be a modal web area that hides the tab (Firefox's welcome screen); the browser icon
  shows until it is dismissed.
- Chromium enables basic web accessibility for its process when a client reaches its web contents. On a page mutating
  50 DOM nodes every 100ms this measured about 3 to 5% more Chrome CPU and no memory change.

## Fetching the icon

- Only the site's homepage is requested (`https://host/`). The document's path, query, fragment and credentials are never
  sent; `http` pages look up the `https` homepage.
- Ephemeral requests carry no cookies, credentials or cache. Local names and hosts resolving to private, loopback,
  link-local or CGNAT addresses are refused, including redirect targets (at most 3 redirects).
- Candidates: `icon` and `apple-touch-icon` links (up to 8, honoring `<base href>`), then `/favicon.ico`. HTML downloads
  stop after `</head>`; responses are capped at 1 MiB.
- Work is shared and bounded: 8 transfers with 32 waiting, 32 pending pages and assets, results cached 30 seconds
  (5 seconds for failures). Excess demand shows the current icon and retries on a later summon.

## Drawing the icon

- Artwork becomes a 64px rounded tile, the same shape as app icons, with a subtle edge highlight.
- Artwork keeps full size only when its corners are one opaque background color wherever the rounded mask leaves them
  visible. Otherwise it is inset on a backing, so transparent logos (GitHub's circle) never blend into the selected row.
- The backing is white and brand colors are never changed. Artwork that barely shows on white (under 1.5:1 contrast for
  over 90% of it, e.g. white or pale-yellow marks) gets a dark backing; a white badge with a small dark logo stays white. Both backings contrast at least 3:1 with
  the selected row's accent color.
- Output does not depend on the system appearance.

## States

- Icons update live while the switcher is open. A result stands until the window's title changes (navigation), which
  starts a new lookup. A window that appears while the switcher is open, or a page still loading, is retried after
  0.25, 0.5, 1 and 2 seconds. Windows without a web area ignore title changes, so a spinner in a terminal title costs
  nothing. No retry runs while the switcher is closed.
- While a window navigates, its icon stays; if the URL is briefly unavailable, the last icon is kept for 8 seconds.
- A web page without usable artwork shows a globe. Other windows (settings, new tab pages) keep the browser icon.
- Private windows can't be detected, so the setting's description says requests also happen for them.
- Turning the setting off cancels transfers, clears caches and restores app icons immediately.
