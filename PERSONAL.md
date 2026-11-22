# Personal build runbook

How to keep this fork's AltTab up to date, check it, and recover it. Terms are defined in [CONTEXT.md](CONTEXT.md).

## Update (Sync)

```bash
cd ~/Developer/alt-tab-nathan && ./personal-build.sh
```

About 85 seconds. It stops at the first problem and prints `FAIL: <reason>`. In order, it:

1. Checks the Mac: Xcode 26 or later, the "Local Self-Signed" certificate, a clean `personal` branch, the repo outside `~/Documents`, and at most one AltTab running (from `/Applications`).
2. Merges `upstream/master`. On a conflict it lists the files, aborts the merge, and stops.
3. Reads the version from the latest upstream `v*` tag and checks that the Pro switch is still in `LicenseManager.computeState()`.
4. Runs the unit tests (`ai/test.sh`, Debug).
5. Writes `config/local.xcconfig` (gitignored) and does a clean Release build.
6. Checks the built version and the signature (`Authority=Local Self-Signed`).
7. Quits AltTab, zips the installed app to `~/AltTab-backups/` (only the newest zip is kept), and moves the old app to the Trash.
8. Installs to `/Applications`, launches it, checks that exactly one copy runs, and tags the commit `personal-<date>-<time>` (local only).

After it finishes, empty the Trash. LaunchServices keeps every trashed AltTab registered as launchable until then.

## How this differs from upstream

| What | Where |
|---|---|
| Release builds always run as Pro (Debug keeps upstream's license logic and its tests) | `src/pro/license/LicenseManager.swift` |
| Debug builds use the in-memory Pro mock | `src/App.swift` |
| Update feed points at `https://updates.invalid/appcast.xml`, so the stock updater can never replace this build | `src/api/Endpoints.swift` |
| The Debug-only QA test panel is not created | `src/App.swift` |
| Titles style uses Clear glass with no panel shadow, like App Icons | `src/switcher/main-window/TilesPanelBackgroundView.swift`, `src/switcher/Appearance.swift` |
| Clear glass gets a light theme-following Tint; titles are fully opaque with a soft halo | `src/switcher/Appearance.swift`, `src/switcher/main-window/TilesPanelBackgroundView.swift`, `src/switcher/main-window/TileView.swift` |
| Switcher titles and search field use Geist Sans, which must be installed in `~/Library/Fonts` (falls back to the system font) | `src/switcher/Appearance.swift`, `src/switcher/main-window/TilesView.swift` |
| Build, install and backup script | `personal-build.sh` |

Not changed on purpose: no features or fallbacks were removed, so merge conflicts are rare (only the patches above can conflict). Set the update policy to "manual" in AltTab Settings; the app's default is "check automatically", which only reaches the dead update address. Crash reporting has no app secret, so with "manual" nothing calls the network automatically.

## Troubleshooting

| Symptom | Check | Fix |
|---|---|---|
| Visual glitches, two switchers | `for p in $(pgrep -x AltTab); do ps -o pid=,comm= -p $p; done` | 2+ lines, or a path outside `/Applications`: `pkill -x AltTab`, then open AltTab from Alfred |
| `FAIL: merge conflict` | the listed files | Resolve on `personal` by hand, commit, rerun |
| `FAIL: the Release Pro switch is missing` | `git log -p upstream/master -- src/pro/license/LicenseManager.swift` | Re-add the `#if !DEBUG return .pro #else … #endif` wrapper around `computeState()`'s body |
| `FAIL: repo is under ~/Documents; move it` | repo location | Move the repo out of `~/Documents` (macOS blocks the test runner there), e.g. to `~/Developer` |
| `FAIL: codesign --verify failed` | `codesign --verify --deep --strict --verbose=4 DerivedData/Build/Products/Release/AltTab.app` | Rerun; the build is clean each time, so a repeat failure is a real signing problem |
| Switcher doesn't work after an install | System Settings > Privacy & Security | Grant Accessibility and Screen Recording to AltTab again |

## Roll back

### Last installed app (about 1 minute)

Never unzip on top of the current app: the files merge and the signature breaks. Never double-click the zip: it creates a second `AltTab.app` in the backups folder.

1. `pkill -x AltTab`
2. `mv /Applications/AltTab.app ~/.Trash/AltTab-broken-$(date +%Y%m%d-%H%M%S).app`
3. `ditto -x -k ~/AltTab-backups/AltTab-*.zip /Applications` (the script keeps exactly one zip)
4. `open /Applications/AltTab.app`

### Known-good source

The `stable-<version>` tags (pushed to GitHub) and the local `personal-<date>-<time>` tags mark builds that passed every check. Compare with `git diff stable-<version> personal`. The script only builds the `personal` branch, so go back by reverting on `personal`:

1. A bad upstream merge: `git revert -m 1 <merge-commit>` (plain `git revert` refuses merge commits), then rerun the Sync.
2. Once upstream has fixed the problem, undo that revert first: `git revert <the-revert-commit>`. Otherwise the reverted upstream changes stay out for good, and a Sync that touches the same files stops on a merge conflict.
3. A bad commit of your own: `git revert <commit>`, then rerun the Sync.

## Rules

- Run AltTab only from `/Applications`. A copy started from another folder runs as a second app.
- `master` stays an untouched mirror of upstream; all changes go on `personal`. Never force-push.
- `config/local.xcconfig` is generated by the script; edits to it are overwritten.
