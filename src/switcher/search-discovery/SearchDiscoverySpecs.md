# Search discovery hint

The nonactivating panel says “Press S to search your windows.” using the configured Search shortcut.
It contains no Pro badge or modifier tutorial. Its close button permanently disables this hint;
the same preference is available in Controls → Shortcuts When Active, including through settings search.
Re-enabling the preference does not erase previous use, exposure count, or cooldown.
The shortcut appears as an inline, noninteractive keycap: 24 × 24 pt for S, widened for custom
combinations. It has no editing, focus, or accessibility action; the complete sentence remains its spoken label.

## Eligibility and frequency

- At least 8 filtered window targets, after tab/app grouping; windowless applications do not count.
  Minimized, hidden, other-Space and other-screen windows count only when the current filters show them.
- Active Pro or trial days 2–11 excluding day 4 (zero-based days 1–10 excluding 3).
  Locked/free-pass sessions never advertise Search. Eligibility never attempts a gated action.
- No previous search, hint refusal, global prompt opt-out, active search, missing/conflicting shortcut,
  pending Pro prompt, visible Pro/permission UI, modal window or open context menu.
- Historical use loads asynchronously once; unknown/malformed history suppresses the hint. Any known
  search permanently marks it used, including a search made before the history callback completes.
  Existing usage timestamps only cover their retained 365-day history.
- One opportunity per switcher session, 1 second after the turn revealing the panel. Navigation in
  the last 500 ms skips that opportunity; it is not rescheduled. The visible-frame timestamp is not
  observable here: the anchor is the completed show turn, not a claim of WindowServer presentation.
- Maximum 3 actual exposures, at least 72 hours apart. A future last-exposure date suppresses the hint
  until the cooldown elapses; missing dates with nonzero counts never reset the limit.
- Entering Search hides it for the session. First nonempty text marks it used permanently, aligned
  with UsageStats (spaces count too; this is not a successful-search metric).

## Presentation and lifecycle

- One reusable panel with the switcher's own background (frosted, or Liquid Glass on macOS 26+) and
  corner radius capped at half its height, normally 470 × 44 pt. Wrapped translations/shortcuts grow
  vertically on narrow screens. Follows the switcher's effective light/dark theme, not the app theme.
- Centred 8 pt above the switcher, otherwise below; clipped to neither screen nor menu/Dock area.
  Uses the actual screen's visible frame including negative origins. No room or preview overlap means
  no hint. The switcher itself is never moved or resized for this panel.
- First window work happens after the switcher appears. Hide its alpha alongside dismissal/search;
  defer window ordering/removal until a later turn. Session identity fences delayed presentation and
  old cleanup cannot hide a new session's hint. Displayed hints keep their own eligibility after the
  exposure count is incremented, so the third exposure does not immediately disappear.
- Search, closure, shortcut changes, menus and new Pro prompts cancel the opportunity for this session.
  Inventory/layout, preview, license, screen and accessibility changes revalidate or dismiss it.
- Never key/main, no key equivalents, no automatic accessibility announcement. The static label speaks
  the readable shortcut; close is an accessible 24 × 24 button and accepts a click without activation.
  The system background honours reduced transparency; no animation; increased contrast adds a border.
  The close button shows a round highlight while hovered.
- The switcher's accessibility children include the hint group. Its pointer gesture bypasses the
  switcher's outside-click dismissal, including a drag released outside the hint.
- No network, no window-title/query storage, no polling. Only local use/exposure metadata is persisted.

## Tests

In Debug builds, QA Menu → Pro Transition → Show search hint arms a preview for the next switcher
session. Hold the switcher open for one second without navigating. The preview bypasses trial day,
license, window threshold, previous searches, opt-outs, exposure cap and cooldown. It still requires
a usable Search shortcut, space on screen, no active search, and no competing prompt/menu/modal UI.
It uses the real panel and lifecycle; displaying or closing it changes neither history nor preferences.
The preview is consumed by that session, even if dismissed before display. Search itself retains its
normal access checks and usage tracking. The QA action is unavailable in Release builds.

`SearchDiscoveryTests` checks thresholds, trial/Pro/locked states, unknown and racing history,
refusals/competing UI, cooldown boundaries/clock rollback, exposure cap, cancelled/replaced sessions,
navigation timing, multi-screen geometry/preview collisions, custom shortcuts, wrapping, theme contrast,
the shared switcher background, close-button hover, nonactivation, pointer gestures and accessible dismissal using the actual AppKit component without presenting it.
The native light/dark snapshots are retained as test attachments. Shortcut symbols use ShortcutRecorder's
current-layout transformer, while the spoken label uses its readable representation.

Interactive VoiceOver navigation and live window-ordering latency still require manual QA; offscreen
component tests do not establish those properties on all supported macOS versions.
