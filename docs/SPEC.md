# AltTab Personal Fork: product and project guide

This guide describes the AltTab Personal Fork: what the product does, how the fork differs from Upstream, how
you build and recover it, and how the source code is organized. It is the hub for the fork's documentation.
Other documents own the details, and this guide links to them instead of repeating them:

| Document | What it owns |
|---|---|
| [CONTEXT.md](../CONTEXT.md) | The glossary. Terms in **bold** in this guide are defined there. |
| [PERSONAL.md](../PERSONAL.md) | The runbook: Sync, troubleshooting, roll back, and rules. |
| [AGENTS.md](../AGENTS.md) | Coding rules for humans and AI agents: style, main-thread IPC, comments, workflow, the license invariant. |
| [docs/contributing.md](contributing.md) | Upstream's technical overview for contributors. |
| `src/**/*Specs.md` | The behavior specs, one per feature (74 files). |

**Audience:** you, the owner of the **Fork**, and AI agents working in this repository.

## Contents

1. [Understanding the product](#understanding-the-product)
2. [Understanding the fork](#understanding-the-fork)
3. [Setting up your Mac](#setting-up-your-mac)
4. [Updating with a Sync](#updating-with-a-sync)
5. [Using the switcher](#using-the-switcher)
6. [Configuring AltTab](#configuring-alttab)
7. [Controlling AltTab from the command line](#controlling-alttab-from-the-command-line)
8. [Rolling back](#rolling-back)
9. [Troubleshooting](#troubleshooting)
10. [Navigating the source code](#navigating-the-source-code)
11. [Developing and testing changes](#developing-and-testing-changes)
12. [Following the project rules](#following-the-project-rules)
13. [Reference: facts at a glance](#reference-facts-at-a-glance)

---

## Understanding the product

AltTab is a macOS window switcher. It brings the Windows-style Alt+Tab experience to macOS: you hold a
modifier key, press a trigger key, and AltTab shows every open window, not only every app. You then pick a
window by its thumbnail, icon, or title.

### What AltTab does

- **Switches between windows, not apps.** Each window gets its own tile, including windows on other Spaces,
  other screens, minimized windows, hidden apps, and fullscreen windows.
- **Shows previews.** Tiles show a live window capture (thumbnail), an app icon, or a title, depending on
  the style you choose.
- **Acts on windows from the switcher.** While the switcher is open, you can close, minimize, fullscreen,
  hide, or quit the selected window's app without leaving the switcher.
- **Supports several shortcuts.** Each shortcut can show a different set of windows. For example, one
  shortcut shows all apps, and another shows only the active app's windows.
- **Searches by typing.** You type part of a window title or app name to filter the tiles.
- **Accepts other input.** You can use the mouse, arrow keys, Vim keys, and trackpad swipes.

### Pro features

Upstream sells a Pro tier. These are the **Pro features**:

| Pro feature | Code identifier (`src/pro/ProFeature.swift`) | What it unlocks |
|---|---|---|
| Search by typing | `searchInSwitcher` | Filtering tiles by typing in the open switcher |
| Search on release | `searchOnReleaseShortcut` | A shortcut style that opens the switcher straight into search mode |
| App icon and title styles | `appIconsAndTitlesStyle` | The "App Icons" and "Titles" appearance styles |
| Auto size | `autoSize` | The "Auto" appearance size |
| Extra shortcuts | `extraShortcut(index:)` | Up to nine shortcuts |

In the Fork's Release builds, every Pro feature is always available. See
[Understanding the fork](#understanding-the-fork).

### System requirements

| Requirement | Value | Source |
|---|---|---|
| Minimum macOS | 12.0 | `MACOSX_DEPLOYMENT_TARGET` in `config/base.xcconfig` |
| Swift language version | 5.8 | `SWIFT_VERSION` in `config/base.xcconfig` |
| Build tool | Xcode 26.x | Checked by `personal-build.sh` |
| Bundle ID | `com.lwouis.alt-tab-macos` | `PRODUCT_BUNDLE_IDENTIFIER` in `config/base.xcconfig` |

### Permissions

AltTab needs two macOS privacy permissions. You grant them in **System Settings > Privacy & Security**.

| Permission | Why AltTab needs it | What happens without it |
|---|---|---|
| Accessibility | Focusing, raising, closing, and minimizing other apps' windows, and reading window titles and tabs | The switcher can't work |
| Screen Recording | Capturing window thumbnails | AltTab can run, but tiles show no thumbnails. You can skip this permission. |

macOS ties these grants to the app's code signature. A **Personal build** keeps the same signing
certificate, so the grants usually survive an update. If the switcher stops working after an install, grant
both permissions again.

---

## Understanding the fork

The **Fork** (`nathanwcyang/alt-tab-nathan`) is your copy of **Upstream** (`lwouis/alt-tab-macos`). You build
it and run it only on your own Mac.

### Branches and remotes

| Name | What it is |
|---|---|
| `origin` | `https://github.com/nathanwcyang/alt-tab-nathan.git`, the Fork |
| `upstream` | `https://github.com/lwouis/alt-tab-macos.git`, Upstream |
| `master` | An untouched mirror of Upstream. You never commit to it. |
| `personal` | The **Personal branch**. It carries the **Patch**, the build script, and the fork's docs. It is also the default branch. |

### The patch

The **Patch** is the full set of source changes on top of Upstream. It is small on purpose, so a Sync rarely
hits a merge conflict. To see it, run:

```bash
git fetch upstream && git diff upstream/master personal --stat
```

Expected output lists six files: `CONTEXT.md`, `PERSONAL.md`, `personal-build.sh`, `src/App.swift`,
`src/api/Endpoints.swift`, and `src/pro/license/LicenseManager.swift` (plus this guide once you commit it).

Each change has one job:

| Change | File | Effect |
|---|---|---|
| Release always returns `.pro` | `src/pro/license/LicenseManager.swift`, top of `computeState()` | The **Gate** always allows Pro features in Release builds. Debug builds keep Upstream's license logic, so its tests still run. |
| Debug always uses the Pro mock | `src/App.swift`, `applicationDidFinishLaunching` | Debug builds call `LicenseManager.shared.mockProUser()`. The mock never reads or changes the real license and never contacts the license server. |
| No QA menu | `src/App.swift` | The Debug-only QA panel is not created. Its buttons can replace the Pro mock or wipe your real preferences. |
| Dead update feed | `src/api/Endpoints.swift` | `appcastUrl` is `https://updates.invalid/appcast.xml`. The `.invalid` domain never resolves, so the stock updater can't replace your build. |

The Release Pro switch is the change a merge is most likely to break silently. Its marker comment is
`Personal fork: Release always runs as Pro`, and `personal-build.sh` refuses to build if the marker is
missing.

### What the fork does not change

- The fork removes no features and no fallbacks.
- The fork doesn't change the bundle ID, the signing team, or the license storage. See the
  [license invariant](#keeping-the-license-and-keychain-invariant).
- The in-app update setting still exists. Set it to **manual** in AltTab Settings. The default, "check
  automatically", only reaches the dead address, but "manual" means nothing calls the network on a timer.
- Crash reporting has no app secret in a Personal build, so it can't send reports.

---

## Setting up your Mac

Do this once, before your first Sync.

### Before you begin

You need:

- macOS with Xcode 26.x installed. To check, run `xcodebuild -version`.
- `python3` on your `PATH`.
- The repository outside `~/Documents`. macOS privacy rules block the test runner from reading
  `~/Documents`. Use `~/Developer/alt-tab-nathan`.

### Creating the signing certificate

The Personal build is signed with a self-signed certificate named **Local Self-Signed**. A stable
certificate keeps your Accessibility and Screen Recording grants across builds.

1. Run Upstream's setup script:

   ```bash
   scripts/codesign/setup_local.sh
   ```

2. Confirm that the certificate exists:

   ```bash
   security find-identity -v -p codesigning | grep '"Local Self-Signed"'
   ```

   You see one line that ends in `"Local Self-Signed"`. The script creates the certificate with the common
   name `Local Self-Signed`, which is the name `personal-build.sh` looks for.

### Cloning the repository

1. Clone the Fork and switch to the Personal branch:

   ```bash
   git clone https://github.com/nathanwcyang/alt-tab-nathan.git ~/Developer/alt-tab-nathan
   cd ~/Developer/alt-tab-nathan
   git checkout personal
   ```

2. Add Upstream as a remote. The build script also adds it if it's missing.

   ```bash
   git remote add upstream https://github.com/lwouis/alt-tab-macos.git
   ```

3. Run your first Sync. See [Updating with a Sync](#updating-with-a-sync).

---

## Updating with a Sync

A **Sync** merges new Upstream changes into the Personal branch, then rebuilds and reinstalls the Personal
build. One script does all of it.

### Running a Sync

1. Quit any AltTab copy that isn't in `/Applications`. The script refuses to run if two copies are running,
   or if one runs from another folder.
2. Run the build script:

   ```bash
   cd ~/Developer/alt-tab-nathan && ./personal-build.sh
   ```

   A Sync takes about 85 seconds. Each step prints an `OK` line. The script stops at the first problem and
   prints `FAIL: <reason>`.

3. Empty the Trash. LaunchServices keeps every trashed AltTab registered as launchable until you do.
4. Check the result:
   1. Open AltTab Settings and confirm that Pro is on.
   2. Open the switcher and type to test search.

### What the script does

| Step | Prints | What it checks or does |
|---|---|---|
| a. Preflight | `OK preflight` | macOS, Xcode 26, the certificate, `python3`, `origin` is the Fork, a clean working tree, the `personal` branch, the repo outside `~/Documents`, and at most one AltTab running (from `/Applications`) |
| b. Merge | `OK merged upstream/master` | Fetches and merges `upstream/master`. On a conflict, it lists the files, aborts the merge, and stops. |
| b. Version | `OK version <x.y.z>` | Reads the version from the latest Upstream `v*` tag. The app crashes without a version, and preference migrations compare it with the stored one. |
| b. Pro switch | `OK Pro switch present` | Confirms that the Release Pro switch survived the merge |
| c. Tests | `OK tests passed` | Runs `ai/test.sh` (Debug) |
| d. Build | `OK built … (version …)` | Writes `config/local.xcconfig`, checks assets, runs a **clean** Release build, and checks the built version |
| e. Signature | `OK signed: Authority=Local Self-Signed` | Runs `codesign --verify --deep --strict` and checks the signing authority |
| f. Quit | `OK AltTab not running` | Quits the running AltTab gracefully, and waits up to 10 seconds |
| g. Backup | `OK backup: <path>` | Zips the installed app to `~/AltTab-backups/`, keeps only the newest zip, and moves the old app to the Trash |
| h. Install | `OK installed /Applications/AltTab.app` | Copies the build to `/Applications`, and unregisters the build copy from LaunchServices |
| i. Launch | `OK AltTab running (one copy, pid …)` | Opens the app, and confirms that exactly one copy runs |
| Tag | `OK tagged personal-<date>-<time>` | Tags the commit locally as a known-good build |

### Why the build is clean every time

An incremental build alternates between embedding Sparkle unsigned and re-signing it, because the "Copy
Sparkle Helpers" build phase doesn't list the embedded framework as an input. A clean build always runs both
steps, so the signature check passes.

### What `config/local.xcconfig` contains

The script writes this gitignored file on every run. Don't edit it: the next Sync overwrites it.

```text
// Written by personal-build.sh on every run; edits are overwritten.
CODE_SIGN_IDENTITY = Local Self-Signed
OTHER_CODE_SIGN_FLAGS = --timestamp=none --deep --options runtime
CURRENT_PROJECT_VERSION = <latest upstream version>
```

The signing settings live in this file and not on the `xcodebuild` command line. Command-line settings also
apply to the vendored Swift packages, which then demand an Apple development team.

---

## Using the switcher

### Opening the switcher and picking a window

1. Hold the hold key. The default is **Option** (⌥).
2. Press the trigger key. The default for shortcut 1 is **Tab** (⇥). The switcher opens after a short delay
   (100 ms by default) and selects the next window.
3. Press the trigger key again to move the selection forward. Press **Shift** (⇧) to move it back.
4. Release the hold key. AltTab focuses the selected window.

The default shortcut style is **Focus**: releasing the hold key focuses the selection. You can change the
style per shortcut. See [Configuring shortcuts](#configuring-shortcuts).

### Using keys inside the open switcher

While the switcher is open and you still hold the hold key, these keys act on the selected window:

| Key | Action | Preference key |
|---|---|---|
| ⏎ Return | Focus the selected window | `focusWindowShortcut` |
| ⇧ Shift | Select the previous window | `previousWindowShortcut` |
| ⎋ Escape | Leave search mode, or close the switcher | `cancelShortcut` |
| W | Close the window (or one tab of a tabbed window) | `closeWindowShortcut` |
| M | Minimize or restore the window | `minDeminWindowShortcut` |
| F | Toggle fullscreen | `toggleFullscreenWindowShortcut` |
| Q | Quit the window's app | `quitAppShortcut` |
| H | Hide or show the window's app | `hideShowAppShortcut` |
| S | Toggle search mode | `searchShortcut` |
| ← → ↑ ↓ | Move the selection (on by default) | `arrowKeysEnabled` |
| h l k j | Move the selection left, right, up, down (off by default) | `vimKeysEnabled` |

After you act on a tile, the selection follows that window by its ID, even when the action reorders the
list. For example, pressing F twice fullscreens and then restores the same window.

### Searching by typing

1. Open the switcher.
2. Press S, or use a shortcut whose style is **Search**.
3. Type part of a window title or app name. The tiles filter as you type.
4. Press Return to focus the selection, or Escape to leave search mode.

Search behavior and its edge cases are specified in `src/switcher/SearchSpecs.md`,
`src/switcher/state/SearchModeResolverSpecs.md`, and `src/switcher/state/SearchFieldEditingSpecs.md`.

### Using the mouse and trackpad

- **Click** a tile to focus that window.
- **Hover** to select a tile. This is off by default (`mouseHoverEnabled`, in **Controls > Additional
  controls**).
- **Move the cursor with focus.** AltTab can move the cursor to the window it focuses: Never (default),
  Always, or Only on different screen (`cursorFollowFocus`, in **Controls > Additional controls**).
- **Swipe** with three or four fingers, horizontally or vertically, to open the switcher. This is off by
  default (`nextWindowGesture`). Trackpad haptic feedback is on by default.
- **Drag and drop** a file onto a tile to open it in that window's app. See
  `src/switcher/main-window/DragAndDropResolverSpecs.md`.

---

## Configuring AltTab

Open AltTab Settings from the menu bar icon. The Settings window has these tabs: **General**, **Controls**,
**Appearance**, **Exceptions**, **Upgrade**, **About**, and **Acknowledgments**. It also has a search field
that finds any setting.

AltTab stores preferences in macOS user defaults under the bundle ID `com.lwouis.alt-tab-macos`. The
defaults below come from `Preferences.defaultValues` in `src/preferences/Preferences.swift`.

### Configuring shortcuts

You can have from one to nine shortcuts (`shortcutCount`, default 2). Each shortcut has its own hold key,
trigger key, style, and window filters.

| Setting | Shortcut 1 default | Shortcut 2 default |
|---|---|---|
| Hold key (`holdShortcut`) | ⌥ Option | ⌥ Option |
| Trigger key (`nextWindowShortcut`) | ⇥ Tab | The key above Tab for your keyboard layout (for example, \`) |
| Apps to show (`appsToShow`) | All apps | Active app |

Each shortcut also has a **style** (`shortcutStyle`) that sets what happens when you release the hold key:

| Style | On release |
|---|---|
| Focus (default) | Focuses the selected window |
| Hold | Does nothing. The switcher stays open until you press Return, click, or press Escape. |
| Search | Opens the switcher in search mode (a Pro feature) |

### Filtering which windows appear

Each shortcut has its own filters. These are the options and their defaults:

| Setting | Options | Default |
|---|---|---|
| Apps to show | All apps, Active app, Non-active apps, Windows under the cursor, App under the cursor | Per shortcut (see above) |
| Spaces to show | All Spaces, Visible Spaces, Non-visible Spaces | All Spaces |
| Screens to show | All screens, Screen showing AltTab | All screens |
| Minimized windows | Show, Hide, Show at the end | Show |
| Hidden windows | Show, Hide, Show at the end | Show |
| Fullscreen windows | Show, Hide, Show at the end | Show |
| Apps with no open window | Show, Hide, Show at the end | Show at the end |
| Window order | Recently Focused First, Recently Created First, Alphabetical Order, Space Order | Recently Focused First |
| Group by app | Show all windows, Show one window per app | Show all windows |
| Tabs | Show single window for all tabs, Show separate window for each tab | Single window for all tabs |

### Choosing the appearance

| Setting | Options | Default |
|---|---|---|
| Style | Thumbnails, App Icons, Titles | Thumbnails |
| Size | Small, Medium, Large, Auto | Auto |
| Theme | Light, Dark, System | System |
| Show on screen | Active screen, Screen including mouse, Screen including menu bar | Active screen |
| Titles show | Window Title, Application Name, Application Name - Window Title | Window Title |
| Title truncation | Start, Middle, End | End |
| Preview the selected window | On, Off | Off |
| Display delay | 0 to 900 ms | 100 ms |
| Fade-out animation | On, Off | Off |
| Preview fade-in animation | On, Off | On |
| Hide Space number labels | On, Off | On |
| Hide status icons | On, Off | Off |
| Hide colored circles | On, Off | Off |

You can override style, size, theme, shortcut style, and the selected-window preview per shortcut.

### Setting app exceptions

The **Exceptions** tab lists apps that AltTab hides from the switcher or ignores. Each entry matches a bundle
ID, and a bundle ID that ends in `.` matches by prefix (for example, `com.parallels.`).

| Field | Options |
|---|---|
| Hide | Never, Always, When no open window, Window title contains |
| Ignore | Never, Always, When fullscreen. While that app is frontmost (and, for When fullscreen, its active window is fullscreen), AltTab's shortcuts don't fire. |

By default, Finder is hidden when it has no open window. Remote-desktop and virtual-machine apps, such as
Screen Sharing, Microsoft Remote Desktop, TeamViewer, Parallels, VMware Fusion, and UTM, are ignored when
fullscreen, so your Option+Tab reaches the remote machine.

### Setting general options

| Setting | Options | Default | Fork advice |
|---|---|---|---|
| Start at login | On, Off | On | Keep on |
| Menu bar icon | Outlined, Filled, Colored (plus legacy variants), or hidden | Outlined, shown | Any |
| Language | System default, or one of 21 languages | System default | Any |
| Updates | Don't check, Check periodically, Auto-install periodically | Check periodically | Set to **Don't check** |
| Crash reports | Never, Ask, Always | Ask | Any. Reports can't send. |
| Capture windows in the background | On, Off | On | Keep on for current thumbnails |

---

## Controlling AltTab from the command line

The AltTab binary doubles as a command-line client. When you run it with one supported argument, it sends
the command to the running AltTab over a Mach message port named `com.lwouis.alt-tab-macos.cli`, prints the
reply, and exits. AltTab must already be running.

### Listing windows

```bash
/Applications/AltTab.app/Contents/MacOS/AltTab --list
```

The reply is JSON with each window's ID and title:

```json
{"windows":[{"id":1234,"title":"README.md — alt-tab-nathan"}]}
```

For app name, bundle ID, Spaces, focus order, state flags, position, and size, use `--detailed-list`.

### Running commands

| Command | Effect |
|---|---|
| `--list` | Lists windows (ID and title) |
| `--detailed-list` | Lists windows with full details |
| `--focus=<window id>` | Focuses the window with that ID |
| `--focusUsingLastFocusOrder=<n>` | Focuses the window at that position in the focus order (0 is the current window) |
| `--show=<shortcut index>` | Opens the switcher as shortcut `<n>` would, counting from 0 |
| `--hide` | Closes the switcher |

For example, to focus the most recently used window other than the current one:

```bash
/Applications/AltTab.app/Contents/MacOS/AltTab --focusUsingLastFocusOrder=1
```

> **Note:** An empty reply line with exit code 0 can mean the command failed inside AltTab. The message port
> can't tell a failed reply from an empty one, so AltTab logs every failure. `--qa-*` commands exist only
> in Debug builds.

---

## Rolling back

[PERSONAL.md](../PERSONAL.md#roll-back) owns the exact rollback steps. This section explains which method to
choose.

| Situation | Method | Time |
|---|---|---|
| The newly installed app misbehaves, and you want the previous app back now | Restore the zip in `~/AltTab-backups/` | About 1 minute |
| A bad Upstream merge | `git revert -m 1 <merge-commit>` on `personal`, then Sync | One Sync |
| Upstream fixed the problem you reverted | Revert your revert first, then Sync | One Sync |
| A bad commit of your own | `git revert <commit>`, then Sync | One Sync |

Known-good builds carry two kinds of tags:

- `personal-<date>-<time>`: written locally by every successful Sync.
- `stable-<version>`: pushed to GitHub by hand for builds you trust.

To compare your branch with a known-good build, run:

```bash
git diff stable-11.10.1 personal
```

> **Caution:** Never unzip a backup on top of the installed app. The files merge and the signature breaks.
> Never double-click the zip, because that creates a second `AltTab.app` in the backups folder.

---

## Troubleshooting

[PERSONAL.md](../PERSONAL.md#troubleshooting) owns the full table. These are the most common problems:

| Symptom | Cause | Fix |
|---|---|---|
| Two switchers appear, or visual glitches | A second AltTab is running, often from `DerivedData` or the Trash | `pkill -x AltTab`, then open AltTab from `/Applications` |
| `FAIL: merge conflict …` | Upstream changed a file the Patch touches | Resolve the listed files on `personal` by hand, commit, and rerun |
| `FAIL: the Release Pro switch is missing …` | A merge moved or dropped the switch without a conflict | Re-add the `#if !DEBUG return .pro #else … #endif` wrapper around the body of `computeState()` |
| `FAIL: repo is under ~/Documents …` | macOS blocks `xctest` from reading `~/Documents` | Move the repo to `~/Developer` |
| `FAIL: codesign --verify failed` | A signing problem | Rerun. A repeat failure is a real signing problem with the certificate. |
| The switcher doesn't respond after an install | macOS dropped the privacy grants | Grant Accessibility and Screen Recording again |
| Tiles show icons but no thumbnails | Screen Recording isn't granted | Grant Screen Recording |

---

## Navigating the source code

The project is about 311 Swift files with no Interface Builder and no SwiftUI. All UI, including the menu
bar, is built in code with AppKit.

### Top-level layout

| Path | What it holds |
|---|---|
| `src/` | Swift source, grouped by feature |
| `config/` | Build settings (`.xcconfig`) under version control |
| `vendor/` | Vendored libraries (Sparkle, ShortcutRecorder, AppCenter) as local Swift packages. `vendor/scripts/update_*.sh` refreshes them. |
| `resources/` | Files shipped inside the app, such as icons and translations |
| `scripts/` | CI and local workflow scripts (release, signing, localization, assets) |
| `ai/` | Fast local scripts for development: build, test, run, profile |
| `docs/` | Supporting documentation |
| `personal-build.sh` | The fork's Sync script |

`git clone` followed by `xcodebuild` is the full bootstrap: there is no remote dependency resolution at
build time.

### Source folders

| Folder | Role |
|---|---|
| `src/switcher/` | The switcher itself: its window, tiles, state, appearance, search, and shortcut actions. The core feature. |
| `src/switcher/state/` | Pure decision logic: which windows appear (`WindowFilterResolver`), their order (`WindowOrderResolver`), selection, tab groups, phantom windows, and the window event reducer |
| `src/switcher/main-window/` | The switcher's views: tile grid layout, tile pool, drag and drop, the panel background |
| `src/windowserver/` | The physical window plane: existence, geometry, Spaces, and z-order from WindowServer (SkyLight/CGS) events. See `src/windowserver/README.md`. |
| `src/window-tracking/` | The attention plane: which window you are looking at, which drives the most-recently-used order. See `src/window-tracking/AttentionOrderSpecs.md`. |
| `src/events/` | Incoming events: keyboard, mouse, trackpad, Dock, screens, sleep and wake, and the CLI |
| `src/macos/` | Wrappers around macOS APIs: the off-main call schedulers, permissions, and login item. `src/macos/api-wrappers/` holds the reverse-engineered private API signatures. |
| `src/preferences/` | Preference storage, migrations, and the Settings window |
| `src/pro/` | Pro features: license (`license/`), trial timeline (`scheduling/`), and Pro UI (`ui/`) |
| `src/secondary-windows/` | Windows other than the switcher: feedback, permissions, debug |
| `src/kit/` | Reusable AppKit building blocks |
| `src/util/` | Generic helpers: background work, throttling, scheduling policy |
| `src/debug/` | Benchmarks, main-thread stall detection, and Debug-only QA tooling |
| `src/api/` | Endpoints and secrets read from `Info.plist` |
| `src/vendors/` | Glue code for vendored libraries (Sparkle, AppCenter) |
| `src/_test-support/` | Mocks shared by unit tests |

### How a window reaches the switcher

AltTab keeps two planes of window facts, and each fact has one authoritative source:

1. **Physical facts** come from the WindowServer: whether a window exists, its geometry, z-order, Space,
   and minimized or fullscreen state. `src/events/WindowServerEvents.swift` installs the tap, and
   `src/windowserver/` decodes and routes the events. The WindowServer still answers when an app is frozen.
2. **Semantic facts** come from one Accessibility observer per app: focused-window changes, title changes,
   and tab groups.
3. **Window order** comes from the attention model (`AttentionModel`, `AttentionDriver`,
   `AttentionEngine`). Only a committed attention decision may change the most-recently-used order.
4. The window event reducer (`src/switcher/state/WindowEventReducer.swift`) combines these into the window
   list that the switcher draws.

### Understanding the triad pattern

When a part of the code needs pinned-down behavior, it has three co-located files:

| File | Contents |
|---|---|
| `Foo.swift` | The implementation |
| `FooSpecs.md` | The behavior spec: scenarios and edge cases, plus a coverage badge |
| `FooTests.swift` | XCTest unit tests, one per spec scenario |

Pure decision logic ("kernels") lives in the triads and is unit-tested. The AppKit layer (windows, views,
event taps) is deliberately not unit-tested, following the Humble Object pattern. `src/coverage.md` holds
the coverage table.

To find the spec for a feature, run:

```bash
find src -name '*Specs.md' | sort
```

---

## Developing and testing changes

### Building a Debug build

```bash
ai/build.sh
```

The script checks the asset illustrations, then builds the Debug scheme into `DerivedData/`. The result is
`DerivedData/Build/Products/Debug/AltTab.app`.

> **Note:** In a git worktree, copy `config/local.xcconfig` from the main checkout before you build. The file
> is gitignored. Without it, the build fails at code signing on a dependency framework before it compiles
> any of `src/`, so it can look as if your code compiled when it didn't.

### Running the unit tests

```bash
ai/test.sh
```

The script validates localizations, checks assets, then runs the `Test` scheme in Debug. Use it, not
`scripts/run_tests.sh`: the CI script builds in Release, which recompiles the whole test target on every edit
(34 seconds against 1.3 seconds). Debug also runs the `#if DEBUG` tests that Release drops.

### Running and profiling the app

| Script | What it does |
|---|---|
| `ai/run.sh` | Launches the Debug build through LaunchServices with debug logs, and streams the log to `/tmp/alttab-run.log` |
| `ai/profile.sh` | Records a 20-second Time Profiler trace of the Debug build's benchmark |

`ai/run.sh` launches with `open`, not by running the binary from a shell. macOS judges privacy grants by the
responsible process, and a binary started from a shell inherits the terminal's grants.

### Committing a change

1. Run `ai/build.sh` and `ai/test.sh`, and confirm that both pass.
2. Commit on `personal`, never on `master`.
3. Write the message in Conventional Commits form, as enforced by `commitlint.config.js`:
   `type: summary`. Write the summary for end users, because Upstream builds the changelog from it.

   ```bash
   git commit -m "docs: add the product and project guide"
   ```

4. Run a Sync to install the change.

### Using the project skills

These Claude Code skills are specific to this repository:

| Skill | Use it to |
|---|---|
| `/audit-specs-tests` | Check that each test has a matching spec scenario, and the reverse |
| `/coverage-explore` | Refresh coverage badges and `src/coverage.md`, and find untested branches |
| `/rework-comments` | Audit comments so they help instead of mislead |
| `/translate-missing-l10n` | Translate missing localization strings |
| `/assets-optimization` | Audit and shrink image assets |

---

## Following the project rules

[AGENTS.md](../AGENTS.md) owns these rules. This section summarizes them.

### Writing code

- Write pure Swift 5.8 with AppKit. Don't use Interface Builder or SwiftUI. Don't develop in the Xcode UI.
- Keep code compact. Prefer `guard` clauses, so the happy path reads straight down.
- Group files that change together into one folder.
- Favor low latency: reuse objects, avoid wasted memory and I/O, and observe events instead of polling.

### Keeping the main thread responsive

- Assume any AppKit call that changes first responder, orders a window, or resizes one makes a synchronous
  call to another process. Setting `searchField.stringValue = ""` once froze a user's main thread for 3.0
  seconds.
- On latency-critical paths (opening the switcher, a keystroke while cycling or searching, dismissing with
  focus), do the visible work first and the bookkeeping after.
- `NSWorkspace` and `NSRunningApplication` are documented as thread safe, so their reads may run off the
  main thread.
- See `src/main-thread-ipc.md` for the audited call sites.

### Writing comments

- Comment what the code can't show: OS behavior, measured timings, private-API notes, and invariants.
- Don't narrate history. If a past bug explains a constraint, name the test that pins it.
- When you change code, update the comments around it in the same change.

### Keeping the license and Keychain invariant

- Keep the Developer ID, Team ID, and bundle ID stable. Keychain items are tied to the code signature, and
  changing any of these orphans stored license keys.
- Don't add the legacy `SecKeychain*` API or `kSecAccessControl` to license code. Both can trigger Keychain
  password prompts.

### Following the fork rules

- Run AltTab only from `/Applications`.
- Keep `master` an untouched mirror of Upstream. Never force-push.
- Don't edit `config/local.xcconfig` by hand.

---

## Reference: facts at a glance

| Fact | Value |
|---|---|
| Product | AltTab, a macOS window switcher |
| Upstream | `lwouis/alt-tab-macos` |
| Fork | `nathanwcyang/alt-tab-nathan`, branch `personal` |
| Version | Follows the latest Upstream `v*` tag (11.10.1 at the time of writing) |
| Bundle ID | `com.lwouis.alt-tab-macos` |
| Minimum macOS | 12.0 |
| Language | Swift 5.8, AppKit, no Interface Builder, no SwiftUI |
| Build tool | Xcode 26.x |
| Signing certificate | Local Self-Signed |
| Installed app | `/Applications/AltTab.app` |
| Release build output | `DerivedData/Build/Products/Release/AltTab.app` |
| Backups | `~/AltTab-backups/AltTab-<date>-<time>.zip`, newest only |
| Good-build tags | `personal-<date>-<time>` (local), `stable-<version>` (pushed) |
| Update feed | `https://updates.invalid/appcast.xml` (unreachable on purpose) |
| CLI message port | `com.lwouis.alt-tab-macos.cli` |
| Vendored libraries | Sparkle, ShortcutRecorder, AppCenter |
| Sync command | `./personal-build.sh` |
| Debug build | `ai/build.sh` |
| Unit tests | `ai/test.sh` |
