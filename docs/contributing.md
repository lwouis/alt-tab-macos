You can [suggest an enhancement or discuss an issue on github](https://github.com/lwouis/alt-tab-macos/issues), or use the feedback form in the app.

## Technical overview

This document gives a technical overview of the project, for newcomers who want to contribute.

## Building the project

This project has minimal dependency on Xcode-only features (e.g. InterfaceBuilder, Playgrounds). You can build it by doing:

* `scripts/codesign/setup_local.sh` to generate a local self-signed certificate, to avoid having to re-check the `System Preferences > Security & Privacy` permissions on every build
* Either open `alt-tab-macos.xcodeproj` with Xcode, or use the CLI: `xcodebuild -project alt-tab-macos.xcodeproj -scheme Debug` to build the .app with the `Debug` build configuration

## Mac development

Mac development ecosystem is pretty terrible in general. They keep piling on the tech stacks on top of each other, so you have C APIs, ObjC APIs, Swift APIs, Interface builder, Playgrounds, Swift UI, Mac Catalyst. All these are bridging with each other with a bunch of macros, SDKs glue, compiler flags, compatibility mode, XCode legacy build system, etc. For alt-tab, we are on Swift 5.0. Note that swift just recently started being stable, but overall any change of version breaks a lot of stuff. Swift itself is the mainstream language with the worst governance I’ve seen in modern times.

Regarding SDKs, it’s very different from other (better) ecosystems like Java. Here the SDK is bundled with XCode, and XCode is bundled with the OS. This means that from a machine running let’s say macOS 10.10, you have access to only a specific range of XCode versions (you can’t run the latest for instance), and these give you access to a specific range of SDKs (i.e. Swift + objc + c + bridges + compiler + toolchain + etc)

Documentation is abysmal. Very simple things are not documented at all, and good information is hard to find. Compared to other ecosystem I’ve worked on in the past like Android, nodejs, Java, rust, this is really a bad spot. You can truly tell Apple doesn’t care about supporting third-parties. They are in such a good position that people will struggle and just push through to deliver on their ecosystem because it is so valuable, and because they don’t have to care, they don’t. They could pay an intern to update the docs over the summer for instance, just to give you context of the lack of care we are talking about here.

Dependencies in this project are vendored under `vendor/` and consumed as local Swift Package Manager packages. Each dependency has an `update_*.sh` script under `vendor/scripts/` that re-fetches it from upstream, strips unused files, and regenerates its `Package.swift`. There is no remote dependency resolution at build time — `git clone && xcodebuild` is the full bootstrap.

OS APIs are quite limited for the kind of low-level, system-wide app AltTab is. This means often we just don’t have an API to do something. For instance, there is no API to ask the OS “how many Spaces does the user have?” or “Can you focus the window on Space 2?”. There are however, retro-engineered private APIs which you can call. These are not documented at all, not guaranteed to be there in future macOS releases, and prevent us from releasing AltTab on the Mac AppStore. We have tried our best to [document the ones we are using](https://github.com/lwouis/alt-tab-macos/blob/master/src/macos/api-wrappers/README.md), as well as [the ones we investigated](https://github.com/lwouis/alt-tab-macos/blob/master/src/experimentations/PrivateApis.swift) in the past.

## Project architecture

To mitigate the issues listed above, we took some measures.

We minimize reliance on XCode, InterfaceBuilder, Playground, and other GUI tools. You can’t cut the dependency completely though as only XCode can build macOS apps. The whole UI, including the menubar, is built in code (no xib). Currently, the project has these files:

* `alt-tab-macos.xcodeproj` file describing AltTab itself. It contains some settings for the app
* `alt_tab_macos.entitlements` and `Info.plist` which are static files describing some app config for XCode
* `vendor/` holds vendored open-source libraries (Sparkle, ShortcutRecorder, AppCenter) as local SPM packages. `vendor/scripts/update_*.sh` refresh them from upstream
* Some `.xcconfig` files in `config/` which contain XCode settings that people typically change using XCode UI, but that I want to be version controlled

The project directory is organized in the following way:

| Path | Role |
|------|-------|
| `config/`    | XCode build settings (`.xcconfig` files) |
| `docs/`      | supporting material to document the project |
| `resources/` | files that are shipped inside the final `.app` (e.g. icons) |
| `scripts/`   | bash scripts useful for CI and local workflows |
| `vendor/`    | vendored open-source libraries, consumed as local SPM packages |
| `src/`       | Swift source code |

The `src/` folder groups files by feature, so files that change together live together. Each folder typically contains the implementation, and for the parts we want to pin down, a triad of `Foo.swift` + `FooSpecs.md` (specs) + `FooTests.swift` (unit tests):

| Path | Role |
|------|-------|
| `src/switcher/`         | the switcher itself: its window, tiles, state, appearance, shortcuts (the core feature) |
| `src/windowserver/`     | the WindowServer event pipeline feeding the list of windows |
| `src/events/`           | incoming events we listen to (keyboard, mouse, cursor, Dock, AX queries, etc.) |
| `src/macos/`            | wrappers around macOS APIs (AX/CGS call schedulers, permissions, login item); `src/macos/api-wrappers/` holds the retro-engineered private-API signatures |
| `src/preferences/`      | user settings: storage, migrations, and the Settings window |
| `src/pro/`              | the paid "Pro" features (license, scheduling, related UI) |
| `src/secondary-windows/`| windows other than the switcher (feedback, permission, debug) |
| `src/kit/`              | reusable AppKit building blocks (custom buttons, views, controls) |
| `src/util/`             | generic helpers (background work, throttling, scheduling policy) |
| `src/api/`              | client for our backend (license and feedback endpoints) |
| `src/vendors/`          | glue code for vendored libraries (AppCenter, Sparkle, ObjC exception catcher) |
| `src/debug/`            | benchmarking and QA tooling |
| `src/experimentations/` | private APIs and approaches we investigated but don't ship |
| `src/_test-support/`    | mocks and helpers shared by the unit tests |

Other folders/files are either tooling or auto-generated (e.g. `DerivedData/` is generated by Xcode builds).

## QA

**alt-tab-macos** is deeply integrated with the OS and other apps. Thus doing end-to-end automated QA would be a nightmare. For the time being QA is done manually.

In an attempt to not have too many regressions, this documents will list OS interactions. This should be useful as some of them are very exotic and not many people know about them.

## List of use-cases

### Which windows to list, and be able to focus

* Minimized windows
* Windows from hidden apps
* Windows of fullscreen apps
* Windows of fullscreen apps with split-screen
* Windows merged into 1 as tabs (e.g. Finder "Merge All Windows", drag-and-drop a window onto an existing window, etc) 
* Windows on multiple monitors
* Windows on multiple Spaces
* Should not show: dialogs, pop-overs, context menus (e.g. Outlook meeting reminder, iStats Pro menus)

### App is summoned during an OS animation

* The UI should only appear after the animation completes for:
  * Space transition
  * an app going fullscreen
* The UI should not show at all (i.e. ignore the shortcut) if Mission Control is open
* The UI should show instantly during:
  * Window minimizing/de-minimizing
  * Window maximizing (i.e. double-click the titlebar)
  * An app is launching/quitting

### Thumbnail layout corner-cases

* Very small windows (i.e. smaller than the thumbnail min size)
* Very wide/tall windows
* Should show the app name for windows without a title
* Long titles should be truncated
* Many windows are opened
* There is no open window
* AltTab should appear on top of all windows, dialogs, pop-overs, the Dock, etc

### OS events to handle while AltTab’s UI is shown

* An app is launching/quitting
* A new window opens
* An existing window is closed

### Drag-and-drop on top of the thumbnails

* Drag-and-dropping a URL onto a window thumbnail should open it with that window’s app
* Drag-and-dropping a file onto a window thumbnail should open it with that window’s app

### System Preferences

* General > Appearance > "Dark": switches to Dark Mode
* General > Accent color > "Graphite": traffic lights on thumbnails should be gray
* Accessibility > Display > Reduce transparency: AltTab background should be a solid color
* General > Show scroll bars > "Always": regenerates all scrollbars
* Display > Resolution > Scaled: changes DPI and rescale AltTab
* Mission Control > "Displays have separate Spaces": changes Spaces behavior on multi-displays setups

### Spaces

* Spaces get created/destroyed
* A window is moved to another space by drag-and-dropping on the Spaces thumbnails at the top of the Mission Control UI
* A window is moved to another space by dragging it on the side of the current Space, and waiting for a Space transition, then dropping it
* A window is moved to another space by destroying the Space it is in
* An app is assigned to a specific space or all spaces by clicking its Dock icon > Options > Assign to

### Shortcuts

* The hold "key" can be multiple modifiers (e.g. `⌥⇧`)
* Shortcuts should have priority over system shortcuts such as `cmd+tab`, so the user can replace these
* The "select next window" shortcut can be modifiers, modifiers+key, or just key; it can also contain the same modifiers as the hold "key"
* All shortcuts, except the hold key, can be disabled by the user
* Shortcuts can include the `escape` and `delete` key; these should not stop recording shortcuts
* [Secure Input](https://github.com/lwouis/alt-tab-macos/issues/157#issuecomment-659170293) can prevent AltTab from listening to the keyboard
* Some shortcuts should only work when AltTab is open
  * These shortcuts should active whether the hold shortcut is held or not
* Shortcuts should work with capslock active or inactive
* Shortcuts should repeat if kept pressed
  * Repeat rate and initial delay should match the values set in `System Preference` > `Keyboard`
  * when navigating left/right/up/down, the repeating behavior should stop when hitting the last window in the list. The user can then manually do the shortcut once more to cycle to the other side; it then repeats again
* The shortcut sets 1 and 2 should not interact with each other (e.g. opening AltTab with one, then using the other to navigate)
* Shortcuts can focus the window on release, or be pressing a key or using the mouse
* Keyboards from other countries have different layout which impact shortcuts
  * e.g. the default ``` ⌥` ``` shortcut should become `⌥<` on a Spanish ISO keyboard

### Localization

* Right-to-left languages (e.g. arabic) have the whole layout reversed
  * For the main window, even navigation is reversed
  * For preferences and feedback windows, all layout is reversed
* Text length can vary per languages which can create layout issues

### Misc

* AltTab is launched after some apps/windows are already opened
* Displays/mouses/trackpads/keyboards get connected/disconnected while AltTab is used
* Sudden Termination
