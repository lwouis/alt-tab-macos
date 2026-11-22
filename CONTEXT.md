# AltTab Personal Fork

A personal fork of AltTab for macOS, built and used only on its owner's own Mac, with all Pro features available. How to update, check and recover it: [PERSONAL.md](PERSONAL.md).

## Language

**Upstream**:
The original AltTab repository (lwouis/alt-tab-macos), the source of all new versions.
_Avoid_: Original, official repo

**Fork**:
The owner's copy of Upstream at nathanwcyang/alt-tab-nathan, holding the Patch and the Personal build script.
_Avoid_: Clone, mirror

**Personal branch**:
The Fork's `personal` branch, which carries the Patch, the Personal build script and this glossary. The Fork's `master` stays an untouched copy of Upstream.
_Avoid_: Custom branch, dev branch

**Pro features**:
The capabilities Upstream sells: search by typing, extra icon and title styles, auto-size thumbnails, and up to nine shortcuts.
_Avoid_: Premium features, paid features

**Gate**:
The local check that decides whether Pro features may run.
_Avoid_: Paywall, lock

**Patch**:
The small source changes on top of Upstream that make the Gate always allow Pro features, keep the app away from Upstream's update feed, and skip the Debug-only QA panel.
_Avoid_: Crack, hack, mod

**Personal build**:
A Release build of the Fork, signed with the owner's "Local Self-Signed" certificate and installed on the owner's own Mac only. Its version is the latest Upstream tag, so it matches the stored preferences.
_Avoid_: Release, distribution

**Sync**:
Merging new Upstream changes into the Personal branch, then rebuilding and reinstalling the Personal build.
_Avoid_: Update (the in-app updater is a different, disabled thing)

**One-shot run**:
A single Claude Code prompt that completes the Personal build without asking questions, and stops with a clear report if a precondition fails.
_Avoid_: Automation, pipeline

**Regular glass**:
The standard macOS Liquid Glass behind the switcher, which Upstream uses for the Thumbnails and Titles styles.
_Avoid_: Default glass, frosted (frosted is the pre-macOS 26 blur)

**Clear glass**:
The more see-through Liquid Glass of the system ⌘Tab switcher, with no panel shadow. Upstream uses it only for the App Icons style; the Fork also uses it for Titles.
_Avoid_: Transparent mode, private look
