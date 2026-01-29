## Can it show, or hide, this window?

It's sometimes hard to say that some dialog, HUD, UI element, is a window or not. Not everyone will agree that a particular window is a window. AltTab does its best to decide what a window is, and show it to the user.

Some apps are not native macOS apps, or poorly programmed. Such apps will use "windows" to code things like menus, and play tricks like hidding a window instead of closing it. Notorious examples: Electron apps (e.g. Slack, Discord, etc) and apps using cross-platform SDKs (e.g. Adobe apps, Steam, IntelliJ, etc).

If a window is showing, and you think it shouldn't, please contact the app maker so they can fix their product.

## Can it show individual browser tabs?

Browser windows are not standard windows or tabs. They are custom UI painted by each browser, in their own unique way. There is no macOS API to screenshot a browser tab. Some browser may not even render a tab that's not active, so there are no pixels to screenshot. 

Browser may offer custom integration to know about tabs, screenshot, active them. However, each browser is unique, and it would require to write these integrations for each one, as well as to maintain them. Browsers evolve fast, so maintaining multiple fast-changing integrations is not attainable.

## Can we add window-management features?

AltTab is not intended to be a window manager. It will not add features such as: resizing windows, organizing them into tiles, Dock enhancements.

[Other apps](http://localhost:4000/#alternatives) offer such experiences.

AltTab aims at being the best at the Windows-style alt+tab experience.

## Can it be on the App Store?

AltTab uses **many** private APIs. This prevents us from publishing on the App Store. It's a shame. Many more casual users would benefit from it. However, without these private APIs, the user experience would be crippled. We use private APIs for refined details, but also for basic functionality.  

## Where are settings stored?

The app uses the standard macOS API to store settings. You can interact with them from the Terminal, using the `defaults` command:
* List current settings: `defaults read com.lwouis.alt-tab-macos.plist`
* Update a setting: `defaults write com.lwouis.alt-tab-macos.plist AppleAccentColor -int 4`
* Export settings to a file: `defaults export com.lwouis.alt-tab-macos.plist /tmp/my-export.plist`

## Can I share an idea or report a bug?

Please open an issue on [GitHub](https://github.com/lwouis/alt-tab-macos/issues)
