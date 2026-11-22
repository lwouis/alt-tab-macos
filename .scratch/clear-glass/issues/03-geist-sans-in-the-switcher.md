# 03: Geist Sans in the switcher

**What to build:** The switcher's window titles and its search field use Geist Sans instead of the system font. They keep today's weights: Geist Medium where the system font is Medium (Titles and Thumbnails on macOS 26+), Geist SemiBold where it's SemiBold (App Icons), and Geist Regular where it's Regular (before macOS 26). Sizes stay the same. The SF Pro Text symbol glyphs (status icons, badges, tile font icons) stay SF Pro, because they're icon characters that Geist doesn't have.

Geist is already installed on the owner's Mac in `~/Library/Fonts` (PostScript names `Geist-Regular`, `Geist-Medium`, `Geist-SemiBold`, from the variable font). Load it by name and fall back to the current system font when it isn't available, so a missing font never crashes or blanks the switcher. Don't bundle font files in the app: that would edit the Xcode project and Info.plist, both Sync conflict hotspots. Always on, with no Settings control. Terms are defined in `CONTEXT.md`.

Out of scope: the search-discovery hint and panel, the empty-state label, the Settings window, and the menu bar.

Decisions already made (don't reopen): installed font by name with a system fallback, not bundled. Titles and search field only. Same weights and sizes. No Upstream PR.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [ ] Titles in all three styles render in Geist at the weights listed above, confirmed in the running app (not only in code), since fonts in `~/Library/Fonts` must load inside the app
- [x] The search field's typed text renders in Geist
- [ ] With Geist unavailable (e.g. a misspelled name in a quick local test, reverted afterwards), the switcher falls back to the system font without crashing
- [x] SF Pro glyphs (status icons, badges) are unchanged
- [ ] Title truncation and row height still fit, with no clipped descenders
- [x] `PERSONAL.md`'s "How this differs from upstream" table gains a row, noting that the font must be installed in `~/Library/Fonts`
- [x] The build command from `ai/build.sh` succeeds and `ai/test.sh` passes
- [x] One commit on `personal` with an end-user changelog-style message that passes the commit hooks, including this ticket file with Status `resolved`, so the working tree is clean for `./personal-build.sh`
- [ ] After `./personal-build.sh` installs it, the owner checks the switcher's titles and search field (owner's visual sign-off)

## Comments

- Geist is loaded by PostScript name with a system-font fallback. That the app process actually finds the fonts in `~/Library/Fonts`, the fallback path, and truncation/row height with Geist's metrics are not verified yet: they need the installed build, so the owner's check covers them.
- Implemented in the same commit as ticket 02.
