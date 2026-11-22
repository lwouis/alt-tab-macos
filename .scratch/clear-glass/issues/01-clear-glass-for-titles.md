# 01: Clear glass for the Titles style

**What to build:** On macOS 26 and later, when the switcher opens in the Titles style, it shows Clear glass with no panel shadow, exactly as the App Icons style already does. Thumbnails keeps Regular glass and its shadow. Anything else that follows the panel's glass kind (the search-discovery hint) follows it here too. The behaviour is always on, with no Settings control. On macOS 25 and earlier, nothing changes (frosted background). When the private clear-glass look isn't available, Titles falls back to Regular glass, the same way App Icons does.

This is a Patch change: keep it to the two existing decisions Upstream already makes for App Icons (which glass kind the panel uses, and whether the panel has a shadow) by adding Titles to them. Don't add new files, preferences or abstractions, so a Sync rarely conflicts. Terms are defined in `CONTEXT.md` (Regular glass, Clear glass, Patch, Sync, Personal branch).

Decisions already made (don't reopen): Titles only, not every style. Committed straight on the Personal branch, with no feature branch. No panel shadow under Clear glass. No readability tint for now. No `personal-build.sh` check for this change. No Upstream PR.

**Blocked by:** None (can start immediately).

**Status:** resolved

- [ ] In the Titles style on macOS 26+, the panel uses Clear glass and has no shadow; with the private look unavailable, it uses Regular glass with a shadow, like App Icons
- [ ] Thumbnails still uses Regular glass with a shadow; App Icons is unchanged
- [ ] Comments next to both decisions say App Icons and Titles (not just App Icons), and the switcher panel background spec's summary and manual scenarios cover Titles with Clear glass, including the corner check at Titles' corner radius
- [ ] `PERSONAL.md`'s "How this differs from upstream" table gains a row for this change
- [ ] The build command from `ai/build.sh` succeeds and `ai/test.sh` passes
- [ ] One commit on `personal` with an end-user changelog-style message that passes the commit hooks. It includes this ticket file with its Status set to `resolved`, so the working tree is clean for `./personal-build.sh`
- [ ] After `./personal-build.sh` installs the build, the owner checks ⌥Tab in Titles over a bright window and over a busy one: all four corners are clean in light and dark appearances, and the titles are readable (owner's visual sign-off)
