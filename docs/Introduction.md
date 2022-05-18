---
permalink: /
---

# Introduction

[![Screenshot](public/demo/frontpage.jpg)](public/demo/frontpage.jpg)

**AltTab** brings the power of Windows's "alt-tab" window switcher to macOS.

## Features

* Switch focus to any window
* Minimize, close, fullscreen any window
* Hide, quit any app
* Customize AltTab appearance (e.g. show app badges, Space numbers, increase icon, thumbnail, title size, etc)
* Custom trigger shortcuts with almost any key
* Blacklist apps you don’t want to list or trigger AltTab from
* Dark Mode
* Drag-and-drop things on top of window thumbnails
* Right-to-left languages and UI
* Accessibility: VoiceOver, sticky keys, reduced transparency, etc

## Installation

[**Download the latest release**]({{ site.github.latest_release.assets[0].browser_download_url }})

Alternatively, you can use [homebrew](https://brew.sh/):

* Homebrew 2.5 or above: `brew install alt-tab`
* Homebrew 2.4 or below: `brew cask install alt-tab`

## Compatibility

* __macOS version:__ from 10.12 to 12 (Monterey)
* __Apple Silicon:__ yes, AltTab is [universal](https://developer.apple.com/documentation/apple-silicon/porting-your-macos-apps-to-apple-silicon)

## Localization

AltTab is available in: Bahasa Indonesia, Català, Dansk, Deutsch, Eesti keel, English, Español, Français, Italiano, Lëtzebuergesch, Magyar, Nederlands, Norsk, Polski, Português, Português (Brasil), Shqip, Slovenčina, Slovenščina, Suomi, Svenska, Tiếng Việt, Türkçe, Čeština, Ελληνικά, Български, Русский язык, Српски / Srpski, українська мова, עִבְרִית ,العربية ,فارسی, हिन्दी, 日本語, 简体中文, 繁體中文, 한국어

[Contribute your own language easily!](https://poeditor.com/join/project/8AOEZ0eAZE)

## Privacy and respecting the user

* AltTab doesn’t send or receive any data without explicit user consent. It may ask the user to send a crash report after a crash for example, but it will never spy on the user.
* AltTab tries to use as few resources as it can: CPU, memory, disk, etc. All images are compressed, AltTab is optimized to be as light as possible on the user resources.

## Configuration

Change the shortcut keys, switch to a Windows theme and more, using the Preferences window:

| [![Screenshot1](public/demo/preferences-appearance.jpg)](public/demo/preferences-appearance.jpg) | [![Screenshot 2](public/demo/preferences-controls.jpg)](public/demo/preferences-controls.jpg) |
| [![Screenshot3](public/demo/preferences-blacklist.jpg)](public/demo/preferences-blacklist.jpg) | [![Screenshot 4](public/demo/preferences-policies.jpg)](public/demo/preferences-policies.jpg) |
| [![Screenshot5](public/demo/preferences-general.jpg)](public/demo/preferences-general.jpg) | |

## Alternatives

Before building my own app, I looked around at similar apps. However, none was completely satisfactory so I rolled my own. Also, the almost-good-enough apps are not open-source.

| Alternative                                                                                 | Differences                                                                                                  |
|---------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| [HyperSwitch](https://bahoom.com/hyperswitch) and [HyperDock](https://bahoom.com/hyperdock) | $10. Closed-source. Thumbnails are too small. App icon is on top of the thumbnail                            |
| [WindowSwitcher](https://www.noteifyapp.com/windowswitcher/)                                | $7. Closed-source. Thumbnails are small and blurry. App icon is on top of the thumbnail                      |
| [Switch](https://github.com/numist/Switch)                                                  | Open Source. Thumbnails are small. Very little customization. Latest release is from 2016                    |
| [Witch](https://manytricks.com/witch/) and [Context](https://contexts.co/)                  | $10-15. Closed-source. Focus on text. No thumbnails                                                          |
| [MissionControl Plus](https://www.fadel.io/missioncontrolplus)                              | $10. Closed-source. No chronology and order to windows. Hard to navigate windows with keyboard               |
| Built-in [MissionControl](https://en.wikipedia.org/wiki/Mission_Control_(macOS))          | No keyboard support                                                                                          |
| Built-in `⌘ command` + `⇥ tab`                                                              | Only shows apps, not windows (note: can press down to see window of selected app)                            |
| Built-in `⌘ command` + `` ` ``                                                              | Cycles through tabs and windows, but only of the same app. Only cycling, no direct access                    |

There are also related apps which don’t really overlap in functionality, but target similar needs: [Swish](https://highlyopinionated.co/swish/), [Hookshot](https://hookshot.app/), [Magnet](https://magnet.crowdcafe.com/), [Spectacle](https://www.spectacleapp.com/), [Rectangle](https://github.com/rxhanson/Rectangle), [yabai](https://github.com/koekeishiya/yabai), [LayAuto](https://layautoapp.com/), [OptimalLayout](http://most-advantageous.com/optimal-layout/), [BetterTouchTool](https://folivora.ai/), [BetterSnapTool](https://folivora.ai/bettersnaptool), [Moom](https://manytricks.com/moom/), [uBar](https://brawersoftware.com/products/ubar).

## More screenshots

| 1 row | 2 rows | Windows theme |
|-------|---------|-------|
| [![Screenshot](public/demo/1-row.jpg)](public/demo/1-row.jpg) | [![Screenshot](public/demo/2-rows.jpg)](public/demo/2-rows.jpg) | [![Screenshot](public/demo/windows-theme.jpg)](public/demo/windows-theme.jpg) |

## License

AltTab is under the [GPL-3.0 license](https://github.com/lwouis/alt-tab-macos/blob/master/LICENCE.md). 
