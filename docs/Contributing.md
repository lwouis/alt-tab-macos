# Contributing

There are many ways to contribute:

* Come discuss with us on the [Discord server](https://discord.gg/mHvmcqT).
* [Suggest an enhancement or discuss an issue on github](https://github.com/lwouis/alt-tab-macos/issues), or use the feedback form in the app.
* [Localize the app in your language](https://poeditor.com/join/project/8AOEZ0eAZE)

## Technical overview

This document gives an technical overview of the project, for newcomers who want to contribute.

## Building the project locally

This project has minimal dependency on Xcode-only features (e.g. InterfaceBuilder, Playgrounds). You can build it using 2 commands:

* `pod install` to fetch the dependencies with [CocoaPods](https://cocoapods.org/)
* `scripts/codesign/setup_local.sh` to generate a local self-signed certificate, to avoid having to re-check the `System Preferences > Security & Privacy` permissions on every build
* Either open `alt-tab-macos.xcworkspace` with XCode, or use the cli: `xcodebuild -workspace alt-tab-macos.xcworkspace -scheme Debug` to build the .app with the `Debug` build configuration

## Raising a pull-request

If you want to contribute a PR, please run `npm install` once. It will add the pre-commit hook to ensure that your commits follow the convention and will pass the PR.

## Mac development ecosystem

Mac development ecosystem is pretty terrible in general. They keep piling on the tech stacks on top of each other, so you have C APIs, ObjC APIs, Swift APIs, Interface builder, Playgrounds, Swift UI. All these are bridging each other with a bunch of macros, SDKs glue, compiler flags, compatibility mode, XCode legacy build system, etc. So keep that in mind. For alt-tab, we are on Swift 4.2. Note that swift just recently started being stable, but overall any change of version breaks a lot of stuff. Swift itself is the worst governed language project I’ve seen in modern times.

Regarding SDKs, it’s very different from other (better) ecosystems like Java. Here the SDK is bundled with XCode, and XCode is bundled with the OS. This means that from a machine running let’s say macOS 10.10, you have access to only a specific range of XCode versions (you can’t run the latest for instance), and these give you access to a specific range of SDKs (i.e. Swift + objc + c + bridges + compiler + toolchain + etc)

Documentation is abysmal. Very simple things are not documented at all, and good information is hard to find. Compared to other ecosystem I’ve worked on in the past like Android, nodejs, Java, rust, this is really a bad spot. You can truly tell Apple doesn’t care about supporting third-parties. They are in such a good position that people will struggle and just push through to deliver on their ecosystem because it is so valuable, and because they don’t have to care, they don’t. They could pay an intern to update the docs over the summer for instance, just to give you context of the lack of care we are talking about here.

Dependencies were historically never handled by Apple. The community came up with [Cocoapods](https://cocoapods.org/) which is the de-facto dependency manager for Apple ecosystem projects these days, even though Apple is now trying to push their own.

OS APIs are quite limited for the kind of low-level, system-wide app alt-tab is. This means often we just don’t have an API to do something. For instance, there is no API to ask the OS “how many Spaces does the user have?” or “Can you focus the window on Space 2?”. There are however, retro-engineered private APIs which you can call. These are not documented at all, not guaranteed to be there in future macOS releases, and prevent us from releasing alt-tab on the Mac AppStore. We have tried my best to [document](../src/api-wrappers/PrivateApis.swift) the ones we are using, as well as ones we investigated in the past.

## This project specifically

To mitigate the issues listed above, we took some measures.

We minimize reliance on XCode, InterfaceBuilder, Playground, and other GUI tools. You can’t cut the dependency completely though as only XCode can build macos apps. Currently the project has these files:

* 1 xib (InterfaceBuilder UI file, describing the menubar items like “Edit” or “Format”)
* `alt-tab-macos.xcodeproj` file describing alt-tab itself. It contains some settings for the app
* `alt-tab-macos.xcworkspace` file describing an xcode workspace containing alt-tab + cocoapods dependencies. You open that file to open the project in XCode or AppCode
* `Alt-tab-macos.entitlements` and Info.plist which are static files describing some app config for XCode
* `PodFile` and `PodFile.lock` describe dependencies on open-source libraries (e.g. [Sparkle](https://github.com/sparkle-project/Sparkle))
* Some `.xcconfig` files in `config/` which contain XCode settings that people typically change using XCode UI, but that I want to be version controlled

We use the command line to build the project, not XCode GUI. See how to build in the [README.md](../README.md).

The project directory is organized in the following way:

| Path | Role |
|------|-------|
| `config/` | XCode build settings                              |
| `docs/`   | supporting material to document the project       |
| `resources/` | files that are shipped inside the final `.app` (e.g. icons) |
| `scripts/` | bash scripts useful for CI and local workflows |
| `src/`     | Swift source code |
| `src/api-wrappers` | Wrapping some unfriendly APIs (usually C-APIs) |
| `src/logic`        | Business logic (i.e. "models") |
| `src/ui`           | UI code (e.g. sublasses of NSView or NSCollectionView) |

Other folders/files are either tooling or auto-generated (e.g. `Pods/` and `Frameworks/` are generated by `pod install`)

## QA

**alt-tab-macos** is deeply integrated with the OS and other apps. Thus doing end-to-end automated QA would be a nightmare. For the time being QA is done manually.

In an attempt to not have too many regressions, this documents will list OS interactions. This should be useful as some of them are very exotic and not many people know about them.

## List of use-cases

### Which windows to list, and be able to focus

* Minimized windows
* Windows from hidden apps
* Windows of fullscreen apps
* Windows of fullscreen apps with split-screen
* Minimized windows merged into 1 as tabs (e.g. Finder "Merge All Windows") 
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
* Alt-Tab should appear on top of all windows, dialogs, pop-overs, the Dock, etc

### OS events to handle while AltTab's UI is shown

* An app is launching/quitting
* A new window opens
* An existing window is closed

### Drag-and-drop on top of the thumbnails

* Drag-and-dropping a URL onto a window thumbnail should open it with that window's app
* Drag-and-dropping a file onto a window thumbnail should open it with that window's app

### System Preferences

* General > Appearance > "Dark": switches to Dark Mode
* General > Show scroll bars > "Always": regenerates all scrollbars
* Display > Resolution > Scaled: changes DPI and rescale AltTab
* Mission Control > "Displays have separate Spaces": changes Spaces behavior on multi-displays setups

### Spaces

* Spaces get created/destroyed
* A window is moved to another space by drag-and-dropping on the Spaces thumbnails at the top of the Mission Control UI
* A window is moved to another space by dragging it on the side of the current Space, and waiting for a Space transition, then dropping it
* A window is moved to another space by destroying the Space it is in
* An app is assigned to a specific space or all spaces by clicking it's Dock icon > Options > Assign to

### Misc

* AltTab is launched after some apps/windows are already opened
* Displays/mouses/trackpads/keyboards get connected/disconnected while AltTab is used
* Sudden Termination
