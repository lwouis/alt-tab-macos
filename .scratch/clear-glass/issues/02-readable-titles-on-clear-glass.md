# 02: Readable titles on Clear glass

**What to build:** On macOS 26 and later, wherever the switcher uses Clear glass (App Icons and Titles), the titles stay readable over bright and busy windows while the panel still looks like glass. Three things together do it:

1. **Full-opacity titles.** The title color becomes fully opaque in both themes, where today it's white at 85% (dark) and black at 80% (light). This applies to every style, since it's one theme color.
2. **A Tint on Clear glass.** It's a neutral wash that follows the theme: black in dark mode, white in light mode. It updates on a live appearance switch with no extra observer code. Regular glass and the pre-macOS 26 frosted background get no Tint.
3. **A subtle shadow under the title text**, in the color opposite to the text (dark under white titles, light under black ones), tight and soft enough to read as a halo rather than a drop shadow. It's tuned after the Tint, in the same pass.

Always on, with no Settings control. Keep it to the code that already decides the glass kind and the title color and attributes. No new preferences, no new files beyond what's unavoidable, so a Sync rarely conflicts. Terms are defined in `CONTEXT.md` (Clear glass, Regular glass, Tint, Patch, Sync).

**Do this first:** build once with an obviously strong tint (red at full strength) on Clear glass and open the switcher. If the panel doesn't turn red, `tintColor` doesn't work on the private Clear glass look. In that case build the Tint as a dim layer instead: a plain view behind the content inside the glass, with the same theme-following color. Note which way it went in this ticket's Comments.

**Tuning (by eye, not to a contrast ratio):** start the Tint around 0.2 alpha. Raise it in 0.05–0.1 steps over a pure white page and a busy photo, in both themes, until the titles read at a glance. Stop at the lowest value that works. If it needs more than about 0.5, the glass look is gone, so stop there and record it in Comments rather than going darker.

Decisions already made (don't reopen): theme-following black/white Tint, not gray, semantic system colors or accent. Applies to Clear glass everywhere. No WCAG target and no screenshot test. No special handling for Reduce Transparency or Increase Contrast unless the check below shows a problem. No Upstream PR.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [x] The red-tint test was run, and the chosen mechanism (`tintColor` or dim layer) is noted in Comments
- [x] Titles are fully opaque in light and dark themes
- [ ] Clear glass shows a black Tint in dark mode and a white Tint in light mode, and switching appearance while AltTab runs updates it without a restart
- [x] Regular glass (Thumbnails) and the frosted background are unchanged apart from the opaque titles
- [x] Titles have a subtle opposite-color shadow; the SF Pro status and badge glyphs are unchanged
- [ ] The chosen Tint alpha and shadow values each have a one-line comment saying they were tuned by eye over a white page and a busy photo
- [x] The switcher panel background spec's manual scenarios cover the Tint (white page and busy photo, both themes, live appearance switch, one look with Reduce Transparency on), and `PERSONAL.md`'s "How this differs from upstream" table gains a row
- [x] The build command from `ai/build.sh` succeeds and `ai/test.sh` passes
- [x] One commit on `personal` with an end-user changelog-style message that passes the commit hooks, including this ticket file with Status `resolved`, so the working tree is clean for `./personal-build.sh`
- [ ] After `./personal-build.sh` installs it, the owner checks ⌥Tab in Titles over a white page and a busy window in both themes: titles readable, glass still visible, selection highlight still clearly accent-colored (owner's visual sign-off)

## Comments

- Red-tint test (macOS 26.7.3): an opaque red `tintColor` on the private Clear glass only lightened it to gray, so the Tint is a dim layer: the glass's content host gets the theme-following background color.
- Tint (0.2) and halo (0.5 alpha, 2pt blur) are starting values, not yet judged by eye; the owner's check below decides them.
- The halo is limited to Clear glass (Regular glass and frosted keep no title shadow), per this ticket.
- Implemented in the same commit as ticket 03, since both change the switcher's theme code.
