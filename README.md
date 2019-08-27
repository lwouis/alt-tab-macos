# Overview

![Screenshot](docs/img/alt-tab-macos/3%20windows%20-%201%20line.png)

`alt-tab-macos` brings the brilliant Windows 10 window switcher (activated by pressing alt-tab) to macOS users.It lets the user switch between windows in a visual way.

On macOS there is an app cycling shortcut which doesn't let you select between windows of an app, and there is Mission Control which doesn't let you navigate using the keyboard.

# How to install

* Compile using XCode or AppCode
* Run the `.app`

# How to use

* `control` + `tab` cycles through apps
* `control` + `shift` + `tab` cycles through apps in reverse
* Quick press-and-release will cycle through apps without showing any UI
* Holding `control` after pressing a cycle shortcut will show the UI
* Releasing `control` or clicking on a window will focus it

# Screenshots

![Screenshot](docs/img/alt-tab-macos/5%20windows%20-%202%20lines.png)

![Screenshot](docs/img/alt-tab-macos/6%20windows%20-%202%20lines.png)

![Screenshot](docs/img/alt-tab-macos/dark-background.png)

# Features

* Delay before showing the UI to avoid flashing (default 200ms)
* High quality thumbnails of all windows
* Background uses macOS vibrancy UX
* UI elements have a subtle shadow to ensure readability
* Window titles will truncate with an ellipsis if they don't fit
* Thumbnails have a maximum width and height to help visualize very long, tall, small, big windows
* Fast. There is no benchmark at the moment but energy was spent making sure the UI is responsive
