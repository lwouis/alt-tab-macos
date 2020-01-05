## [2.3.2](https://github.com/lwouis/alt-tab-macos/compare/v2.3.1...v2.3.2) (2020-01-05)


### Bug Fixes

* app crashes when no windows are open ([cecc53a](https://github.com/lwouis/alt-tab-macos/commit/cecc53a))

## [2.3.1](https://github.com/lwouis/alt-tab-macos/compare/v2.3.0...v2.3.1) (2020-01-04)


### Bug Fixes

* selecting windows theme shows an error (closes [#109](https://github.com/lwouis/alt-tab-macos/issues/109)) ([01163c6](https://github.com/lwouis/alt-tab-macos/commit/01163c6))

# [2.3.0](https://github.com/lwouis/alt-tab-macos/compare/v2.2.0...v2.3.0) (2020-01-04)


### Features

* handle hidden app windows (closes [#108](https://github.com/lwouis/alt-tab-macos/issues/108)) ([6fcf092](https://github.com/lwouis/alt-tab-macos/commit/6fcf092))

# [2.2.0](https://github.com/lwouis/alt-tab-macos/compare/v2.1.0...v2.2.0) (2020-01-03)


### Bug Fixes

* follow-up on pr-104; minimized windows are not on another space ([998c763](https://github.com/lwouis/alt-tab-macos/commit/998c763))


### Features

* **ux:** add option to hide the space number label ([51a193c](https://github.com/lwouis/alt-tab-macos/commit/51a193c))

# [2.1.0](https://github.com/lwouis/alt-tab-macos/compare/v2.0.3...v2.1.0) (2020-01-03)


### Bug Fixes

* **ux:** simplify tool menu ([de7f428](https://github.com/lwouis/alt-tab-macos/commit/de7f428))
* issue in pr-104 where app would not show properly ([4d19015](https://github.com/lwouis/alt-tab-macos/commit/4d19015))
* small ux change on pr-104 ([6d2741a](https://github.com/lwouis/alt-tab-macos/commit/6d2741a))


### Features

* add menu option to pop up the selector window ([78428dc](https://github.com/lwouis/alt-tab-macos/commit/78428dc))

## [2.0.3](https://github.com/lwouis/alt-tab-macos/compare/v2.0.2...v2.0.3) (2020-01-03)


### Bug Fixes

* better filtering of "actual" windows (closes 102) ([fcdce9c](https://github.com/lwouis/alt-tab-macos/commit/fcdce9c))

## [2.0.2](https://github.com/lwouis/alt-tab-macos/compare/v2.0.1...v2.0.2) (2019-12-30)


### Bug Fixes

* space numbers are correctly removed if single space ([45ad43f](https://github.com/lwouis/alt-tab-macos/commit/45ad43f))

## [2.0.1](https://github.com/lwouis/alt-tab-macos/compare/v2.0.0...v2.0.1) (2019-12-30)


### Bug Fixes

* app crashes when invoked when there is 0 window (closes [#95](https://github.com/lwouis/alt-tab-macos/issues/95)) ([921590a](https://github.com/lwouis/alt-tab-macos/commit/921590a))

# [2.0.0](https://github.com/lwouis/alt-tab-macos/compare/v1.14.4...v2.0.0) (2019-12-27)


### Features

* display other spaces/minimized windows (closes [#14](https://github.com/lwouis/alt-tab-macos/issues/14)) ([3f5ea25](https://github.com/lwouis/alt-tab-macos/commit/3f5ea25)), closes [#11](https://github.com/lwouis/alt-tab-macos/issues/11) [#45](https://github.com/lwouis/alt-tab-macos/issues/45) [#62](https://github.com/lwouis/alt-tab-macos/issues/62)


### BREAKING CHANGES

* this brings huge changes to core parts of the codebase. It introduces the use of private APIs that hopefully are should be compatible from macOS 10.12+, but I couldn't test them. I reviewed the whole codebase to clean and improve on performance and readability

## [1.14.4](https://github.com/lwouis/alt-tab-macos/compare/v1.14.3...v1.14.4) (2019-12-24)

## [1.14.3](https://github.com/lwouis/alt-tab-macos/compare/v1.14.2...v1.14.3) (2019-11-12)


### Bug Fixes

* code compile compatibility with old macos ([10552a0](https://github.com/lwouis/alt-tab-macos/commit/10552a0))

## [1.14.2](https://github.com/lwouis/alt-tab-macos/compare/v1.14.1...v1.14.2) (2019-11-11)

## [1.14.1](https://github.com/lwouis/alt-tab-macos/compare/v1.14.0...v1.14.1) (2019-11-11)


### Bug Fixes

* handle preference files with deprecated keys ([eabc327](https://github.com/lwouis/alt-tab-macos/commit/eabc327))

# [1.14.0](https://github.com/lwouis/alt-tab-macos/compare/v1.13.0...v1.14.0) (2019-11-11)


### Features

* merge previous preferences onto new defaults (closes [#73](https://github.com/lwouis/alt-tab-macos/issues/73)) ([7ec3a50](https://github.com/lwouis/alt-tab-macos/commit/7ec3a50))
* reading preferences on disk will reset file if error (closes [#73](https://github.com/lwouis/alt-tab-macos/issues/73)) ([39677fe](https://github.com/lwouis/alt-tab-macos/commit/39677fe))

# [1.13.0](https://github.com/lwouis/alt-tab-macos/compare/v1.12.3...v1.13.0) (2019-11-11)


### Features

* improved PreferencesPanel UX, partially implements [#49](https://github.com/lwouis/alt-tab-macos/issues/49) ([59fc712](https://github.com/lwouis/alt-tab-macos/commit/59fc712))
* improved PreferencesPanel UX, partially implements [#49](https://github.com/lwouis/alt-tab-macos/issues/49) ([fa4d150](https://github.com/lwouis/alt-tab-macos/commit/fa4d150))
* improves PreferencesPanel UX, partially implements [#49](https://github.com/lwouis/alt-tab-macos/issues/49) ([21a4587](https://github.com/lwouis/alt-tab-macos/commit/21a4587))
* improves PreferencesPanel UX, partially implements [#49](https://github.com/lwouis/alt-tab-macos/issues/49) ([65327c2](https://github.com/lwouis/alt-tab-macos/commit/65327c2))

## [1.12.3](https://github.com/lwouis/alt-tab-macos/compare/v1.12.2...v1.12.3) (2019-11-10)

## [1.12.2](https://github.com/lwouis/alt-tab-macos/compare/v1.12.1...v1.12.2) (2019-11-06)

## [1.12.1](https://github.com/lwouis/alt-tab-macos/compare/v1.12.0...v1.12.1) (2019-11-06)

# [1.12.0](https://github.com/lwouis/alt-tab-macos/compare/v1.11.3...v1.12.0) (2019-11-01)


### Features

* windows on mouse screen, implements [#28](https://github.com/lwouis/alt-tab-macos/issues/28) ([b841ec7](https://github.com/lwouis/alt-tab-macos/commit/b841ec7))
* windows on mouse screen, implements [#28](https://github.com/lwouis/alt-tab-macos/issues/28) ([6c93047](https://github.com/lwouis/alt-tab-macos/commit/6c93047)), closes [#66](https://github.com/lwouis/alt-tab-macos/issues/66) [#59](https://github.com/lwouis/alt-tab-macos/issues/59) [#66](https://github.com/lwouis/alt-tab-macos/issues/66) [#66](https://github.com/lwouis/alt-tab-macos/issues/66)

## [1.11.3](https://github.com/lwouis/alt-tab-macos/compare/v1.11.2...v1.11.3) (2019-10-30)

## [1.11.2](https://github.com/lwouis/alt-tab-macos/compare/v1.11.1...v1.11.2) (2019-10-30)

## [1.11.1](https://github.com/lwouis/alt-tab-macos/compare/v1.11.0...v1.11.1) (2019-10-30)

# [1.11.0](https://github.com/lwouis/alt-tab-macos/compare/v1.10.0...v1.11.0) (2019-10-28)


### Bug Fixes

* app was no longer absorbing its shortcut key events properly ([4976267](https://github.com/lwouis/alt-tab-macos/commit/4976267))
* don't let the app bellow get the meta keyUp event ([7f12f41](https://github.com/lwouis/alt-tab-macos/commit/7f12f41))


### Features

* allows more than one metaKeyCode ([7e21974](https://github.com/lwouis/alt-tab-macos/commit/7e21974))

# [1.10.0](https://github.com/lwouis/alt-tab-macos/compare/v1.9.8...v1.10.0) (2019-10-28)


### Features

* don't show the UI on very fast shortcut triggers from the user ([4b5fa1a](https://github.com/lwouis/alt-tab-macos/commit/4b5fa1a))

## [1.9.8](https://github.com/lwouis/alt-tab-macos/compare/v1.9.7...v1.9.8) (2019-10-28)


### Bug Fixes

* adds missing return statements ([4b517ff](https://github.com/lwouis/alt-tab-macos/commit/4b517ff))

## [1.9.7](https://github.com/lwouis/alt-tab-macos/compare/v1.9.6...v1.9.7) (2019-10-27)


### Bug Fixes

* remove broken meta keys from preferences (closes [#61](https://github.com/lwouis/alt-tab-macos/issues/61)) ([5517e7a](https://github.com/lwouis/alt-tab-macos/commit/5517e7a))

## [1.9.6](https://github.com/lwouis/alt-tab-macos/compare/v1.9.5...v1.9.6) (2019-10-26)


### Bug Fixes

* removed logic on meta key press and better app summon logic ([8ac6a51](https://github.com/lwouis/alt-tab-macos/commit/8ac6a51))

## [1.9.5](https://github.com/lwouis/alt-tab-macos/compare/v1.9.4...v1.9.5) (2019-10-25)


### Bug Fixes

* option key was broken as a meta key ([e59d51d](https://github.com/lwouis/alt-tab-macos/commit/e59d51d))

## [1.9.4](https://github.com/lwouis/alt-tab-macos/compare/v1.9.3...v1.9.4) (2019-10-25)


### Bug Fixes

* app was broken for new installs because of the tab keyCode ([51e9aee](https://github.com/lwouis/alt-tab-macos/commit/51e9aee))

## [1.9.3](https://github.com/lwouis/alt-tab-macos/compare/v1.9.2...v1.9.3) (2019-10-25)

## [1.9.2](https://github.com/lwouis/alt-tab-macos/compare/v1.9.1...v1.9.2) (2019-10-25)

## [1.9.1](https://github.com/lwouis/alt-tab-macos/compare/v1.9.0...v1.9.1) (2019-10-25)

# [1.9.0](https://github.com/lwouis/alt-tab-macos/compare/v1.8.1...v1.9.0) (2019-10-25)


### Features

* hovering with the mouse highlights cells (closes [#34](https://github.com/lwouis/alt-tab-macos/issues/34)) ([f20ada6](https://github.com/lwouis/alt-tab-macos/commit/f20ada6))

## [1.8.1](https://github.com/lwouis/alt-tab-macos/compare/v1.8.0...v1.8.1) (2019-10-25)


### Bug Fixes

* meta+arrow activates only if meta+tab was first pressed ([aa5f748](https://github.com/lwouis/alt-tab-macos/commit/aa5f748))

# [1.8.0](https://github.com/lwouis/alt-tab-macos/compare/v1.7.2...v1.8.0) (2019-10-25)


### Features

* use arrow keys to navigate the UI (closes [#53](https://github.com/lwouis/alt-tab-macos/issues/53)) ([1049a50](https://github.com/lwouis/alt-tab-macos/commit/1049a50))

## [1.7.2](https://github.com/lwouis/alt-tab-macos/compare/v1.7.1...v1.7.2) (2019-10-25)


### Bug Fixes

* increased contrast to help with dark backgrounds ([8458113](https://github.com/lwouis/alt-tab-macos/commit/8458113))

## [1.7.1](https://github.com/lwouis/alt-tab-macos/compare/v1.7.0...v1.7.1) (2019-10-25)


### Bug Fixes

* remove flickr due to current app losing focus when AltTab appears ([98273de](https://github.com/lwouis/alt-tab-macos/commit/98273de))

# [1.7.0](https://github.com/lwouis/alt-tab-macos/compare/v1.6.1...v1.7.0) (2019-10-25)


### Bug Fixes

* don't crash when the OS doesn't return an icon ([ce6f6aa](https://github.com/lwouis/alt-tab-macos/commit/ce6f6aa))


### Features

* close main window when (meta and) escape is pressed (closes [#44](https://github.com/lwouis/alt-tab-macos/issues/44)) ([b6e4826](https://github.com/lwouis/alt-tab-macos/commit/b6e4826))

## [1.6.1](https://github.com/lwouis/alt-tab-macos/compare/v1.6.0...v1.6.1) (2019-10-24)

# [1.6.0](https://github.com/lwouis/alt-tab-macos/compare/v1.5.1...v1.6.0) (2019-10-24)


### Features

* add mac theme and improve preferences (closes [#21](https://github.com/lwouis/alt-tab-macos/issues/21)) ([4a5bbe9](https://github.com/lwouis/alt-tab-macos/commit/4a5bbe9))

## [1.5.1](https://github.com/lwouis/alt-tab-macos/compare/v1.5.0...v1.5.1) (2019-10-24)

# [1.5.0](https://github.com/lwouis/alt-tab-macos/compare/v1.4.7...v1.5.0) (2019-10-23)


### Features

* add panel to set user preferences (closes [#8](https://github.com/lwouis/alt-tab-macos/issues/8)) ([a994825](https://github.com/lwouis/alt-tab-macos/commit/a994825))

## [1.4.7](https://github.com/lwouis/alt-tab-macos/compare/v1.4.6...v1.4.7) (2019-10-23)

## [1.4.6](https://github.com/lwouis/alt-tab-macos/compare/v1.4.5...v1.4.6) (2019-10-23)

## [1.4.5](https://github.com/lwouis/alt-tab-macos/compare/v1.4.4...v1.4.5) (2019-10-17)


### Bug Fixes

* handle new Screen Recording permission on Catalina (closes [#29](https://github.com/lwouis/alt-tab-macos/issues/29)) ([cbfa586](https://github.com/lwouis/alt-tab-macos/commit/cbfa586))

## [1.4.4](https://github.com/lwouis/alt-tab-macos/compare/v1.4.3...v1.4.4) (2019-10-17)


### Bug Fixes

* better decide which windows to show the user (closes [#15](https://github.com/lwouis/alt-tab-macos/issues/15) [#30](https://github.com/lwouis/alt-tab-macos/issues/30)) ([f150b7e](https://github.com/lwouis/alt-tab-macos/commit/f150b7e))

## [1.4.3](https://github.com/lwouis/alt-tab-macos/compare/v1.4.2...v1.4.3) (2019-10-17)

## [1.4.2](https://github.com/lwouis/alt-tab-macos/compare/v1.4.1...v1.4.2) (2019-10-17)


### Bug Fixes

* travis should release versioned archives (follow-up to de6ad7f83) ([5538bbd](https://github.com/lwouis/alt-tab-macos/commit/5538bbd))

## [1.4.1](https://github.com/lwouis/alt-tab-macos/compare/v1.4.0...v1.4.1) (2019-10-17)


### Bug Fixes

* travis should release versioned archives (follow-up to de6ad7f83) ([15fcbc9](https://github.com/lwouis/alt-tab-macos/commit/15fcbc9))

# [1.4.0](https://github.com/lwouis/alt-tab-macos/compare/v1.3.0...v1.4.0) (2019-10-17)


### Features

* add version to the app menubar and release archives (closes [#36](https://github.com/lwouis/alt-tab-macos/issues/36)) ([de6ad7f](https://github.com/lwouis/alt-tab-macos/commit/de6ad7f))

# [1.3.0](https://github.com/lwouis/alt-tab-macos/compare/v1.2.1...v1.3.0) (2019-10-16)


### Bug Fixes

* upgrade scenario didn't work properly ([f864a25](https://github.com/lwouis/alt-tab-macos/commit/f864a25))


### Features

* add window display delay as a preference ([e52326b](https://github.com/lwouis/alt-tab-macos/commit/e52326b))

## [1.2.1](https://github.com/lwouis/alt-tab-macos/compare/v1.2.0...v1.2.1) (2019-10-16)

# [1.2.0](https://github.com/lwouis/alt-tab-macos/compare/v1.1.0...v1.2.0) (2019-10-16)


### Features

* support macOS 10.11+ (closes [#27](https://github.com/lwouis/alt-tab-macos/issues/27)) ([d0face2](https://github.com/lwouis/alt-tab-macos/commit/d0face2))

# [1.1.0](https://github.com/lwouis/alt-tab-macos/compare/v1.0.12...v1.1.0) (2019-10-16)


### Features

* preferences can be changed through JSON file ([64cb6f0](https://github.com/lwouis/alt-tab-macos/commit/64cb6f0))

## [1.0.12](https://github.com/lwouis/alt-tab-macos/compare/v1.0.11...v1.0.12) (2019-10-15)

## [1.0.11](https://github.com/lwouis/alt-tab-macos/compare/v1.0.10...v1.0.11) (2019-10-04)


### Bug Fixes

* keyboard events don't stop being listened to (closes [#18](https://github.com/lwouis/alt-tab-macos/issues/18)) ([75db5e9](https://github.com/lwouis/alt-tab-macos/commit/75db5e9))

## [1.0.10](https://github.com/lwouis/alt-tab-macos/compare/v1.0.9...v1.0.10) (2019-09-30)


### Bug Fixes

* don't crash when focusing an app that was closed (closes [#19](https://github.com/lwouis/alt-tab-macos/issues/19)) ([6b5e426](https://github.com/lwouis/alt-tab-macos/commit/6b5e426))

## [1.0.9](https://github.com/lwouis/alt-tab-macos/compare/v1.0.8...v1.0.9) (2019-09-16)


### Bug Fixes

* crash when windows changed between the CG and the AX calls ([2fa140f](https://github.com/lwouis/alt-tab-macos/commit/2fa140f))
* don't crash when the nsevent contructor fails ([6f61354](https://github.com/lwouis/alt-tab-macos/commit/6f61354))

## [1.0.8](https://github.com/lwouis/alt-tab-macos/compare/v1.0.7...v1.0.8) (2019-09-02)


### Bug Fixes

* should not alter focus when displayed (closes [#16](https://github.com/lwouis/alt-tab-macos/issues/16)) ([376a21b](https://github.com/lwouis/alt-tab-macos/commit/376a21b))

## [1.0.7](https://github.com/lwouis/alt-tab-macos/compare/v1.0.6...v1.0.7) (2019-08-30)


### Bug Fixes

* alt-shift-tab as first shortcut works properly (closes [#10](https://github.com/lwouis/alt-tab-macos/issues/10)) ([87a0a3c](https://github.com/lwouis/alt-tab-macos/commit/87a0a3c))

## [1.0.6](https://github.com/lwouis/alt-tab-macos/compare/v1.0.5...v1.0.6) (2019-08-29)


### Bug Fixes

* better heuristic for windows of same app (closes [#12](https://github.com/lwouis/alt-tab-macos/issues/12)) ([a4cc11b](https://github.com/lwouis/alt-tab-macos/commit/a4cc11b))

## [1.0.5](https://github.com/lwouis/alt-tab-macos/compare/v1.0.4...v1.0.5) (2019-08-28)

## [1.0.4](https://github.com/lwouis/alt-tab-macos/compare/v1.0.3...v1.0.4) (2019-08-28)

## [1.0.3](https://github.com/lwouis/alt-tab-macos/compare/v1.0.2...v1.0.3) (2019-08-28)

## [1.0.2](https://github.com/lwouis/alt-tab-macos/compare/v1.0.1...v1.0.2) (2019-08-28)

## [1.0.1](https://github.com/lwouis/alt-tab-macos/compare/v1.0.0...v1.0.1) (2019-08-28)

# 1.0.0 (2019-08-27)


### Features

* documented the project and reduced image sizes ([930c82d](https://github.com/lwouis/alt-tab-macos/commit/930c82d))
* mvp ([be59936](https://github.com/lwouis/alt-tab-macos/commit/be59936))
