# Context

**alt-tab-macos** is deeply integrated with the OS and other apps. Thus doing end-to-end automated QA would be a nightmare. For the time being QA is done manually.

In an attempt to not have too many regressions, this documents will list OS interactions. This should be useful as some of them or very exotic and not many people know about them.

# List of use-cases

## Which windows to list, and be able to focus

* Minimized windows
* Windows from hidden apps
* Windows of fullscreen apps
* Windows of fullscreen apps with split-screen
* Minimized windows merged into 1 as tabs (e.g. Finder "Merge All Windows") 
* Windows on multiple monitors
* Windows on multiple Spaces
* Should not show: dialogs, pop-overs, context menus (e.g. Outlook meeting reminder, iStats Pro menus)

## App is summoned during an OS animation

* The UI should only appear after the animation completes for:
  * Space transition
  * an app going fullscreen
* The UI should not show at all (i.e. ignore the shortcut) if Mission Control is open
* The UI should show instantly during:
  * Window minimizing/de-minimizing
  * Window maximizing (i.e. double-click the titlebar)
  * An app is launching/quitting

## Thumbnail layout corner-cases

* Very small windows (i.e. smaller than the thumbnail min size)
* Very wide/tall windows
* Should show the app name for windows without a title
* Long titles should be truncated
* Many windows are opened
* There is no open window
* Alt-Tab should appear on top of all windows, dialogs, pop-overs, the Dock, etc

## OS events to handle while the app's UI is shown

* An app is launching/quitting
* A new window opens
* An existing window is closed

## Drag-and-drop on top of the thumbnails

* Drag-and-dropping a URL onto a window thumbnail should open it with that window's app
* Drag-and-dropping a file onto a window thumbnail should open it with that window's app

## System Preferences

* General > Appearance > "Dark": switches to Dark Mode
* General > Show scroll bars > "Always": regenerates all scrollbars
* Display > Resolution > Scaled: changes DPI and rescale the app
* Mission Control > "Displays have separate Spaces": changes Spaces behavior on multi-displays setups

## Misc

* The app is launched after some apps/windows are already opened
* Displays/mouses/trackpads/keyboards get connected/disconnected while the app is used
* Spaces get created/destroyed
* Sudden Termination

