## [8.3.4](https://github.com/lwouis/alt-tab-macos/compare/v8.3.3...v8.3.4) (2026-01-31)


### Bug Fixes

* app could sometimes crash in the background ([ab704dc](https://github.com/lwouis/alt-tab-macos/commit/ab704dc)), closes [#5260](https://github.com/lwouis/alt-tab-macos/issues/5260)
* quitting apps by pressing q multiple times (closes [#5247](https://github.com/lwouis/alt-tab-macos/issues/5247)) ([21aeafd](https://github.com/lwouis/alt-tab-macos/commit/21aeafd))

## [8.3.3](https://github.com/lwouis/alt-tab-macos/compare/v8.3.2...v8.3.3) (2026-01-25)


### Bug Fixes

* app icons could sometimes be invisible (closes [#5226](https://github.com/lwouis/alt-tab-macos/issues/5226)) ([23fbc01](https://github.com/lwouis/alt-tab-macos/commit/23fbc01))
* improve trackpad gesture detection (closes [#5203](https://github.com/lwouis/alt-tab-macos/issues/5203)) ([9b5e43e](https://github.com/lwouis/alt-tab-macos/commit/9b5e43e))
* switcher could sometimes show with no window pre-selected ([3e95f77](https://github.com/lwouis/alt-tab-macos/commit/3e95f77))
* title could be off-center in app-icons appearance (closes [#5235](https://github.com/lwouis/alt-tab-macos/issues/5235)) ([7fdfe4a](https://github.com/lwouis/alt-tab-macos/commit/7fdfe4a))

## [8.3.2](https://github.com/lwouis/alt-tab-macos/compare/v8.3.1...v8.3.2) (2026-01-22)


### Bug Fixes

* blacklisting fullscreen windows was not working (closes [#5228](https://github.com/lwouis/alt-tab-macos/issues/5228)) ([53815e0](https://github.com/lwouis/alt-tab-macos/commit/53815e0))

## [8.3.1](https://github.com/lwouis/alt-tab-macos/compare/v8.3.0...v8.3.1) (2026-01-22)


### Bug Fixes

* chrome apps windows would not show in the switcher (closes [#5227](https://github.com/lwouis/alt-tab-macos/issues/5227)) ([bf3fa67](https://github.com/lwouis/alt-tab-macos/commit/bf3fa67))

# [8.3.0](https://github.com/lwouis/alt-tab-macos/compare/v8.2.0...v8.3.0) (2026-01-20)


### Bug Fixes

* position of windowless indicator in thumbnails appearance ([d1fd1fd](https://github.com/lwouis/alt-tab-macos/commit/d1fd1fd))
* small memory leak when opening the switcher (closes [#4255](https://github.com/lwouis/alt-tab-macos/issues/4255)) ([0a6485e](https://github.com/lwouis/alt-tab-macos/commit/0a6485e))
* windows would sometimes not update their order (closes [#5207](https://github.com/lwouis/alt-tab-macos/issues/5207)) ([a3f2a54](https://github.com/lwouis/alt-tab-macos/commit/a3f2a54))


### Features

* increase apparition delay granularity (closes [#5210](https://github.com/lwouis/alt-tab-macos/issues/5210)) ([5b0df6b](https://github.com/lwouis/alt-tab-macos/commit/5b0df6b))

# [8.2.0](https://github.com/lwouis/alt-tab-macos/compare/v8.1.0...v8.2.0) (2026-01-15)


### Bug Fixes

* thumbnails could sometimes be stretched (closes [#5204](https://github.com/lwouis/alt-tab-macos/issues/5204)) ([ac24d6d](https://github.com/lwouis/alt-tab-macos/commit/ac24d6d))


### Features

* stop checking screen-recording permission after launch ([#5202](https://github.com/lwouis/alt-tab-macos/issues/5202)) ([f481d22](https://github.com/lwouis/alt-tab-macos/commit/f481d22))

# [8.1.0](https://github.com/lwouis/alt-tab-macos/compare/v8.0.0...v8.1.0) (2026-01-14)


### Bug Fixes

* allow f-keys as shortcuts-when-active (closes [#5166](https://github.com/lwouis/alt-tab-macos/issues/5166)) ([a0c9fee](https://github.com/lwouis/alt-tab-macos/commit/a0c9fee))
* avoid unintentional trackpad trigger (closes [#4278](https://github.com/lwouis/alt-tab-macos/issues/4278)) ([0539a3a](https://github.com/lwouis/alt-tab-macos/commit/0539a3a))
* better handle palm/fingers resting on the trackpad (closes [#5191](https://github.com/lwouis/alt-tab-macos/issues/5191)) ([9ed8a19](https://github.com/lwouis/alt-tab-macos/commit/9ed8a19))
* mitigate macos 15 bugs with screencapture-kit (closes [#5190](https://github.com/lwouis/alt-tab-macos/issues/5190)) ([b2f5c6c](https://github.com/lwouis/alt-tab-macos/commit/b2f5c6c))
* mouse hover detection for hidden/windowless apps ([7c64864](https://github.com/lwouis/alt-tab-macos/commit/7c64864))
* thumbnails could sometimes be the wrong size ([9d0b947](https://github.com/lwouis/alt-tab-macos/commit/9d0b947))


### Features

* add belarusian localization ([0fe722b](https://github.com/lwouis/alt-tab-macos/commit/0fe722b))
* improve accidental cursor movement ([74b5a11](https://github.com/lwouis/alt-tab-macos/commit/74b5a11)), closes [/github.com/lwouis/alt-tab-macos/issues/4278#issuecomment-3733280737](https://github.com//github.com/lwouis/alt-tab-macos/issues/4278/issues/issuecomment-3733280737)
* improve pl localization ([3b53ce7](https://github.com/lwouis/alt-tab-macos/commit/3b53ce7))
* show outline of windows hidden for privacy reasons (closes [#5172](https://github.com/lwouis/alt-tab-macos/issues/5172)) ([1090acf](https://github.com/lwouis/alt-tab-macos/commit/1090acf))

# [8.0.0](https://github.com/lwouis/alt-tab-macos/compare/v7.39.0...v8.0.0) (2026-01-06)


### Bug Fixes

* avoid macos bug where many permission dialogs pop (closes [#5106](https://github.com/lwouis/alt-tab-macos/issues/5106)) ([5c4199e](https://github.com/lwouis/alt-tab-macos/commit/5c4199e))


### Features

* improve memory image of showing app icons (closes [#5144](https://github.com/lwouis/alt-tab-macos/issues/5144)) ([bf58335](https://github.com/lwouis/alt-tab-macos/commit/bf58335))
* improve ta localization ([989b344](https://github.com/lwouis/alt-tab-macos/commit/989b344))
* improve thumbnails with screen-capture kit ([7821d7c](https://github.com/lwouis/alt-tab-macos/commit/7821d7c)), closes [#4255](https://github.com/lwouis/alt-tab-macos/issues/4255) [#3652](https://github.com/lwouis/alt-tab-macos/issues/3652)


### Performance Improvements

* debounce screen/space events to minimize work ([e2b4779](https://github.com/lwouis/alt-tab-macos/commit/e2b4779))


### BREAKING CHANGES

* Better thumbnails with ScreenCaptureKit for users on macOS >= 14

# [7.39.0](https://github.com/lwouis/alt-tab-macos/compare/v7.38.1...v7.39.0) (2026-01-03)


### Bug Fixes

* avoid showing closed windows (closes [#3589](https://github.com/lwouis/alt-tab-macos/issues/3589)) ([894a69d](https://github.com/lwouis/alt-tab-macos/commit/894a69d)), closes [#4924](https://github.com/lwouis/alt-tab-macos/issues/4924)
* permission checks might freeze or restart the app (closes [#5112](https://github.com/lwouis/alt-tab-macos/issues/5112)) ([7906d63](https://github.com/lwouis/alt-tab-macos/commit/7906d63))
* permission window could steal focus (see [#3577](https://github.com/lwouis/alt-tab-macos/issues/3577)) ([2f875b3](https://github.com/lwouis/alt-tab-macos/commit/2f875b3))
* permissions window could look wrong in some languages like chinese ([914f91f](https://github.com/lwouis/alt-tab-macos/commit/914f91f)), closes [/github.com/lwouis/alt-tab-macos/issues/5112#issuecomment-3692769341](https://github.com//github.com/lwouis/alt-tab-macos/issues/5112/issues/issuecomment-3692769341)
* preview could sometimes be incorrectly positioned ([edc2f00](https://github.com/lwouis/alt-tab-macos/commit/edc2f00))
* show some hovering windows (e.g. zoom.app) (closes [#5140](https://github.com/lwouis/alt-tab-macos/issues/5140)) ([fcc6651](https://github.com/lwouis/alt-tab-macos/commit/fcc6651))
* thumbnails could sometimes have the wrong size ([55f3f59](https://github.com/lwouis/alt-tab-macos/commit/55f3f59))


### Features

* avoid occasional delays in showing the switcher (closes [#5109](https://github.com/lwouis/alt-tab-macos/issues/5109)) ([3c04a4c](https://github.com/lwouis/alt-tab-macos/commit/3c04a4c))
* improve nb/tr localizations ([5e842d5](https://github.com/lwouis/alt-tab-macos/commit/5e842d5))
* remove shadow around app icon appearance ([dda612c](https://github.com/lwouis/alt-tab-macos/commit/dda612c))


### Performance Improvements

* do login item and plist updates later to accelerate launch ([2f72c5d](https://github.com/lwouis/alt-tab-macos/commit/2f72c5d))
* don't compute diffs of running-apps; directly get new/old ([7ded01c](https://github.com/lwouis/alt-tab-macos/commit/7ded01c))
* improve mouse hover algo and core-animation side ([6103785](https://github.com/lwouis/alt-tab-macos/commit/6103785))

## [7.38.1](https://github.com/lwouis/alt-tab-macos/compare/v7.38.0...v7.38.1) (2025-12-13)


### Bug Fixes

* could sometimes freeze on the permission window ([43838e1](https://github.com/lwouis/alt-tab-macos/commit/43838e1)), closes [#5112](https://github.com/lwouis/alt-tab-macos/issues/5112)
* prevent crash when sending a debug profile ([741e790](https://github.com/lwouis/alt-tab-macos/commit/741e790))

# [7.38.0](https://github.com/lwouis/alt-tab-macos/compare/v7.37.0...v7.38.0) (2025-12-07)


### Bug Fixes

* could sometimes freeze upon launch (closes [#5079](https://github.com/lwouis/alt-tab-macos/issues/5079)) ([ee27df7](https://github.com/lwouis/alt-tab-macos/commit/ee27df7))
* sending feedback with a debug-profile could sometimes crash ([e0ae29d](https://github.com/lwouis/alt-tab-macos/commit/e0ae29d))


### Features

* improve ca/es/ga/pt/pt-br/uk localizations ([8a98b4e](https://github.com/lwouis/alt-tab-macos/commit/8a98b4e))
* prevent mouse-hover when using trackpad swipes (closes [#5071](https://github.com/lwouis/alt-tab-macos/issues/5071)) ([b8ecd58](https://github.com/lwouis/alt-tab-macos/commit/b8ecd58))

# [7.37.0](https://github.com/lwouis/alt-tab-macos/compare/v7.36.0...v7.37.0) (2025-11-28)


### Bug Fixes

* better crop app icons on macos < 26 (closes [#5080](https://github.com/lwouis/alt-tab-macos/issues/5080)) ([237bb1e](https://github.com/lwouis/alt-tab-macos/commit/237bb1e))


### Features

* improve portuguese localization ([3994429](https://github.com/lwouis/alt-tab-macos/commit/3994429))
* warn tahoe users of shortcut conflict with macos game-overlay ([911aad4](https://github.com/lwouis/alt-tab-macos/commit/911aad4)), closes [#5018](https://github.com/lwouis/alt-tab-macos/issues/5018)

# [7.36.0](https://github.com/lwouis/alt-tab-macos/compare/v7.35.0...v7.36.0) (2025-11-25)


### Bug Fixes

* switcher could become broken after changing appearance ([d377b3d](https://github.com/lwouis/alt-tab-macos/commit/d377b3d)), closes [#5061](https://github.com/lwouis/alt-tab-macos/issues/5061)


### Features

* improve portuguese localization ([435a310](https://github.com/lwouis/alt-tab-macos/commit/435a310))

# [7.35.0](https://github.com/lwouis/alt-tab-macos/compare/v7.34.0...v7.35.0) (2025-11-24)


### Bug Fixes

* app would sometimes crash on macos monterey (closes [#5051](https://github.com/lwouis/alt-tab-macos/issues/5051)) ([29e1cff](https://github.com/lwouis/alt-tab-macos/commit/29e1cff))
* better gesture recognition (closes [#5039](https://github.com/lwouis/alt-tab-macos/issues/5039)) ([1689954](https://github.com/lwouis/alt-tab-macos/commit/1689954))
* closing fullscreen window would glitch it (closes [#5029](https://github.com/lwouis/alt-tab-macos/issues/5029)) ([ee436cc](https://github.com/lwouis/alt-tab-macos/commit/ee436cc))


### Features

* add trackpad haptic feedback for better navigation (closes [#4763](https://github.com/lwouis/alt-tab-macos/issues/4763)) ([fb5dfc4](https://github.com/lwouis/alt-tab-macos/commit/fb5dfc4))
* better icon for feedback form (closes [#5013](https://github.com/lwouis/alt-tab-macos/issues/5013)) ([2c3373a](https://github.com/lwouis/alt-tab-macos/commit/2c3373a))
* improve portuguese localization ([c294ad0](https://github.com/lwouis/alt-tab-macos/commit/c294ad0))

# [7.34.0](https://github.com/lwouis/alt-tab-macos/compare/v7.33.0...v7.34.0) (2025-11-20)


### Bug Fixes

* reduce memory footprint after running for a while (closes [#4255](https://github.com/lwouis/alt-tab-macos/issues/4255)) ([938b735](https://github.com/lwouis/alt-tab-macos/commit/938b735))


### Features

* improve localizations ([516329a](https://github.com/lwouis/alt-tab-macos/commit/516329a))
* improve responsiveness in showing switcher (closes [#4959](https://github.com/lwouis/alt-tab-macos/issues/4959)) ([a80721b](https://github.com/lwouis/alt-tab-macos/commit/a80721b))

# [7.33.0](https://github.com/lwouis/alt-tab-macos/compare/v7.32.0...v7.33.0) (2025-11-16)


### Bug Fixes

* app icon was too small in titles-appearance large-size ([ffd0c75](https://github.com/lwouis/alt-tab-macos/commit/ffd0c75))
* take into account accent-color immediatly (closes [#4984](https://github.com/lwouis/alt-tab-macos/issues/4984)) ([011fdba](https://github.com/lwouis/alt-tab-macos/commit/011fdba))


### Features

* improve dealing with reserved/conflicting shortcuts ([fdf3134](https://github.com/lwouis/alt-tab-macos/commit/fdf3134)), closes [#3190](https://github.com/lwouis/alt-tab-macos/issues/3190) [#3288](https://github.com/lwouis/alt-tab-macos/issues/3288) [#1835](https://github.com/lwouis/alt-tab-macos/issues/1835) [#3826](https://github.com/lwouis/alt-tab-macos/issues/3826)
* improve nl/pl/uk localizations ([96caad4](https://github.com/lwouis/alt-tab-macos/commit/96caad4))
* improve trackpad multi-fingers swiping (closes [#4765](https://github.com/lwouis/alt-tab-macos/issues/4765)) ([d6196ec](https://github.com/lwouis/alt-tab-macos/commit/d6196ec))
* improve ux for titles-appearance (closes [#4975](https://github.com/lwouis/alt-tab-macos/issues/4975)) ([c352591](https://github.com/lwouis/alt-tab-macos/commit/c352591))
* macos tahoe improvements: menubar menu, feedback form, wording ([309cae3](https://github.com/lwouis/alt-tab-macos/commit/309cae3)), closes [#4986](https://github.com/lwouis/alt-tab-macos/issues/4986)

# [7.32.0](https://github.com/lwouis/alt-tab-macos/compare/v7.31.0...v7.32.0) (2025-11-10)


### Bug Fixes

* alt-tab could crash if asked to close one of its own window ([f46372b](https://github.com/lwouis/alt-tab-macos/commit/f46372b))
* could sometimes crash when navigating up or down (closes [#4110](https://github.com/lwouis/alt-tab-macos/issues/4110)) ([d2220c6](https://github.com/lwouis/alt-tab-macos/commit/d2220c6))


### Features

* improve pl/zh-hk localizations ([786e752](https://github.com/lwouis/alt-tab-macos/commit/786e752))
* improve responsiveness of showing the switcher ([689adc0](https://github.com/lwouis/alt-tab-macos/commit/689adc0))
* new look for tahoe and liquid glass (closes [#4658](https://github.com/lwouis/alt-tab-macos/issues/4658)) ([fab9d7c](https://github.com/lwouis/alt-tab-macos/commit/fab9d7c))
* titles appearance now resizes for better readability ([26d40e1](https://github.com/lwouis/alt-tab-macos/commit/26d40e1)), closes [#3882](https://github.com/lwouis/alt-tab-macos/issues/3882)
* update visuals for macos tahoe and liquid glass ([33c6615](https://github.com/lwouis/alt-tab-macos/commit/33c6615))


### Performance Improvements

* improve rendering performance by doing less work ([ec55ae8](https://github.com/lwouis/alt-tab-macos/commit/ec55ae8))

# [7.31.0](https://github.com/lwouis/alt-tab-macos/compare/v7.30.0...v7.31.0) (2025-10-26)


### Bug Fixes

* cmd+q would quit alt-tab instead of the selected app (closes [#4867](https://github.com/lwouis/alt-tab-macos/issues/4867)) ([247f635](https://github.com/lwouis/alt-tab-macos/commit/247f635)), closes [#4891](https://github.com/lwouis/alt-tab-macos/issues/4891)
* title was truncated in app-icons appearance (closes [#4860](https://github.com/lwouis/alt-tab-macos/issues/4860)) ([a1cfd1d](https://github.com/lwouis/alt-tab-macos/commit/a1cfd1d))


### Features

* improve ar/de/fr/kn/ru/zh-tw localizations ([173bc97](https://github.com/lwouis/alt-tab-macos/commit/173bc97))
* improve windows detection ([cab591e](https://github.com/lwouis/alt-tab-macos/commit/cab591e))
* new cli command to focus a window using focus order (closes [#4610](https://github.com/lwouis/alt-tab-macos/issues/4610)) ([84166ab](https://github.com/lwouis/alt-tab-macos/commit/84166ab))
* save resources trying to detect certain windows ([33e5acf](https://github.com/lwouis/alt-tab-macos/commit/33e5acf))

# [7.30.0](https://github.com/lwouis/alt-tab-macos/compare/v7.29.0...v7.30.0) (2025-09-23)


### Bug Fixes

* bring back pre-v7.28 performance (closes [#4805](https://github.com/lwouis/alt-tab-macos/issues/4805)) ([fb6110d](https://github.com/lwouis/alt-tab-macos/commit/fb6110d))


### Features

* improve nb/nl/zh-tw localizations ([a9cb03c](https://github.com/lwouis/alt-tab-macos/commit/a9cb03c))

# [7.29.0](https://github.com/lwouis/alt-tab-macos/compare/v7.28.0...v7.29.0) (2025-09-20)


### Bug Fixes

* windows order was not updating correctly (closes [#4754](https://github.com/lwouis/alt-tab-macos/issues/4754)) ([1316eb2](https://github.com/lwouis/alt-tab-macos/commit/1316eb2))


### Features

* improve fr/ja languages ([c5286c3](https://github.com/lwouis/alt-tab-macos/commit/c5286c3))

# [7.28.0](https://github.com/lwouis/alt-tab-macos/compare/v7.27.0...v7.28.0) (2025-09-15)


### Bug Fixes

* focusing windows could fail after focusing a frozen app ([#4520](https://github.com/lwouis/alt-tab-macos/issues/4520)) ([591ce52](https://github.com/lwouis/alt-tab-macos/commit/591ce52))
* improve detection of windows (closes [#4405](https://github.com/lwouis/alt-tab-macos/issues/4405)) ([3c79840](https://github.com/lwouis/alt-tab-macos/commit/3c79840))
* keyboard selection now works with dragging + mouse hover ([be077f1](https://github.com/lwouis/alt-tab-macos/commit/be077f1)), closes [#4711](https://github.com/lwouis/alt-tab-macos/issues/4711)
* remove high-volume unactionable logs (closes [#4697](https://github.com/lwouis/alt-tab-macos/issues/4697)) ([e93e42f](https://github.com/lwouis/alt-tab-macos/commit/e93e42f))


### Features

* add gujarati localization ([4ebd990](https://github.com/lwouis/alt-tab-macos/commit/4ebd990))
* add hong-kong cantonese + improve other languages ([78c8525](https://github.com/lwouis/alt-tab-macos/commit/78c8525))
* add preference to show only non-active apps (closes [#4691](https://github.com/lwouis/alt-tab-macos/issues/4691)) ([4567550](https://github.com/lwouis/alt-tab-macos/commit/4567550))
* improve norwegian localization ([726e13e](https://github.com/lwouis/alt-tab-macos/commit/726e13e))
* more fine-grained cursor-follows-focus preference (closes [#4734](https://github.com/lwouis/alt-tab-macos/issues/4734)) ([985a681](https://github.com/lwouis/alt-tab-macos/commit/985a681))

# [7.27.0](https://github.com/lwouis/alt-tab-macos/compare/v7.26.0...v7.27.0) (2025-08-12)


### Bug Fixes

* restore default command+tab if shortcut is unbound (closes [#4642](https://github.com/lwouis/alt-tab-macos/issues/4642)) ([f66c92a](https://github.com/lwouis/alt-tab-macos/commit/f66c92a))


### Features

* improve cs/th localizations ([aa46a62](https://github.com/lwouis/alt-tab-macos/commit/aa46a62))
* windowless apps can now be shown in focus-order (closes [#4653](https://github.com/lwouis/alt-tab-macos/issues/4653)) ([5db53b5](https://github.com/lwouis/alt-tab-macos/commit/5db53b5))

# [7.26.0](https://github.com/lwouis/alt-tab-macos/compare/v7.25.0...v7.26.0) (2025-07-31)


### Bug Fixes

* ignore autodesk fusion internal panels (closes [#4578](https://github.com/lwouis/alt-tab-macos/issues/4578)) ([f67d182](https://github.com/lwouis/alt-tab-macos/commit/f67d182))


### Features

* improve da/fi/ga localizations ([f376529](https://github.com/lwouis/alt-tab-macos/commit/f376529))
* improve preference to show-apps-with-open-window (closes [#4485](https://github.com/lwouis/alt-tab-macos/issues/4485)) ([67f5098](https://github.com/lwouis/alt-tab-macos/commit/67f5098))

# [7.25.0](https://github.com/lwouis/alt-tab-macos/compare/v7.24.0...v7.25.0) (2025-06-14)


### Bug Fixes

* icons on thumbnails could sometimes be incorrect ([b4bc0b0](https://github.com/lwouis/alt-tab-macos/commit/b4bc0b0))


### Features

* new cli commands: --show, --detailed-list (closes [#4489](https://github.com/lwouis/alt-tab-macos/issues/4489)) ([b0ce899](https://github.com/lwouis/alt-tab-macos/commit/b0ce899))

# [7.24.0](https://github.com/lwouis/alt-tab-macos/compare/v7.23.0...v7.24.0) (2025-05-05)


### Features

* clicking to focus windows/apps is now easier (closes [#4407](https://github.com/lwouis/alt-tab-macos/issues/4407)) ([397457c](https://github.com/lwouis/alt-tab-macos/commit/397457c))
* improve ca/pt/ro localizations ([8b7d69c](https://github.com/lwouis/alt-tab-macos/commit/8b7d69c))


### Performance Improvements

* avoid updating preview if not necessary ([518f8b4](https://github.com/lwouis/alt-tab-macos/commit/518f8b4))

# [7.23.0](https://github.com/lwouis/alt-tab-macos/compare/v7.22.0...v7.23.0) (2025-04-01)


### Bug Fixes

* avoid crashing on uncommon keys in shortcuts (closes [#4379](https://github.com/lwouis/alt-tab-macos/issues/4379)) ([9d852ee](https://github.com/lwouis/alt-tab-macos/commit/9d852ee))
* window name would sometimes be empty (closes [#4350](https://github.com/lwouis/alt-tab-macos/issues/4350)) ([911c3c1](https://github.com/lwouis/alt-tab-macos/commit/911c3c1))


### Features

* improve hindi localization ([dec0519](https://github.com/lwouis/alt-tab-macos/commit/dec0519))

# [7.22.0](https://github.com/lwouis/alt-tab-macos/compare/v7.21.1...v7.22.0) (2025-03-30)


### Bug Fixes

* language switcher picked up as window ([f4f7d9a](https://github.com/lwouis/alt-tab-macos/commit/f4f7d9a))
* prevent rare crash ([4e35f9f](https://github.com/lwouis/alt-tab-macos/commit/4e35f9f))


### Features

* update ca/de/fr/ko/ru/tw localizations ([9b3f936](https://github.com/lwouis/alt-tab-macos/commit/9b3f936))

## [7.21.1](https://github.com/lwouis/alt-tab-macos/compare/v7.21.0...v7.21.1) (2025-02-22)


### Bug Fixes

* update how feedback messages are sent ([647f900](https://github.com/lwouis/alt-tab-macos/commit/647f900))

# [7.21.0](https://github.com/lwouis/alt-tab-macos/compare/v7.20.1...v7.21.0) (2025-02-21)


### Bug Fixes

* app would sometimes crash (closes [#4244](https://github.com/lwouis/alt-tab-macos/issues/4244)) ([d543393](https://github.com/lwouis/alt-tab-macos/commit/d543393))


### Features

* add lithuanian localization ([bc95b90](https://github.com/lwouis/alt-tab-macos/commit/bc95b90))
* improve chinese localization ([330ac54](https://github.com/lwouis/alt-tab-macos/commit/330ac54))

## [7.20.1](https://github.com/lwouis/alt-tab-macos/compare/v7.20.0...v7.20.1) (2025-02-20)


### Bug Fixes

* may crash when changing space or screen ([b62cec0](https://github.com/lwouis/alt-tab-macos/commit/b62cec0))

# [7.20.0](https://github.com/lwouis/alt-tab-macos/compare/v7.19.1...v7.20.0) (2025-02-19)


### Bug Fixes

* better detect windows from other spaces (closes [#1324](https://github.com/lwouis/alt-tab-macos/issues/1324)) ([2cd8b96](https://github.com/lwouis/alt-tab-macos/commit/2cd8b96))
* colored circles would go away on ui refresh (closes [#4151](https://github.com/lwouis/alt-tab-macos/issues/4151)) ([dcea005](https://github.com/lwouis/alt-tab-macos/commit/dcea005))
* stage manager no longer skews the thumbnails (closes [#1731](https://github.com/lwouis/alt-tab-macos/issues/1731)) ([93defcd](https://github.com/lwouis/alt-tab-macos/commit/93defcd))
* window might be noted to be on the wrong space ([5413372](https://github.com/lwouis/alt-tab-macos/commit/5413372))


### Features

* add javanese localization ([8564ed2](https://github.com/lwouis/alt-tab-macos/commit/8564ed2))
* improve performance and lower resources consumption ([9d78700](https://github.com/lwouis/alt-tab-macos/commit/9d78700))
* improve thumbnails quality and performance (closes [#4183](https://github.com/lwouis/alt-tab-macos/issues/4183)) ([9d6fc68](https://github.com/lwouis/alt-tab-macos/commit/9d6fc68))
* improve window focusing action ([8dd63c7](https://github.com/lwouis/alt-tab-macos/commit/8dd63c7))
* update fr, kn, pt-br, uk localizations ([fd0411b](https://github.com/lwouis/alt-tab-macos/commit/fd0411b))

## [7.19.1](https://github.com/lwouis/alt-tab-macos/compare/v7.19.0...v7.19.1) (2025-01-14)


### Bug Fixes

* a few labels were not displaying (closes [#4127](https://github.com/lwouis/alt-tab-macos/issues/4127)) ([0a22547](https://github.com/lwouis/alt-tab-macos/commit/0a22547))

# [7.19.0](https://github.com/lwouis/alt-tab-macos/compare/v7.18.1...v7.19.0) (2025-01-14)


### Features

* add preference to toggle animation of preview (closes [#4118](https://github.com/lwouis/alt-tab-macos/issues/4118)) ([c10ca2a](https://github.com/lwouis/alt-tab-macos/commit/c10ca2a))
* middle-click will now close windows and quit applications ([2f8c014](https://github.com/lwouis/alt-tab-macos/commit/2f8c014))

## [7.18.1](https://github.com/lwouis/alt-tab-macos/compare/v7.18.0...v7.18.1) (2025-01-12)


### Bug Fixes

* don't check screen-recording permission if unnecessary ([f3b116e](https://github.com/lwouis/alt-tab-macos/commit/f3b116e)), closes [#4113](https://github.com/lwouis/alt-tab-macos/issues/4113)
* show shadows around thumbnails (closes [#4068](https://github.com/lwouis/alt-tab-macos/issues/4068)) ([597b443](https://github.com/lwouis/alt-tab-macos/commit/597b443))

# [7.18.0](https://github.com/lwouis/alt-tab-macos/compare/v7.17.0...v7.18.0) (2025-01-07)


### Bug Fixes

* various issues with the app freezing or being slowly ([121515c](https://github.com/lwouis/alt-tab-macos/commit/121515c))
* window order on first display was wrong ([db5644e](https://github.com/lwouis/alt-tab-macos/commit/db5644e))
* window preview was not showing in titles style ([684cc66](https://github.com/lwouis/alt-tab-macos/commit/684cc66))


### Features

* improve polish localization ([c712473](https://github.com/lwouis/alt-tab-macos/commit/c712473))

# [7.17.0](https://github.com/lwouis/alt-tab-macos/compare/v7.16.0...v7.17.0) (2025-01-05)


### Bug Fixes

* app icons could sometimes be at the wrong size ([d5d1311](https://github.com/lwouis/alt-tab-macos/commit/d5d1311))
* more robust screen-recording permission detection ([d85ec7b](https://github.com/lwouis/alt-tab-macos/commit/d85ec7b))


### Features

* handle cli commands: --list and --focus=window_id ([0f2c0e7](https://github.com/lwouis/alt-tab-macos/commit/0f2c0e7))

# [7.16.0](https://github.com/lwouis/alt-tab-macos/compare/v7.15.0...v7.16.0) (2025-01-04)


### Bug Fixes

* app badges could be incorrectly positioned on the very first launch ([c2ccccd](https://github.com/lwouis/alt-tab-macos/commit/c2ccccd))
* app-icons wouldn't show when permissions were skipped ([837fa03](https://github.com/lwouis/alt-tab-macos/commit/837fa03))
* screen recording warnings shouldn't appear with skipped permissions ([f027b47](https://github.com/lwouis/alt-tab-macos/commit/f027b47))


### Features

* improve performance by caching preferences better ([d653a54](https://github.com/lwouis/alt-tab-macos/commit/d653a54))

# [7.15.0](https://github.com/lwouis/alt-tab-macos/compare/v7.14.1...v7.15.0) (2025-01-02)


### Bug Fixes

* better position preview for fullscreen windows (closes [#4051](https://github.com/lwouis/alt-tab-macos/issues/4051)) ([3b0cba4](https://github.com/lwouis/alt-tab-macos/commit/3b0cba4))
* layout was sometimes broken in app-icons style (closes [#4036](https://github.com/lwouis/alt-tab-macos/issues/4036)) ([be5eb26](https://github.com/lwouis/alt-tab-macos/commit/be5eb26))


### Features

* improve chinese-taiwanese localization ([dfcf9de](https://github.com/lwouis/alt-tab-macos/commit/dfcf9de))
* improve performance and order accuracy at launch ([fc6d636](https://github.com/lwouis/alt-tab-macos/commit/fc6d636))
* improve quality of thumbnails and performance ([a138a92](https://github.com/lwouis/alt-tab-macos/commit/a138a92))
* reduce space between app icon and window title ([295eb2b](https://github.com/lwouis/alt-tab-macos/commit/295eb2b))
* switcher displays faster; other performance improvements ([b51ff65](https://github.com/lwouis/alt-tab-macos/commit/b51ff65))

## [7.14.1](https://github.com/lwouis/alt-tab-macos/compare/v7.14.0...v7.14.1) (2024-12-28)


### Bug Fixes

* improve label display in app-icons style ([7e501a4](https://github.com/lwouis/alt-tab-macos/commit/7e501a4))
* title would sometimes not show when mouse hovering ([dd05ba2](https://github.com/lwouis/alt-tab-macos/commit/dd05ba2))

# [7.14.0](https://github.com/lwouis/alt-tab-macos/compare/v7.13.1...v7.14.0) (2024-12-26)


### Bug Fixes

* improve acknowledgments tab (closes [#4025](https://github.com/lwouis/alt-tab-macos/issues/4025)) ([db5500f](https://github.com/lwouis/alt-tab-macos/commit/db5500f))


### Features

* clear feedback form after submission (closes [#4026](https://github.com/lwouis/alt-tab-macos/issues/4026)) ([42bbd0f](https://github.com/lwouis/alt-tab-macos/commit/42bbd0f))
* improve chinese, irish, italian localizations ([18ef16f](https://github.com/lwouis/alt-tab-macos/commit/18ef16f))
* swipes can now be horizontal or vertical (closes [#4020](https://github.com/lwouis/alt-tab-macos/issues/4020)) ([fda3ada](https://github.com/lwouis/alt-tab-macos/commit/fda3ada))

## [7.13.1](https://github.com/lwouis/alt-tab-macos/compare/v7.13.0...v7.13.1) (2024-12-24)


### Bug Fixes

* acknowledgments tab was hard to read in dark mode (closes [#4019](https://github.com/lwouis/alt-tab-macos/issues/4019)) ([4481d94](https://github.com/lwouis/alt-tab-macos/commit/4481d94))
* app crash from v7.13.0 (closes [#4016](https://github.com/lwouis/alt-tab-macos/issues/4016)) ([d3b5bef](https://github.com/lwouis/alt-tab-macos/commit/d3b5bef))

# [7.13.0](https://github.com/lwouis/alt-tab-macos/compare/v7.12.0...v7.13.0) (2024-12-24)


### Bug Fixes

* enabling previews with multiple screens could lead to flickering ([87a2b21](https://github.com/lwouis/alt-tab-macos/commit/87a2b21))
* prevent initial window lastFocusOrder overlaps ([d32f953](https://github.com/lwouis/alt-tab-macos/commit/d32f953))
* previews on multiple screens could get misplaced ([2a0a858](https://github.com/lwouis/alt-tab-macos/commit/2a0a858))
* titles could sometimes be covered when in small size ([c5e13cc](https://github.com/lwouis/alt-tab-macos/commit/c5e13cc))


### Features

* add fade-in for window previews (closes [#2456](https://github.com/lwouis/alt-tab-macos/issues/2456)) ([40c9a18](https://github.com/lwouis/alt-tab-macos/commit/40c9a18))
* allow vertical swipes as trigger (closes [#4012](https://github.com/lwouis/alt-tab-macos/issues/4012)) ([9adf64c](https://github.com/lwouis/alt-tab-macos/commit/9adf64c))
* improve localizations ([6d9059e](https://github.com/lwouis/alt-tab-macos/commit/6d9059e))
* reduce disk size of localizations ([9ec2762](https://github.com/lwouis/alt-tab-macos/commit/9ec2762))
* swiping won't wrap-around to other rows (closes [#3983](https://github.com/lwouis/alt-tab-macos/issues/3983)) ([6215b65](https://github.com/lwouis/alt-tab-macos/commit/6215b65))

# [7.12.0](https://github.com/lwouis/alt-tab-macos/compare/v7.11.0...v7.12.0) (2024-12-11)


### Bug Fixes

* switcher could appear collapsed in titles style (closes [#3744](https://github.com/lwouis/alt-tab-macos/issues/3744)) ([60534bc](https://github.com/lwouis/alt-tab-macos/commit/60534bc))


### Features

* acknowledgments tab was slow to display (closes [#3957](https://github.com/lwouis/alt-tab-macos/issues/3957)) ([41ddd7c](https://github.com/lwouis/alt-tab-macos/commit/41ddd7c))

# [7.11.0](https://github.com/lwouis/alt-tab-macos/compare/v7.10.0...v7.11.0) (2024-12-09)


### Bug Fixes

* always show a window in show:apps mode (closes [#3950](https://github.com/lwouis/alt-tab-macos/issues/3950)) ([ac70fcc](https://github.com/lwouis/alt-tab-macos/commit/ac70fcc))


### Features

* decrease shortcuts from 5 to 3 ([d65f220](https://github.com/lwouis/alt-tab-macos/commit/d65f220))
* improve chinese localization ([764e0f3](https://github.com/lwouis/alt-tab-macos/commit/764e0f3))
* improve focus in show:apps mode (closes [#3951](https://github.com/lwouis/alt-tab-macos/issues/3951)) ([cb191d6](https://github.com/lwouis/alt-tab-macos/commit/cb191d6))
* support 3 or 4 finger swipes to use the app (closes [#730](https://github.com/lwouis/alt-tab-macos/issues/730)) ([903e758](https://github.com/lwouis/alt-tab-macos/commit/903e758))
* switcher will now show in "show desktop" mode (closes [#783](https://github.com/lwouis/alt-tab-macos/issues/783)) ([9b85f00](https://github.com/lwouis/alt-tab-macos/commit/9b85f00))

# [7.10.0](https://github.com/lwouis/alt-tab-macos/compare/v7.9.0...v7.10.0) (2024-12-08)


### Features

* improve catalan localization ([7e199f6](https://github.com/lwouis/alt-tab-macos/commit/7e199f6))
* make it more clear how to hide the menubar icon (closes [#503](https://github.com/lwouis/alt-tab-macos/issues/503)) ([9ca0649](https://github.com/lwouis/alt-tab-macos/commit/9ca0649))

# [7.9.0](https://github.com/lwouis/alt-tab-macos/compare/v7.8.0...v7.9.0) (2024-12-07)


### Features

* improve catalan and taiwanese localizations ([bf3a4dc](https://github.com/lwouis/alt-tab-macos/commit/bf3a4dc))
* try to avoid launching multiple instances at login (closes [#1840](https://github.com/lwouis/alt-tab-macos/issues/1840)) ([e4cfd85](https://github.com/lwouis/alt-tab-macos/commit/e4cfd85))

# [7.8.0](https://github.com/lwouis/alt-tab-macos/compare/v7.7.0...v7.8.0) (2024-12-06)


### Features

* bring back the cursor follow focus feature ([#3882](https://github.com/lwouis/alt-tab-macos/issues/3882)) ([73382db](https://github.com/lwouis/alt-tab-macos/commit/73382db))
* improve display of very small windows (closes [#3902](https://github.com/lwouis/alt-tab-macos/issues/3902)) ([9bafd03](https://github.com/lwouis/alt-tab-macos/commit/9bafd03))
* improve irish localization ([89c02c9](https://github.com/lwouis/alt-tab-macos/commit/89c02c9))
* switcher will show faster (closes [#3845](https://github.com/lwouis/alt-tab-macos/issues/3845)) ([b694c83](https://github.com/lwouis/alt-tab-macos/commit/b694c83))

# [7.7.0](https://github.com/lwouis/alt-tab-macos/compare/v7.6.0...v7.7.0) (2024-12-03)


### Bug Fixes

* [after release: do nothing] was broken in v7.6.0 (closes [#3929](https://github.com/lwouis/alt-tab-macos/issues/3929)) ([83b5319](https://github.com/lwouis/alt-tab-macos/commit/83b5319))


### Features

* improve chinese localization ([17e9599](https://github.com/lwouis/alt-tab-macos/commit/17e9599))
* improve tooltips in preferences ([f97e9f9](https://github.com/lwouis/alt-tab-macos/commit/f97e9f9))

# [7.6.0](https://github.com/lwouis/alt-tab-macos/compare/v7.5.0...v7.6.0) (2024-12-01)


### Features

* better display on some external monitors (closes [#3866](https://github.com/lwouis/alt-tab-macos/issues/3866)) ([165a669](https://github.com/lwouis/alt-tab-macos/commit/165a669))
* improve keyboard handling when macos is overwhelmed ([4a9b543](https://github.com/lwouis/alt-tab-macos/commit/4a9b543))
* improve korean localization ([22aafce](https://github.com/lwouis/alt-tab-macos/commit/22aafce))

# [7.5.0](https://github.com/lwouis/alt-tab-macos/compare/v7.4.0...v7.5.0) (2024-11-27)


### Features

* improve da, hu, tr localizations ([ffdab44](https://github.com/lwouis/alt-tab-macos/commit/ffdab44))
* in-app feedback form now requires a title ([05851fb](https://github.com/lwouis/alt-tab-macos/commit/05851fb))
* update switcher max-width to 90% of screen, like windows 11 ([a94eeb0](https://github.com/lwouis/alt-tab-macos/commit/a94eeb0))

# [7.4.0](https://github.com/lwouis/alt-tab-macos/compare/v7.3.0...v7.4.0) (2024-11-16)


### Bug Fixes

* permission callout could show even with permission granted ([9585c92](https://github.com/lwouis/alt-tab-macos/commit/9585c92)), closes [#3801](https://github.com/lwouis/alt-tab-macos/issues/3801)


### Features

* better switcher max-width at various monitor sizes ([49178b5](https://github.com/lwouis/alt-tab-macos/commit/49178b5))
* improve ar, de, el, hu, it, ko, pt localizations ([c4f98a1](https://github.com/lwouis/alt-tab-macos/commit/c4f98a1))

# [7.3.0](https://github.com/lwouis/alt-tab-macos/compare/v7.2.0...v7.3.0) (2024-11-10)


### Bug Fixes

* better handle screen or space changes (closes [#1254](https://github.com/lwouis/alt-tab-macos/issues/1254), closes [#2983](https://github.com/lwouis/alt-tab-macos/issues/2983)) ([3c4aaf5](https://github.com/lwouis/alt-tab-macos/commit/3c4aaf5))
* potential issues with key repeats due to concurrency ([4cfe16a](https://github.com/lwouis/alt-tab-macos/commit/4cfe16a))
* switcher would not close, or cycle on its own (closes [#3117](https://github.com/lwouis/alt-tab-macos/issues/3117)) ([d430f83](https://github.com/lwouis/alt-tab-macos/commit/d430f83))
* works without screen-recording permissions (closes [#3819](https://github.com/lwouis/alt-tab-macos/issues/3819)) ([f7de2bb](https://github.com/lwouis/alt-tab-macos/commit/f7de2bb))


### Features

* can pass the --logs= flags at launch to show logs ([81eb07e](https://github.com/lwouis/alt-tab-macos/commit/81eb07e))
* improve el, fi, hi, it, pl, pt localizations ([a9614c1](https://github.com/lwouis/alt-tab-macos/commit/a9614c1))

# [7.2.0](https://github.com/lwouis/alt-tab-macos/compare/v7.1.1...v7.2.0) (2024-11-04)


### Features

* hide space labels when showing same-space windows ([88c1595](https://github.com/lwouis/alt-tab-macos/commit/88c1595)), closes [#3766](https://github.com/lwouis/alt-tab-macos/issues/3766)
* improve switcher layout and presentation ([545b5db](https://github.com/lwouis/alt-tab-macos/commit/545b5db))

## [7.1.1](https://github.com/lwouis/alt-tab-macos/compare/v7.1.0...v7.1.1) (2024-11-03)


### Bug Fixes

* blacklist could prevent app launch in v7.1.0 ([8f4784f](https://github.com/lwouis/alt-tab-macos/commit/8f4784f))

# [7.1.0](https://github.com/lwouis/alt-tab-macos/compare/v7.0.2...v7.1.0) (2024-11-02)


### Bug Fixes

* fixed the rounded corners when the mouse moves over the table ([dd379c4](https://github.com/lwouis/alt-tab-macos/commit/dd379c4))


### Features

* add irish localization ([19f59b2](https://github.com/lwouis/alt-tab-macos/commit/19f59b2))
* add language preference ([f33418e](https://github.com/lwouis/alt-tab-macos/commit/f33418e))
* allow to run the app without screen-recording permissions ([129d061](https://github.com/lwouis/alt-tab-macos/commit/129d061)), closes [#1082](https://github.com/lwouis/alt-tab-macos/issues/1082)
* hide space labels when showing same-space windows (closes [#3766](https://github.com/lwouis/alt-tab-macos/issues/3766)) ([ad64ced](https://github.com/lwouis/alt-tab-macos/commit/ad64ced))
* i18n ([d77fa67](https://github.com/lwouis/alt-tab-macos/commit/d77fa67))
* improve appearance at the different sizes ([2c857a6](https://github.com/lwouis/alt-tab-macos/commit/2c857a6))
* improve display of wide/tall thumbnails (closes [#3791](https://github.com/lwouis/alt-tab-macos/issues/3791)) ([45bbc93](https://github.com/lwouis/alt-tab-macos/commit/45bbc93))
* improve localizations ([9d1349b](https://github.com/lwouis/alt-tab-macos/commit/9d1349b))

## [7.0.2](https://github.com/lwouis/alt-tab-macos/compare/v7.0.1...v7.0.2) (2024-10-12)


### Bug Fixes

* avoid crashing in some cases ([d46d903](https://github.com/lwouis/alt-tab-macos/commit/d46d903))
* block titles in preferences in rtl languages ([ea5574b](https://github.com/lwouis/alt-tab-macos/commit/ea5574b))
* preferences panel icons wouldnt show on old macos versions ([9258acf](https://github.com/lwouis/alt-tab-macos/commit/9258acf))
* show titles > application name, in thumbnails style (closes [#3667](https://github.com/lwouis/alt-tab-macos/issues/3667)) ([b4e97ea](https://github.com/lwouis/alt-tab-macos/commit/b4e97ea))

## [7.0.1](https://github.com/lwouis/alt-tab-macos/compare/v7.0.0...v7.0.1) (2024-10-11)


### Bug Fixes

* avoid crashing in rare cases ([9980ec6](https://github.com/lwouis/alt-tab-macos/commit/9980ec6))

# [7.0.0](https://github.com/lwouis/alt-tab-macos/compare/v6.73.0...v7.0.0) (2024-10-09)


### Features

* major rehaul of the preferences! ([6d97cbd](https://github.com/lwouis/alt-tab-macos/commit/6d97cbd)), closes [#351](https://github.com/lwouis/alt-tab-macos/issues/351)


### BREAKING CHANGES

* The old preferences panel has been replaced with a brand new one

Preferences are now much simpler, full of visual illustrations, and should provide a much better experience. Pick between 3 styles (thumbnails, app-icons, titles), sizes, dark/light themes, high visibility options, and more!

# [6.73.0](https://github.com/lwouis/alt-tab-macos/compare/v6.72.0...v6.73.0) (2024-10-08)


### Bug Fixes

* closing alttab windows gives focus to previous app (closes [#3577](https://github.com/lwouis/alt-tab-macos/issues/3577)) ([0e6f200](https://github.com/lwouis/alt-tab-macos/commit/0e6f200))
* detect passwords app (closes [#3545](https://github.com/lwouis/alt-tab-macos/issues/3545)) ([d0cd206](https://github.com/lwouis/alt-tab-macos/commit/d0cd206))
* dragging files onto windowless apps was inconsistent ([0a9fe9b](https://github.com/lwouis/alt-tab-macos/commit/0a9fe9b))
* finder would sometimes not be listed (closes [#3350](https://github.com/lwouis/alt-tab-macos/issues/3350)) ([eba5e42](https://github.com/lwouis/alt-tab-macos/commit/eba5e42))
* focusing an app could open another version of it ([9d5f11a](https://github.com/lwouis/alt-tab-macos/commit/9d5f11a))
* preview window could remain after focusing an app (closes [#3505](https://github.com/lwouis/alt-tab-macos/issues/3505)) ([e890a60](https://github.com/lwouis/alt-tab-macos/commit/e890a60))


### Features

* add kannada and malayalam and localizations ([5e27701](https://github.com/lwouis/alt-tab-macos/commit/5e27701))

# [6.72.0](https://github.com/lwouis/alt-tab-macos/compare/v6.71.0...v6.72.0) (2024-07-14)


### Bug Fixes

* preferences window quit button supports right-to-left languages ([d3dfd54](https://github.com/lwouis/alt-tab-macos/commit/d3dfd54)), closes [#3487](https://github.com/lwouis/alt-tab-macos/issues/3487)


### Features

* don't show caps-lock indicator as a window (closes [#3171](https://github.com/lwouis/alt-tab-macos/issues/3171)) ([2e15732](https://github.com/lwouis/alt-tab-macos/commit/2e15732))
* improve da/he localizations ([3d98b64](https://github.com/lwouis/alt-tab-macos/commit/3d98b64))

# [6.71.0](https://github.com/lwouis/alt-tab-macos/compare/v6.70.1...v6.71.0) (2024-07-06)


### Bug Fixes

* restore default cmd+tab shortcut when alt-tab crashes ([2c47b4e](https://github.com/lwouis/alt-tab-macos/commit/2c47b4e))
* showing permissions window would crash on macos < 10.15 ([bb5215c](https://github.com/lwouis/alt-tab-macos/commit/bb5215c)), closes [#3437](https://github.com/lwouis/alt-tab-macos/issues/3437)
* traffic light icons could appear half-transparent (closes [#2892](https://github.com/lwouis/alt-tab-macos/issues/2892)) ([1eef1e0](https://github.com/lwouis/alt-tab-macos/commit/1eef1e0))


### Features

* improve fr/he/it/ja/pt/sv localizations ([35521a5](https://github.com/lwouis/alt-tab-macos/commit/35521a5))
* show de-fullscreen button on fullscreen windows ([ad1e8d0](https://github.com/lwouis/alt-tab-macos/commit/ad1e8d0))

## [6.70.1](https://github.com/lwouis/alt-tab-macos/compare/v6.70.0...v6.70.1) (2024-06-01)


### Bug Fixes

* prevent crash introduced in v6.70.0 (closes [#3392](https://github.com/lwouis/alt-tab-macos/issues/3392)) ([e16a3d4](https://github.com/lwouis/alt-tab-macos/commit/e16a3d4))

# [6.70.0](https://github.com/lwouis/alt-tab-macos/compare/v6.69.0...v6.70.0) (2024-05-29)


### Bug Fixes

* detect safari fullscreen windows better (closes [#3384](https://github.com/lwouis/alt-tab-macos/issues/3384)) ([c3006c6](https://github.com/lwouis/alt-tab-macos/commit/c3006c6))


### Features

* add utm-app to default blacklist ([523bcbb](https://github.com/lwouis/alt-tab-macos/commit/523bcbb))

# [6.69.0](https://github.com/lwouis/alt-tab-macos/compare/v6.68.0...v6.69.0) (2024-05-12)


### Bug Fixes

* only show standard windows of preview.app (closes [#3351](https://github.com/lwouis/alt-tab-macos/issues/3351)) ([6231977](https://github.com/lwouis/alt-tab-macos/commit/6231977))


### Features

* update fi, ja, ko, pt-br, th localizations ([14d287a](https://github.com/lwouis/alt-tab-macos/commit/14d287a))

# [6.68.0](https://github.com/lwouis/alt-tab-macos/compare/v6.67.0...v6.68.0) (2024-04-03)


### Bug Fixes

* preview.app window may not show when opening many docs ([31b5a3d](https://github.com/lwouis/alt-tab-macos/commit/31b5a3d)), closes [#3276](https://github.com/lwouis/alt-tab-macos/issues/3276)
* preview.app windows would sometimes not show (closes [#3275](https://github.com/lwouis/alt-tab-macos/issues/3275)) ([785cf9c](https://github.com/lwouis/alt-tab-macos/commit/785cf9c))


### Features

* improve ar/nb/nn/pl/tr/uk localizations ([67a6d81](https://github.com/lwouis/alt-tab-macos/commit/67a6d81))
* new thai and norwegian localizations (closes [#3260](https://github.com/lwouis/alt-tab-macos/issues/3260)) ([d9aa319](https://github.com/lwouis/alt-tab-macos/commit/d9aa319))

# [6.67.0](https://github.com/lwouis/alt-tab-macos/compare/v6.66.0...v6.67.0) (2024-03-15)


### Features

* add icelandic localization ([7df1432](https://github.com/lwouis/alt-tab-macos/commit/7df1432))
* improve ru/cn localizations ([c9fe54e](https://github.com/lwouis/alt-tab-macos/commit/c9fe54e))
* support autocad non-native windows ([#3219](https://github.com/lwouis/alt-tab-macos/issues/3219)) ([bbaef6c](https://github.com/lwouis/alt-tab-macos/commit/bbaef6c))

# [6.66.0](https://github.com/lwouis/alt-tab-macos/compare/v6.65.0...v6.66.0) (2024-03-03)


### Bug Fixes

* alttab would crash after menubar icon was actioned with voiceover ([f7fdf3f](https://github.com/lwouis/alt-tab-macos/commit/f7fdf3f)), closes [#3211](https://github.com/lwouis/alt-tab-macos/issues/3211)


### Features

* improved ca/de/es/ko/nl/sv/vi/zh localizations ([f4ad2ea](https://github.com/lwouis/alt-tab-macos/commit/f4ad2ea))

# [6.65.0](https://github.com/lwouis/alt-tab-macos/compare/v6.64.0...v6.65.0) (2024-01-29)


### Features

* update da/de/es/sv localizations ([c88426e](https://github.com/lwouis/alt-tab-macos/commit/c88426e))
* users can check status of required system permissions ([70ee681](https://github.com/lwouis/alt-tab-macos/commit/70ee681))

# [6.64.0](https://github.com/lwouis/alt-tab-macos/compare/v6.63.0...v6.64.0) (2023-10-24)


### Bug Fixes

* don't absorb key up events after summon (closes [#2914](https://github.com/lwouis/alt-tab-macos/issues/2914)) ([3b0194d](https://github.com/lwouis/alt-tab-macos/commit/3b0194d))
* stop vim keys preference disabling on launch (closes [#2919](https://github.com/lwouis/alt-tab-macos/issues/2919)) ([53692ff](https://github.com/lwouis/alt-tab-macos/commit/53692ff))


### Features

* improve fr,de localizations ([c4ae549](https://github.com/lwouis/alt-tab-macos/commit/c4ae549))

# [6.63.0](https://github.com/lwouis/alt-tab-macos/compare/v6.62.0...v6.63.0) (2023-10-20)


### Bug Fixes

* never screenshot windows if thumbnails are hidden ([5e7f44b](https://github.com/lwouis/alt-tab-macos/commit/5e7f44b))


### Features

* improve ca/ko/ku localizations ([865570f](https://github.com/lwouis/alt-tab-macos/commit/865570f))

# [6.62.0](https://github.com/lwouis/alt-tab-macos/compare/v6.61.0...v6.62.0) (2023-10-10)


### Bug Fixes

* better crossover windows detection ([3f64463](https://github.com/lwouis/alt-tab-macos/commit/3f64463))


### Features

* add tamil and croatian localizations ([e542da8](https://github.com/lwouis/alt-tab-macos/commit/e542da8))
* add vim key window navigation (closes [#1229](https://github.com/lwouis/alt-tab-macos/issues/1229)) ([5cf7f99](https://github.com/lwouis/alt-tab-macos/commit/5cf7f99))
* improve bg,es,he,hi,ko,uk,cn localizations ([31fb795](https://github.com/lwouis/alt-tab-macos/commit/31fb795))

# [6.61.0](https://github.com/lwouis/alt-tab-macos/compare/v6.60.0...v6.61.0) (2023-07-12)


### Bug Fixes

* better identify tabs on macos versions older than 13 ([3147a69](https://github.com/lwouis/alt-tab-macos/commit/3147a69)), closes [#2017](https://github.com/lwouis/alt-tab-macos/issues/2017)
* don't show empty color-slurp windows ([01b3a42](https://github.com/lwouis/alt-tab-macos/commit/01b3a42))


### Features

* improve german localization ([1084d87](https://github.com/lwouis/alt-tab-macos/commit/1084d87))
* improve support for crossover windows ([f9f1c19](https://github.com/lwouis/alt-tab-macos/commit/f9f1c19))
* improve support for scrcpy always-on-top windows ([0673381](https://github.com/lwouis/alt-tab-macos/commit/0673381))
* show the ui by right-clicking the menubar icon (closes [#2647](https://github.com/lwouis/alt-tab-macos/issues/2647)) ([63502d5](https://github.com/lwouis/alt-tab-macos/commit/63502d5))

# [6.60.0](https://github.com/lwouis/alt-tab-macos/compare/v6.59.0...v6.60.0) (2023-06-23)


### Bug Fixes

* prevent flickering when switching to a previewed window ([b69f5f4](https://github.com/lwouis/alt-tab-macos/commit/b69f5f4)), closes [#2432](https://github.com/lwouis/alt-tab-macos/issues/2432)


### Features

* improve support for color-slurp windows ([8605b23](https://github.com/lwouis/alt-tab-macos/commit/8605b23))
* user can change window order in preferences (closes [#515](https://github.com/lwouis/alt-tab-macos/issues/515)) ([a67d123](https://github.com/lwouis/alt-tab-macos/commit/a67d123))

# [6.59.0](https://github.com/lwouis/alt-tab-macos/compare/v6.58.0...v6.59.0) (2023-06-04)


### Features

* show app icon for app with no open window (closes [#2561](https://github.com/lwouis/alt-tab-macos/issues/2561)) ([44a5630](https://github.com/lwouis/alt-tab-macos/commit/44a5630))
* update vietnamese localization ([7229b8a](https://github.com/lwouis/alt-tab-macos/commit/7229b8a))

# [6.58.0](https://github.com/lwouis/alt-tab-macos/compare/v6.57.0...v6.58.0) (2023-05-15)


### Bug Fixes

* editing the blacklist could sometimes bug (closes [#2528](https://github.com/lwouis/alt-tab-macos/issues/2528)) ([f7f4430](https://github.com/lwouis/alt-tab-macos/commit/f7f4430))


### Features

* update dutch localization ([04948a2](https://github.com/lwouis/alt-tab-macos/commit/04948a2))

# [6.57.0](https://github.com/lwouis/alt-tab-macos/compare/v6.56.0...v6.57.0) (2023-05-09)


### Bug Fixes

* drag-and-drop from a folder on the dock (closes [#706](https://github.com/lwouis/alt-tab-macos/issues/706)) ([ee6785f](https://github.com/lwouis/alt-tab-macos/commit/ee6785f))
* preview window wouldn't update in some cases ([537ba26](https://github.com/lwouis/alt-tab-macos/commit/537ba26))


### Features

* add shortcut to toggle fullscreen selected window (closes [#2521](https://github.com/lwouis/alt-tab-macos/issues/2521)) ([7327917](https://github.com/lwouis/alt-tab-macos/commit/7327917))
* add uzbek localization ([0e106e2](https://github.com/lwouis/alt-tab-macos/commit/0e106e2))

# [6.56.0](https://github.com/lwouis/alt-tab-macos/compare/v6.55.0...v6.56.0) (2023-03-16)


### Bug Fixes

* correctly show when an app is no longer assigned to all desktops ([10bbaa9](https://github.com/lwouis/alt-tab-macos/commit/10bbaa9)), closes [#2372](https://github.com/lwouis/alt-tab-macos/issues/2372)


### Features

* add option to preview selected window (closes [#967](https://github.com/lwouis/alt-tab-macos/issues/967)) ([6534a2d](https://github.com/lwouis/alt-tab-macos/commit/6534a2d))

# [6.55.0](https://github.com/lwouis/alt-tab-macos/compare/v6.54.0...v6.55.0) (2023-02-23)


### Bug Fixes

* use plain number formatter for initial slider label ([7cab722](https://github.com/lwouis/alt-tab-macos/commit/7cab722))


### Features

* allow batch removal from the blacklist ([f53c070](https://github.com/lwouis/alt-tab-macos/commit/f53c070))
* allow to switch shortcuts while the ui is already open ([b99c988](https://github.com/lwouis/alt-tab-macos/commit/b99c988))
* improved german localization ([5d27a19](https://github.com/lwouis/alt-tab-macos/commit/5d27a19))
* show dock badges when they don't show a number (closes [#2356](https://github.com/lwouis/alt-tab-macos/issues/2356)) ([84752e0](https://github.com/lwouis/alt-tab-macos/commit/84752e0))

# [6.54.0](https://github.com/lwouis/alt-tab-macos/compare/v6.53.1...v6.54.0) (2023-02-20)


### Features

* improve selection background/border color contrast ([cea0cff](https://github.com/lwouis/alt-tab-macos/commit/cea0cff)), closes [#2352](https://github.com/lwouis/alt-tab-macos/issues/2352)

## [6.53.1](https://github.com/lwouis/alt-tab-macos/compare/v6.53.0...v6.53.1) (2023-02-12)


### Bug Fixes

* bring back mouse hover selection (closes [#2317](https://github.com/lwouis/alt-tab-macos/issues/2317)) ([abe2e0b](https://github.com/lwouis/alt-tab-macos/commit/abe2e0b))

# [6.53.0](https://github.com/lwouis/alt-tab-macos/compare/v6.52.1...v6.53.0) (2023-02-09)


### Bug Fixes

* don't focus window when dropping a file on it ([c386a0c](https://github.com/lwouis/alt-tab-macos/commit/c386a0c))


### Features

* allow status item removal by dragging ([216c5d8](https://github.com/lwouis/alt-tab-macos/commit/216c5d8))
* improve localizations ([7a30b18](https://github.com/lwouis/alt-tab-macos/commit/7a30b18))
* separate mouse hover from keyboard selection ([3fb9a19](https://github.com/lwouis/alt-tab-macos/commit/3fb9a19)), closes [#2078](https://github.com/lwouis/alt-tab-macos/issues/2078) [#1617](https://github.com/lwouis/alt-tab-macos/issues/1617)

## [6.52.1](https://github.com/lwouis/alt-tab-macos/compare/v6.52.0...v6.52.1) (2022-12-28)

# [6.52.0](https://github.com/lwouis/alt-tab-macos/compare/v6.51.0...v6.52.0) (2022-12-28)


### Bug Fixes

* scale app red badge with app icon size (closes [#559](https://github.com/lwouis/alt-tab-macos/issues/559)) ([4b2f134](https://github.com/lwouis/alt-tab-macos/commit/4b2f134))
* some tooltips would remain on screen (closes [#2190](https://github.com/lwouis/alt-tab-macos/issues/2190)) ([6526caa](https://github.com/lwouis/alt-tab-macos/commit/6526caa))


### Features

* add kurdish localization and improve russian/romanian ([8217ad8](https://github.com/lwouis/alt-tab-macos/commit/8217ad8))
* help support broken fl studio app (closes [#2174](https://github.com/lwouis/alt-tab-macos/issues/2174)) ([4f26bc2](https://github.com/lwouis/alt-tab-macos/commit/4f26bc2))

# [6.51.0](https://github.com/lwouis/alt-tab-macos/compare/v6.50.0...v6.51.0) (2022-11-16)


### Bug Fixes

* fullscreening windows stopped working (closes [#2129](https://github.com/lwouis/alt-tab-macos/issues/2129)) ([a09dbbf](https://github.com/lwouis/alt-tab-macos/commit/a09dbbf))
* windows assigned to all spaces were not shown (closes [#2123](https://github.com/lwouis/alt-tab-macos/issues/2123)) ([82cfb62](https://github.com/lwouis/alt-tab-macos/commit/82cfb62))


### Features

* improve localizations ([d2d5016](https://github.com/lwouis/alt-tab-macos/commit/d2d5016))

# [6.50.0](https://github.com/lwouis/alt-tab-macos/compare/v6.49.0...v6.50.0) (2022-11-14)


### Bug Fixes

* don't show firefox tooltips as windows (closes [#2110](https://github.com/lwouis/alt-tab-macos/issues/2110)) ([bf905b1](https://github.com/lwouis/alt-tab-macos/commit/bf905b1))
* tabs show as separate windows sometimes on monterey (closes [#2017](https://github.com/lwouis/alt-tab-macos/issues/2017)) ([0965a78](https://github.com/lwouis/alt-tab-macos/commit/0965a78))


### Features

* avoid accidental press of the "reset preferences" button ([#2093](https://github.com/lwouis/alt-tab-macos/issues/2093)) ([f6fcac5](https://github.com/lwouis/alt-tab-macos/commit/f6fcac5))
* avoid confusion with native app-switcher (closes [#2080](https://github.com/lwouis/alt-tab-macos/issues/2080)) ([f906c0e](https://github.com/lwouis/alt-tab-macos/commit/f906c0e))
* improve localizations ([2123af3](https://github.com/lwouis/alt-tab-macos/commit/2123af3))
* show alttab on display with active menubar when needed ([#2107](https://github.com/lwouis/alt-tab-macos/issues/2107)) ([917e661](https://github.com/lwouis/alt-tab-macos/commit/917e661))

# [6.49.0](https://github.com/lwouis/alt-tab-macos/compare/v6.48.0...v6.49.0) (2022-11-02)


### Bug Fixes

* command+backtick not working if stage manager is on (closes [#2053](https://github.com/lwouis/alt-tab-macos/issues/2053)) ([848ae5f](https://github.com/lwouis/alt-tab-macos/commit/848ae5f))
* crash when setting some shortcut combinations (closes [#2061](https://github.com/lwouis/alt-tab-macos/issues/2061)) ([8b2d659](https://github.com/lwouis/alt-tab-macos/commit/8b2d659))
* hide minimize and fullscreen thumbnail buttons for tabs ([b62c422](https://github.com/lwouis/alt-tab-macos/commit/b62c422))
* improve key repeat-rate when held (closes [#2026](https://github.com/lwouis/alt-tab-macos/issues/2026)) ([1821dea](https://github.com/lwouis/alt-tab-macos/commit/1821dea))
* key-above-tab on international keyboards (closes [#1190](https://github.com/lwouis/alt-tab-macos/issues/1190)) ([4c31740](https://github.com/lwouis/alt-tab-macos/commit/4c31740))
* thumbnails would sometimes be the wrong size ([1065c0d](https://github.com/lwouis/alt-tab-macos/commit/1065c0d))
* wrong focus after active app becomes windowless (closes [#2065](https://github.com/lwouis/alt-tab-macos/issues/2065)) ([281b3ed](https://github.com/lwouis/alt-tab-macos/commit/281b3ed))


### Features

* improve some localizations ([292e6b0](https://github.com/lwouis/alt-tab-macos/commit/292e6b0))
* play alert sound for unavailable thumbnail shortcuts ([fd84a9a](https://github.com/lwouis/alt-tab-macos/commit/fd84a9a))
* support adobe after effects non-standard windows (closes [#1982](https://github.com/lwouis/alt-tab-macos/issues/1982)) ([7b54873](https://github.com/lwouis/alt-tab-macos/commit/7b54873))

# [6.48.0](https://github.com/lwouis/alt-tab-macos/compare/v6.47.0...v6.48.0) (2022-10-27)


### Bug Fixes

* app name in system settings in macos 13 (closes [#2044](https://github.com/lwouis/alt-tab-macos/issues/2044)) ([02451e8](https://github.com/lwouis/alt-tab-macos/commit/02451e8))


### Features

* add 3 more shortcut tabs in the preferences (closes [#1064](https://github.com/lwouis/alt-tab-macos/issues/1064)) ([31bd0a6](https://github.com/lwouis/alt-tab-macos/commit/31bd0a6))

# [6.47.0](https://github.com/lwouis/alt-tab-macos/compare/v6.46.1...v6.47.0) (2022-10-14)


### Bug Fixes

* alt-tab would show on the wrong screen (closes [#2003](https://github.com/lwouis/alt-tab-macos/issues/2003)) ([b72c4db](https://github.com/lwouis/alt-tab-macos/commit/b72c4db))
* discover windows when switching spaces ([#1324](https://github.com/lwouis/alt-tab-macos/issues/1324)) ([9c26d54](https://github.com/lwouis/alt-tab-macos/commit/9c26d54))
* shortcut tabs right margin ([d207f86](https://github.com/lwouis/alt-tab-macos/commit/d207f86))
* show finder file copy windows (closes [#1466](https://github.com/lwouis/alt-tab-macos/issues/1466)) ([c78481b](https://github.com/lwouis/alt-tab-macos/commit/c78481b))
* wrap thumbnail buttons when needed ([ea05c03](https://github.com/lwouis/alt-tab-macos/commit/ea05c03))


### Features

* improve many localizations and add romanian ([71f1609](https://github.com/lwouis/alt-tab-macos/commit/71f1609))

## [6.46.1](https://github.com/lwouis/alt-tab-macos/compare/v6.46.0...v6.46.1) (2022-06-24)


### Bug Fixes

* mouse-hover controls remained after closing a window (closes [#1730](https://github.com/lwouis/alt-tab-macos/issues/1730)) ([6bd303d](https://github.com/lwouis/alt-tab-macos/commit/6bd303d))

# [6.46.0](https://github.com/lwouis/alt-tab-macos/compare/v6.45.0...v6.46.0) (2022-06-23)


### Features

* add quit-app icon on mouse hover (closes [#1260](https://github.com/lwouis/alt-tab-macos/issues/1260)) ([5c3b503](https://github.com/lwouis/alt-tab-macos/commit/5c3b503))
* improved turkish localization ([bb4a2b9](https://github.com/lwouis/alt-tab-macos/commit/bb4a2b9))

# [6.45.0](https://github.com/lwouis/alt-tab-macos/compare/v6.44.0...v6.45.0) (2022-06-21)


### Bug Fixes

* better guess at focus order on launch (closes [#1694](https://github.com/lwouis/alt-tab-macos/issues/1694)) ([be8631e](https://github.com/lwouis/alt-tab-macos/commit/be8631e))
* may avoid rare crashes ([e32beea](https://github.com/lwouis/alt-tab-macos/commit/e32beea))


### Features

* add bengali localization ([2d32823](https://github.com/lwouis/alt-tab-macos/commit/2d32823))
* improve chinese and german localizations ([69bfb41](https://github.com/lwouis/alt-tab-macos/commit/69bfb41))
* improve tooltips on mouse hover (closes [#1661](https://github.com/lwouis/alt-tab-macos/issues/1661)) ([38262f1](https://github.com/lwouis/alt-tab-macos/commit/38262f1))
* quitting an app twice force-quits it (closes [#1529](https://github.com/lwouis/alt-tab-macos/issues/1529)) ([bfcbaac](https://github.com/lwouis/alt-tab-macos/commit/bfcbaac))

# [6.44.0](https://github.com/lwouis/alt-tab-macos/compare/v6.43.0...v6.44.0) (2022-06-19)


### Bug Fixes

* blacklist table colors were wrong in dark mode ([#1702](https://github.com/lwouis/alt-tab-macos/issues/1702)) ([95cc29f](https://github.com/lwouis/alt-tab-macos/commit/95cc29f))
* don't show space icon for apps ([#1700](https://github.com/lwouis/alt-tab-macos/issues/1700)) ([f7d070b](https://github.com/lwouis/alt-tab-macos/commit/f7d070b))
* round corners would be aliased after changing theme ([#1698](https://github.com/lwouis/alt-tab-macos/issues/1698)) ([9ae76a9](https://github.com/lwouis/alt-tab-macos/commit/9ae76a9))


### Features

* update german and turkish localizations ([b91696b](https://github.com/lwouis/alt-tab-macos/commit/b91696b))

# [6.43.0](https://github.com/lwouis/alt-tab-macos/compare/v6.42.0...v6.43.0) (2022-06-14)


### Features

* improve blacklist ux (closes [#539](https://github.com/lwouis/alt-tab-macos/issues/539)) ([892a168](https://github.com/lwouis/alt-tab-macos/commit/892a168))
* improve german and chinese (tw) localizations ([5133641](https://github.com/lwouis/alt-tab-macos/commit/5133641))

# [6.42.0](https://github.com/lwouis/alt-tab-macos/compare/v6.41.1...v6.42.0) (2022-06-07)


### Bug Fixes

* some windows would not show ([#1655](https://github.com/lwouis/alt-tab-macos/issues/1655)) ([6a6c80d](https://github.com/lwouis/alt-tab-macos/commit/6a6c80d))


### Features

* show tooltips on mouse hover on main window ([#1661](https://github.com/lwouis/alt-tab-macos/issues/1661)) ([bb5cc23](https://github.com/lwouis/alt-tab-macos/commit/bb5cc23))

## [6.41.1](https://github.com/lwouis/alt-tab-macos/compare/v6.41.0...v6.41.1) (2022-06-05)


### Bug Fixes

* tab detection got broken in v6.41.0 ([#1656](https://github.com/lwouis/alt-tab-macos/issues/1656)) ([95f97d3](https://github.com/lwouis/alt-tab-macos/commit/95f97d3))

# [6.41.0](https://github.com/lwouis/alt-tab-macos/compare/v6.40.0...v6.41.0) (2022-06-01)


### Bug Fixes

* fade-out animation was broken from macos 11 ([#760](https://github.com/lwouis/alt-tab-macos/issues/760)) ([d701bc7](https://github.com/lwouis/alt-tab-macos/commit/d701bc7))
* menubar icons in preferences handle dark mode ([1653c16](https://github.com/lwouis/alt-tab-macos/commit/1653c16))


### Features

* add a button to reset the preferences ([#1275](https://github.com/lwouis/alt-tab-macos/issues/1275)) ([82e9ca9](https://github.com/lwouis/alt-tab-macos/commit/82e9ca9))
* add galician localization ([965b179](https://github.com/lwouis/alt-tab-macos/commit/965b179))
* improve windows detection ([de0497a](https://github.com/lwouis/alt-tab-macos/commit/de0497a))
* smoother rounded corners for the main window ([5d0fff2](https://github.com/lwouis/alt-tab-macos/commit/5d0fff2))
* update czech localization ([d7b6b7c](https://github.com/lwouis/alt-tab-macos/commit/d7b6b7c))

# [6.40.0](https://github.com/lwouis/alt-tab-macos/compare/v6.39.1...v6.40.0) (2022-05-27)


### Bug Fixes

* focusing alt-tab own windows could fail ([#759](https://github.com/lwouis/alt-tab-macos/issues/759)) ([08720d8](https://github.com/lwouis/alt-tab-macos/commit/08720d8))


### Features

* update spanish localization ([1ac0494](https://github.com/lwouis/alt-tab-macos/commit/1ac0494))

## [6.39.1](https://github.com/lwouis/alt-tab-macos/compare/v6.39.0...v6.39.1) (2022-05-26)


### Bug Fixes

* better tabs detection + fix issues with some apps (closes [#1540](https://github.com/lwouis/alt-tab-macos/issues/1540)) ([abd54b3](https://github.com/lwouis/alt-tab-macos/commit/abd54b3)), closes [#647](https://github.com/lwouis/alt-tab-macos/issues/647) [#718](https://github.com/lwouis/alt-tab-macos/issues/718)

# [6.39.0](https://github.com/lwouis/alt-tab-macos/compare/v6.38.0...v6.39.0) (2022-05-26)


### Bug Fixes

* handle being quit through activity-monitor (closes [#1622](https://github.com/lwouis/alt-tab-macos/issues/1622)) ([69a5ffd](https://github.com/lwouis/alt-tab-macos/commit/69a5ffd))


### Features

* middle-click a thumbnail to close that window (closes [#1621](https://github.com/lwouis/alt-tab-macos/issues/1621)) ([bc4c0cc](https://github.com/lwouis/alt-tab-macos/commit/bc4c0cc))
* update contributors ([b1bf867](https://github.com/lwouis/alt-tab-macos/commit/b1bf867))

# [6.38.0](https://github.com/lwouis/alt-tab-macos/compare/v6.37.1...v6.38.0) (2022-05-24)


### Bug Fixes

* better mouse hover behavior ([#1557](https://github.com/lwouis/alt-tab-macos/issues/1557)) ([d3cabc1](https://github.com/lwouis/alt-tab-macos/commit/d3cabc1))


### Features

* improve ukrainian, polish, albanian localization ([b02972b](https://github.com/lwouis/alt-tab-macos/commit/b02972b))

## [6.37.1](https://github.com/lwouis/alt-tab-macos/compare/v6.37.0...v6.37.1) (2022-05-12)


### Bug Fixes

* hovering thumbnails would make alttab laggy ([#1567](https://github.com/lwouis/alt-tab-macos/issues/1567)) ([7e66009](https://github.com/lwouis/alt-tab-macos/commit/7e66009))

# [6.37.0](https://github.com/lwouis/alt-tab-macos/compare/v6.36.2...v6.37.0) (2022-05-12)


### Bug Fixes

* prevent matlab freezing ([#890](https://github.com/lwouis/alt-tab-macos/issues/890)) ([0792838](https://github.com/lwouis/alt-tab-macos/commit/0792838))


### Features

* add albanian localization ([c22b364](https://github.com/lwouis/alt-tab-macos/commit/c22b364))
* improve chinese/taiwanese localizations ([f1c0244](https://github.com/lwouis/alt-tab-macos/commit/f1c0244))

## [6.36.2](https://github.com/lwouis/alt-tab-macos/compare/v6.36.1...v6.36.2) (2022-05-11)


### Bug Fixes

* hide window controls when another window is selected (closes [#1557](https://github.com/lwouis/alt-tab-macos/issues/1557)) ([2e9cc3b](https://github.com/lwouis/alt-tab-macos/commit/2e9cc3b))

## [6.36.1](https://github.com/lwouis/alt-tab-macos/compare/v6.36.0...v6.36.1) (2022-05-07)


### Bug Fixes

* better anti-aliasing on traffic-light icons ([022806b](https://github.com/lwouis/alt-tab-macos/commit/022806b))
* libre-office would freeze with 2 open windows (closes [#1508](https://github.com/lwouis/alt-tab-macos/issues/1508)) ([1bb9fd0](https://github.com/lwouis/alt-tab-macos/commit/1bb9fd0))
* switcher could select the wrong thumbnail (closes [#1198](https://github.com/lwouis/alt-tab-macos/issues/1198)) ([4c67778](https://github.com/lwouis/alt-tab-macos/commit/4c67778))

# [6.36.0](https://github.com/lwouis/alt-tab-macos/compare/v6.35.0...v6.36.0) (2022-05-06)


### Features

* improve traffic-light icons (closes [#1542](https://github.com/lwouis/alt-tab-macos/issues/1542)) ([6974de0](https://github.com/lwouis/alt-tab-macos/commit/6974de0))

# [6.35.0](https://github.com/lwouis/alt-tab-macos/compare/v6.34.1...v6.35.0) (2022-05-05)


### Bug Fixes

* sometimes moved cursor on focus wrong (closes [#1087](https://github.com/lwouis/alt-tab-macos/issues/1087)) ([ed10201](https://github.com/lwouis/alt-tab-macos/commit/ed10201))


### Features

* update turkish localization ([9129ff6](https://github.com/lwouis/alt-tab-macos/commit/9129ff6))

## [6.34.1](https://github.com/lwouis/alt-tab-macos/compare/v6.34.0...v6.34.1) (2022-04-30)


### Bug Fixes

* custom shortcuts can use arrow keys (closes [#1376](https://github.com/lwouis/alt-tab-macos/issues/1376)) ([bb1de75](https://github.com/lwouis/alt-tab-macos/commit/bb1de75))

# [6.34.0](https://github.com/lwouis/alt-tab-macos/compare/v6.33.0...v6.34.0) (2022-04-28)


### Bug Fixes

* alt-tab could be relaunched in a loop (closes [#1367](https://github.com/lwouis/alt-tab-macos/issues/1367)) ([cdb461a](https://github.com/lwouis/alt-tab-macos/commit/cdb461a))
* reduce alt-tab cpu usage in some scenarios (closes [#1481](https://github.com/lwouis/alt-tab-macos/issues/1481)) ([0569ed0](https://github.com/lwouis/alt-tab-macos/commit/0569ed0))


### Features

* update indian and russian localizations ([85210e2](https://github.com/lwouis/alt-tab-macos/commit/85210e2))

# [6.33.0](https://github.com/lwouis/alt-tab-macos/compare/v6.32.0...v6.33.0) (2022-04-08)


### Features

* allow quitting finder for power users (closes [#1328](https://github.com/lwouis/alt-tab-macos/issues/1328)) ([9e46bd8](https://github.com/lwouis/alt-tab-macos/commit/9e46bd8))

# [6.32.0](https://github.com/lwouis/alt-tab-macos/compare/v6.31.0...v6.32.0) (2022-04-07)


### Bug Fixes

* issue with some apps launched before alt-tab ([f97cd74](https://github.com/lwouis/alt-tab-macos/commit/f97cd74))
* show window of some apps like jetbrains apps ([#1249](https://github.com/lwouis/alt-tab-macos/issues/1249) [#1079](https://github.com/lwouis/alt-tab-macos/issues/1079) [#1392](https://github.com/lwouis/alt-tab-macos/issues/1392)) ([0b85b09](https://github.com/lwouis/alt-tab-macos/commit/0b85b09))
* show windows of some defective apps like bear.app ([9b5cd42](https://github.com/lwouis/alt-tab-macos/commit/9b5cd42))


### Features

* add greek and estonian, and update other localizations ([fccae77](https://github.com/lwouis/alt-tab-macos/commit/fccae77))

# [6.31.0](https://github.com/lwouis/alt-tab-macos/compare/v6.30.0...v6.31.0) (2022-02-10)


### Features

* add hebrew localization ([26b72e3](https://github.com/lwouis/alt-tab-macos/commit/26b72e3))

# [6.30.0](https://github.com/lwouis/alt-tab-macos/compare/v6.29.0...v6.30.0) (2022-02-05)


### Features

* add localization in danish, catalan, persian, serbian ([058a0f8](https://github.com/lwouis/alt-tab-macos/commit/058a0f8))
* allow cursor follow focus behavior ([be50758](https://github.com/lwouis/alt-tab-macos/commit/be50758))
* update some localizations ([17fbcc5](https://github.com/lwouis/alt-tab-macos/commit/17fbcc5))

# [6.29.0](https://github.com/lwouis/alt-tab-macos/compare/v6.28.0...v6.29.0) (2021-12-01)


### Bug Fixes

* only make network calls to appcenter when necessary (closes [#1265](https://github.com/lwouis/alt-tab-macos/issues/1265)) ([79c2906](https://github.com/lwouis/alt-tab-macos/commit/79c2906))
* prevent setting min width to 0% in preferences (see [#1248](https://github.com/lwouis/alt-tab-macos/issues/1248)) ([467736c](https://github.com/lwouis/alt-tab-macos/commit/467736c))


### Features

* add apple screen sharing to default blacklist ([#1258](https://github.com/lwouis/alt-tab-macos/issues/1258)) ([d4780f6](https://github.com/lwouis/alt-tab-macos/commit/d4780f6))
* add vmware fusion to default blacklist (closes [#1258](https://github.com/lwouis/alt-tab-macos/issues/1258)) ([17f98b5](https://github.com/lwouis/alt-tab-macos/commit/17f98b5))

# [6.28.0](https://github.com/lwouis/alt-tab-macos/compare/v6.27.1...v6.28.0) (2021-11-19)


### Bug Fixes

* would sometimes crash when opening preferences > appearance ([c66e106](https://github.com/lwouis/alt-tab-macos/commit/c66e106))


### Features

* native support for apple silicon (e.g. m1 mac) ([6f93130](https://github.com/lwouis/alt-tab-macos/commit/6f93130))
* support login-at-start on macos 11, 12, and m1 macs ([664c5b9](https://github.com/lwouis/alt-tab-macos/commit/664c5b9))

## [6.27.1](https://github.com/lwouis/alt-tab-macos/compare/v6.27.0...v6.27.1) (2021-11-13)


### Bug Fixes

* ghost windows in android studio (#closes 1224) ([b668928](https://github.com/lwouis/alt-tab-macos/commit/b668928))

# [6.27.0](https://github.com/lwouis/alt-tab-macos/compare/v6.26.0...v6.27.0) (2021-11-12)


### Bug Fixes

* display all windows from android studio ([e2d26f2](https://github.com/lwouis/alt-tab-macos/commit/e2d26f2))
* parallels windows wouldn't switch sometimes (closes [#1213](https://github.com/lwouis/alt-tab-macos/issues/1213)) ([21133ce](https://github.com/lwouis/alt-tab-macos/commit/21133ce))
* the app would sometimes freeze or lag (closes [#563](https://github.com/lwouis/alt-tab-macos/issues/563)) ([4a264ab](https://github.com/lwouis/alt-tab-macos/commit/4a264ab))


### Features

* improved spanish localization ([3709b62](https://github.com/lwouis/alt-tab-macos/commit/3709b62))

# [6.26.0](https://github.com/lwouis/alt-tab-macos/compare/v6.25.0...v6.26.0) (2021-10-13)


### Bug Fixes

* feedback form messages got broken by github ([1539727](https://github.com/lwouis/alt-tab-macos/commit/1539727))


### Features

* add bulgarian and improve arabic localizations ([f1be3cf](https://github.com/lwouis/alt-tab-macos/commit/f1be3cf))

# [6.25.0](https://github.com/lwouis/alt-tab-macos/compare/v6.24.0...v6.25.0) (2021-09-18)


### Bug Fixes

* "show on active screen" could show the wrong screen (closes [#1129](https://github.com/lwouis/alt-tab-macos/issues/1129)) ([23bbd64](https://github.com/lwouis/alt-tab-macos/commit/23bbd64))
* windows from the iina app would not show sometimes (closes [#1037](https://github.com/lwouis/alt-tab-macos/issues/1037)) ([47d283e](https://github.com/lwouis/alt-tab-macos/commit/47d283e))


### Features

* improve localization in hindi, arabic, vietnamese ([2905f7d](https://github.com/lwouis/alt-tab-macos/commit/2905f7d))
* improve voiceover and speech accessibility ([194e726](https://github.com/lwouis/alt-tab-macos/commit/194e726))

# [6.24.0](https://github.com/lwouis/alt-tab-macos/compare/v6.23.0...v6.24.0) (2021-09-04)


### Bug Fixes

* main window would sometimes appear after a delay (closes [#1096](https://github.com/lwouis/alt-tab-macos/issues/1096)) ([8ab0e61](https://github.com/lwouis/alt-tab-macos/commit/8ab0e61))


### Features

* update dutch localization ([91821f7](https://github.com/lwouis/alt-tab-macos/commit/91821f7))
* update italian and turkish localizations ([5cd7b44](https://github.com/lwouis/alt-tab-macos/commit/5cd7b44))

# [6.23.0](https://github.com/lwouis/alt-tab-macos/compare/v6.22.1...v6.23.0) (2021-08-30)


### Bug Fixes

* fix situations from some crash reports ([c18aa4d](https://github.com/lwouis/alt-tab-macos/commit/c18aa4d))
* ghost popup windows in android studio (closes [#1056](https://github.com/lwouis/alt-tab-macos/issues/1056)) ([6f33e3a](https://github.com/lwouis/alt-tab-macos/commit/6f33e3a))
* hide window controls after a window is closed (closes [#925](https://github.com/lwouis/alt-tab-macos/issues/925)) ([0dad739](https://github.com/lwouis/alt-tab-macos/commit/0dad739))
* highlight right thumbnail when no window is focused (closes [#1044](https://github.com/lwouis/alt-tab-macos/issues/1044)) ([f4d3db7](https://github.com/lwouis/alt-tab-macos/commit/f4d3db7))
* showing windows of other screens when it shouldn't (closes [#1052](https://github.com/lwouis/alt-tab-macos/issues/1052)) ([b5b3c38](https://github.com/lwouis/alt-tab-macos/commit/b5b3c38))


### Features

* add vietnamese and luxembourgish localizations ([749db12](https://github.com/lwouis/alt-tab-macos/commit/749db12))
* improve french, portuguese and chinese localizations ([a7026a4](https://github.com/lwouis/alt-tab-macos/commit/a7026a4))
* remove "active space" from filter list ([4623e5b](https://github.com/lwouis/alt-tab-macos/commit/4623e5b))
* support voiceover + "speak items under the cursor" (closes [#1070](https://github.com/lwouis/alt-tab-macos/issues/1070)) ([c7911f3](https://github.com/lwouis/alt-tab-macos/commit/c7911f3))

## [6.22.1](https://github.com/lwouis/alt-tab-macos/compare/v6.22.0...v6.22.1) (2021-05-12)


### Bug Fixes

* certain jetbrain apps windows were not shown (closes [#948](https://github.com/lwouis/alt-tab-macos/issues/948)) ([5958107](https://github.com/lwouis/alt-tab-macos/commit/5958107))

# [6.22.0](https://github.com/lwouis/alt-tab-macos/compare/v6.21.2...v6.22.0) (2021-05-10)


### Bug Fixes

* remove jetbrain app non-windows (closes [#885](https://github.com/lwouis/alt-tab-macos/issues/885)) ([a368af3](https://github.com/lwouis/alt-tab-macos/commit/a368af3))


### Features

* add citrix viewer in the default blacklist (see [#381](https://github.com/lwouis/alt-tab-macos/issues/381)) ([e630acf](https://github.com/lwouis/alt-tab-macos/commit/e630acf))

## [6.21.2](https://github.com/lwouis/alt-tab-macos/compare/v6.21.1...v6.21.2) (2021-04-20)


### Bug Fixes

* selected thumbnail was sometimes wrong (closes [#926](https://github.com/lwouis/alt-tab-macos/issues/926)) ([1da3f32](https://github.com/lwouis/alt-tab-macos/commit/1da3f32))

## [6.21.1](https://github.com/lwouis/alt-tab-macos/compare/v6.21.0...v6.21.1) (2021-04-19)


### Bug Fixes

* crash on launch on a new install (closes [#928](https://github.com/lwouis/alt-tab-macos/issues/928)) ([bed3351](https://github.com/lwouis/alt-tab-macos/commit/bed3351))

# [6.21.0](https://github.com/lwouis/alt-tab-macos/compare/v6.20.0...v6.21.0) (2021-04-17)


### Bug Fixes

* apps could steal key focus from alt-tab main window ([#719](https://github.com/lwouis/alt-tab-macos/issues/719) [#916](https://github.com/lwouis/alt-tab-macos/issues/916)) ([6be72f3](https://github.com/lwouis/alt-tab-macos/commit/6be72f3))


### Features

* update korean location ([c1fc40d](https://github.com/lwouis/alt-tab-macos/commit/c1fc40d))

# [6.20.0](https://github.com/lwouis/alt-tab-macos/compare/v6.19.0...v6.20.0) (2021-04-15)


### Bug Fixes

* broken preferences window toolbar on macos 11 (closes [#914](https://github.com/lwouis/alt-tab-macos/issues/914)) ([1539030](https://github.com/lwouis/alt-tab-macos/commit/1539030))


### Features

* update contributors ([9847038](https://github.com/lwouis/alt-tab-macos/commit/9847038))

# [6.19.0](https://github.com/lwouis/alt-tab-macos/compare/v6.18.1...v6.19.0) (2021-04-14)


### Bug Fixes

* correct Wikipedia link ([5a41561](https://github.com/lwouis/alt-tab-macos/commit/5a41561))
* intellij fullscreen windows sometimes not showing ([#824](https://github.com/lwouis/alt-tab-macos/issues/824)) ([4dcb6bb](https://github.com/lwouis/alt-tab-macos/commit/4dcb6bb))
* rare crash when the ui was kept open during space transition ([e869900](https://github.com/lwouis/alt-tab-macos/commit/e869900))


### Features

* added NICE DCV to the don't show list ([3a98628](https://github.com/lwouis/alt-tab-macos/commit/3a98628))
* update german, russian, swedish localization ([6f1a27a](https://github.com/lwouis/alt-tab-macos/commit/6f1a27a))
* update korean, polish, and brazilian localizations ([5bc8f82](https://github.com/lwouis/alt-tab-macos/commit/5bc8f82))

## [6.18.1](https://github.com/lwouis/alt-tab-macos/compare/v6.18.0...v6.18.1) (2021-03-13)


### Bug Fixes

* force new release ([1a098af](https://github.com/lwouis/alt-tab-macos/commit/1a098af))

# [6.18.0](https://github.com/lwouis/alt-tab-macos/compare/v6.17.0...v6.18.0) (2021-03-13)


### Bug Fixes

* more robust handling of custom shortcuts ([339aeaa](https://github.com/lwouis/alt-tab-macos/commit/339aeaa))
* windows launched already fullscreen sometimes didn't show ([#824](https://github.com/lwouis/alt-tab-macos/issues/824)) ([62b43f2](https://github.com/lwouis/alt-tab-macos/commit/62b43f2))


### Features

* avoid disabling native command-tab (closes [#834](https://github.com/lwouis/alt-tab-macos/issues/834)) ([fb51c5d](https://github.com/lwouis/alt-tab-macos/commit/fb51c5d))
* update contributors list ([5c7aa38](https://github.com/lwouis/alt-tab-macos/commit/5c7aa38))

# [6.17.0](https://github.com/lwouis/alt-tab-macos/compare/v6.16.0...v6.17.0) (2021-02-26)


### Features

* space number start at 1 instead of 0 ([#838](https://github.com/lwouis/alt-tab-macos/issues/838)) ([200dafa](https://github.com/lwouis/alt-tab-macos/commit/200dafa))

# [6.16.0](https://github.com/lwouis/alt-tab-macos/compare/v6.15.3...v6.16.0) (2021-02-24)


### Features

* remove unused localized text ([e7ef15b](https://github.com/lwouis/alt-tab-macos/commit/e7ef15b))
* tell users about conflicting shortcuts (close [#832](https://github.com/lwouis/alt-tab-macos/issues/832)) ([b345648](https://github.com/lwouis/alt-tab-macos/commit/b345648))

## [6.15.3](https://github.com/lwouis/alt-tab-macos/compare/v6.15.2...v6.15.3) (2021-02-23)


### Bug Fixes

* better permission revocation detection ([f6d75fb](https://github.com/lwouis/alt-tab-macos/commit/f6d75fb))

## [6.15.2](https://github.com/lwouis/alt-tab-macos/compare/v6.15.1...v6.15.2) (2021-02-23)


### Bug Fixes

* avoid restarting alt-tab in some rare scenarios ([#825](https://github.com/lwouis/alt-tab-macos/issues/825)) ([4003df4](https://github.com/lwouis/alt-tab-macos/commit/4003df4))
* show windows of apps launched hidden ([#390](https://github.com/lwouis/alt-tab-macos/issues/390)) ([eb5d019](https://github.com/lwouis/alt-tab-macos/commit/eb5d019))

## [6.15.1](https://github.com/lwouis/alt-tab-macos/compare/v6.15.0...v6.15.1) (2021-02-16)


### Bug Fixes

* didn't show skim app windows (closes [#772](https://github.com/lwouis/alt-tab-macos/issues/772)) ([fed2eb6](https://github.com/lwouis/alt-tab-macos/commit/fed2eb6))
* issues with the app mediathekview (closes [#822](https://github.com/lwouis/alt-tab-macos/issues/822)) ([0181547](https://github.com/lwouis/alt-tab-macos/commit/0181547))
* live2d cubism editor stuck on startup (closes [#813](https://github.com/lwouis/alt-tab-macos/issues/813)) ([ee5c44f](https://github.com/lwouis/alt-tab-macos/commit/ee5c44f))

# [6.15.0](https://github.com/lwouis/alt-tab-macos/compare/v6.14.0...v6.15.0) (2021-02-02)


### Bug Fixes

* show vlc fullscreen video (closes [#792](https://github.com/lwouis/alt-tab-macos/issues/792)) ([e675fab](https://github.com/lwouis/alt-tab-macos/commit/e675fab))


### Features

* update russian localization ([909c123](https://github.com/lwouis/alt-tab-macos/commit/909c123))

# [6.14.0](https://github.com/lwouis/alt-tab-macos/compare/v6.13.0...v6.14.0) (2021-02-01)


### Bug Fixes

* crash in very rare data-race ([e9e61af](https://github.com/lwouis/alt-tab-macos/commit/e9e61af)), closes [#1](https://github.com/lwouis/alt-tab-macos/issues/1)
* didn't show windows on same screen (closes [#794](https://github.com/lwouis/alt-tab-macos/issues/794)) ([b02e8be](https://github.com/lwouis/alt-tab-macos/commit/b02e8be))


### Features

* update korean, portuguese, swedish localizations ([81a33b8](https://github.com/lwouis/alt-tab-macos/commit/81a33b8))

# [6.13.0](https://github.com/lwouis/alt-tab-macos/compare/v6.12.0...v6.13.0) (2021-01-25)


### Bug Fixes

* app would sometimes quit while in the background (closes [#704](https://github.com/lwouis/alt-tab-macos/issues/704)) ([d621ce5](https://github.com/lwouis/alt-tab-macos/commit/d621ce5))
* disable standard tab detection for all JetBrains apps ([25343ea](https://github.com/lwouis/alt-tab-macos/commit/25343ea)), closes [#716](https://github.com/lwouis/alt-tab-macos/issues/716)
* prevent macos 11 from terminating alt-tab randomly ([2447140](https://github.com/lwouis/alt-tab-macos/commit/2447140))
* restarting the app would sometimes fail to start again ([56d47fc](https://github.com/lwouis/alt-tab-macos/commit/56d47fc))
* show window controls, even when mouse hover option is disabled ([c256933](https://github.com/lwouis/alt-tab-macos/commit/c256933))


### Features

* add app category meta-data ([96572a8](https://github.com/lwouis/alt-tab-macos/commit/96572a8))
* add swedish and czech localizations ([00e95d6](https://github.com/lwouis/alt-tab-macos/commit/00e95d6))
* add ukrainian localization ([e576ca1](https://github.com/lwouis/alt-tab-macos/commit/e576ca1))
* display windows partially on screen correctly (closes [#727](https://github.com/lwouis/alt-tab-macos/issues/727)) ([2f92936](https://github.com/lwouis/alt-tab-macos/commit/2f92936))
* show window partially on-screen (closes [#727](https://github.com/lwouis/alt-tab-macos/issues/727)) ([b121162](https://github.com/lwouis/alt-tab-macos/commit/b121162))
* update japanese, turkish, chinese localizations ([7226c25](https://github.com/lwouis/alt-tab-macos/commit/7226c25))

# [6.12.0](https://github.com/lwouis/alt-tab-macos/compare/v6.11.0...v6.12.0) (2020-11-17)


### Bug Fixes

* window was not shown after closing tab (closes [#696](https://github.com/lwouis/alt-tab-macos/issues/696)) ([a7e96f2](https://github.com/lwouis/alt-tab-macos/commit/a7e96f2))


### Features

* add slovak localization ([06027dc](https://github.com/lwouis/alt-tab-macos/commit/06027dc))

# [6.11.0](https://github.com/lwouis/alt-tab-macos/compare/v6.10.0...v6.11.0) (2020-11-11)


### Bug Fixes

* some windows would not be shown in fullscreen app (closes [#688](https://github.com/lwouis/alt-tab-macos/issues/688)) ([5f9caed](https://github.com/lwouis/alt-tab-macos/commit/5f9caed))


### Features

* add preference to show visible spaces (closes [#583](https://github.com/lwouis/alt-tab-macos/issues/583)) ([545437e](https://github.com/lwouis/alt-tab-macos/commit/545437e))
* added slovenian localization ([8b22d41](https://github.com/lwouis/alt-tab-macos/commit/8b22d41))

# [6.10.0](https://github.com/lwouis/alt-tab-macos/compare/v6.9.0...v6.10.0) (2020-11-09)


### Bug Fixes

* some apps were not showing (closes [#677](https://github.com/lwouis/alt-tab-macos/issues/677), closes [#679](https://github.com/lwouis/alt-tab-macos/issues/679)) ([e0fa680](https://github.com/lwouis/alt-tab-macos/commit/e0fa680))


### Features

* improve french, hungarian and polish localizations ([bf21a4e](https://github.com/lwouis/alt-tab-macos/commit/bf21a4e))

# [6.9.0](https://github.com/lwouis/alt-tab-macos/compare/v6.8.0...v6.9.0) (2020-10-27)


### Features

* don't show glitchy windows from non-native apps (closes [#562](https://github.com/lwouis/alt-tab-macos/issues/562)) ([84dbaa0](https://github.com/lwouis/alt-tab-macos/commit/84dbaa0)), closes [#456](https://github.com/lwouis/alt-tab-macos/issues/456)
* update chinese localization ([9240040](https://github.com/lwouis/alt-tab-macos/commit/9240040))
* update french localization ([e9a6f54](https://github.com/lwouis/alt-tab-macos/commit/e9a6f54))

# [6.8.0](https://github.com/lwouis/alt-tab-macos/compare/v6.7.4...v6.8.0) (2020-10-26)


### Bug Fixes

* rare crash at launch during permissions grant ([6120418](https://github.com/lwouis/alt-tab-macos/commit/6120418))


### Features

* update dutch localization ([8cf9954](https://github.com/lwouis/alt-tab-macos/commit/8cf9954))

## [6.7.4](https://github.com/lwouis/alt-tab-macos/compare/v6.7.3...v6.7.4) (2020-10-15)


### Bug Fixes

* shortcuts temporarily stuck in intellij eap (closes [#652](https://github.com/lwouis/alt-tab-macos/issues/652)) ([7c171c2](https://github.com/lwouis/alt-tab-macos/commit/7c171c2))
* show the android emulator (closes [#653](https://github.com/lwouis/alt-tab-macos/issues/653)) ([16c7a93](https://github.com/lwouis/alt-tab-macos/commit/16c7a93))

## [6.7.3](https://github.com/lwouis/alt-tab-macos/compare/v6.7.2...v6.7.3) (2020-10-10)


### Bug Fixes

* apparition delay preference would sometimes not be respected ([3019dd5](https://github.com/lwouis/alt-tab-macos/commit/3019dd5))
* ui would sometimes stay open (closes [#588](https://github.com/lwouis/alt-tab-macos/issues/588)) ([8912c70](https://github.com/lwouis/alt-tab-macos/commit/8912c70))

## [6.7.2](https://github.com/lwouis/alt-tab-macos/compare/v6.7.1...v6.7.2) (2020-10-06)


### Bug Fixes

* crash in rare unknown scenario scenario ([08581f5](https://github.com/lwouis/alt-tab-macos/commit/08581f5))
* crash on blacklisted app with main shortcut cleared ([c3f0686](https://github.com/lwouis/alt-tab-macos/commit/c3f0686))
* ignore more non-user-facing apps (xpc processes) ([8417564](https://github.com/lwouis/alt-tab-macos/commit/8417564))
* key repeat rate was too fast on high fps monitors (closes [#633](https://github.com/lwouis/alt-tab-macos/issues/633)) ([b408f14](https://github.com/lwouis/alt-tab-macos/commit/b408f14))
* keynote was not showing while in slideshow mode (closes [#636](https://github.com/lwouis/alt-tab-macos/issues/636)) ([ec7b69f](https://github.com/lwouis/alt-tab-macos/commit/ec7b69f))
* space transition sometimes absorbed the shortcut (closes [#588](https://github.com/lwouis/alt-tab-macos/issues/588)) ([5e6a0c2](https://github.com/lwouis/alt-tab-macos/commit/5e6a0c2))

## [6.7.1](https://github.com/lwouis/alt-tab-macos/compare/v6.7.0...v6.7.1) (2020-09-27)


### Bug Fixes

* crashes when some shortcuts was set to nothing ([9b3e4b1](https://github.com/lwouis/alt-tab-macos/commit/9b3e4b1))

# [6.7.0](https://github.com/lwouis/alt-tab-macos/compare/v6.6.0...v6.7.0) (2020-09-25)


### Bug Fixes

* cpu usage higher than normal for 2min after quitting an app ([2f4c56c](https://github.com/lwouis/alt-tab-macos/commit/2f4c56c))
* crash on launch in some rare scenarios (closes [#615](https://github.com/lwouis/alt-tab-macos/issues/615)) ([5d4b2b0](https://github.com/lwouis/alt-tab-macos/commit/5d4b2b0))


### Features

* make shortcuts repeat when held down (closes [#556](https://github.com/lwouis/alt-tab-macos/issues/556)) ([6803b02](https://github.com/lwouis/alt-tab-macos/commit/6803b02))
* show openboard window ([#621](https://github.com/lwouis/alt-tab-macos/issues/621)) ([5b35601](https://github.com/lwouis/alt-tab-macos/commit/5b35601))
* update japanese and portuguese (brazil) localizations ([85638df](https://github.com/lwouis/alt-tab-macos/commit/85638df))
* update russian localization ([40ef009](https://github.com/lwouis/alt-tab-macos/commit/40ef009))

# [6.6.0](https://github.com/lwouis/alt-tab-macos/compare/v6.5.0...v6.6.0) (2020-09-14)


### Bug Fixes

* app would sometimes crash at launch (closes [#607](https://github.com/lwouis/alt-tab-macos/issues/607)) ([7288013](https://github.com/lwouis/alt-tab-macos/commit/7288013))


### Features

* update japanese localization ([473e08f](https://github.com/lwouis/alt-tab-macos/commit/473e08f))

# [6.5.0](https://github.com/lwouis/alt-tab-macos/compare/v6.4.0...v6.5.0) (2020-09-09)


### Bug Fixes

* ui would take time to display sometimes (see [#563](https://github.com/lwouis/alt-tab-macos/issues/563)) ([7efc806](https://github.com/lwouis/alt-tab-macos/commit/7efc806))


### Features

* update russian and dutch localizations ([eaa0cc9](https://github.com/lwouis/alt-tab-macos/commit/eaa0cc9))

# [6.4.0](https://github.com/lwouis/alt-tab-macos/compare/v6.3.0...v6.4.0) (2020-09-08)


### Features

* update chinese, korean, and german localizations ([1514eca](https://github.com/lwouis/alt-tab-macos/commit/1514eca))


### Performance Improvements

* guaranty app nap is not interfering ([4895ee7](https://github.com/lwouis/alt-tab-macos/commit/4895ee7))
* prevent random freezes of the ui ([#563](https://github.com/lwouis/alt-tab-macos/issues/563)) ([e208da9](https://github.com/lwouis/alt-tab-macos/commit/e208da9))

# [6.3.0](https://github.com/lwouis/alt-tab-macos/compare/v6.2.0...v6.3.0) (2020-09-08)


### Bug Fixes

* adobe audition windows were not showing up (closes [#581](https://github.com/lwouis/alt-tab-macos/issues/581)) ([6edced0](https://github.com/lwouis/alt-tab-macos/commit/6edced0))
* crash from appcenter in rare scenario ([c49a2bc](https://github.com/lwouis/alt-tab-macos/commit/c49a2bc)), closes [#1](https://github.com/lwouis/alt-tab-macos/issues/1)
* load app badges asynchronously to avoid system lag (closes [#563](https://github.com/lwouis/alt-tab-macos/issues/563)) ([29eff03](https://github.com/lwouis/alt-tab-macos/commit/29eff03))
* prevent rare crash seen in app center ([6ca58b1](https://github.com/lwouis/alt-tab-macos/commit/6ca58b1))


### Features

* show minimized/hidden windows last in the list (closes [#289](https://github.com/lwouis/alt-tab-macos/issues/289)) ([4fea943](https://github.com/lwouis/alt-tab-macos/commit/4fea943))
* split max screen size preference into width/height (closes [#579](https://github.com/lwouis/alt-tab-macos/issues/579)) ([6e2e5b4](https://github.com/lwouis/alt-tab-macos/commit/6e2e5b4))
* update es, ja, ko, nl, pt, pt-br localizations ([af5ed9b](https://github.com/lwouis/alt-tab-macos/commit/af5ed9b))

# [6.2.0](https://github.com/lwouis/alt-tab-macos/compare/v6.1.0...v6.2.0) (2020-09-04)


### Bug Fixes

* apps would not quit properly sometimes (regression from 10b2c71) ([41384d9](https://github.com/lwouis/alt-tab-macos/commit/41384d9))
* avoid random delay after releasing shortcut (closes [#563](https://github.com/lwouis/alt-tab-macos/issues/563)) ([cbc4c39](https://github.com/lwouis/alt-tab-macos/commit/cbc4c39))
* crash on launch if the user didn't have sf symbols font ([58e9026](https://github.com/lwouis/alt-tab-macos/commit/58e9026))
* focused wrong window in rare scenario ([66820a1](https://github.com/lwouis/alt-tab-macos/commit/66820a1))
* issue when selecting windowless app from fullscreen window ([657c9e5](https://github.com/lwouis/alt-tab-macos/commit/657c9e5))
* smoother behavior when summoned during a space transition ([e6ded6c](https://github.com/lwouis/alt-tab-macos/commit/e6ded6c))
* thumbnail sizes could be wrong when switching between screens ([e13a263](https://github.com/lwouis/alt-tab-macos/commit/e13a263))
* triggering alt-tab during space transition failed (closes [#566](https://github.com/lwouis/alt-tab-macos/issues/566)) ([d66d788](https://github.com/lwouis/alt-tab-macos/commit/d66d788))
* windowless apps would rarely show despite the blacklist ([355225b](https://github.com/lwouis/alt-tab-macos/commit/355225b))
* workaround a quick in photoshop (closes [#571](https://github.com/lwouis/alt-tab-macos/issues/571)) ([7218418](https://github.com/lwouis/alt-tab-macos/commit/7218418))


### Features

* allow per-shortcut release action preference (closes [#573](https://github.com/lwouis/alt-tab-macos/issues/573)) ([2a9c33b](https://github.com/lwouis/alt-tab-macos/commit/2a9c33b))
* first blacklist can now match prefixes instead of full ids ([10693d0](https://github.com/lwouis/alt-tab-macos/commit/10693d0))
* new preference to hide thumbnails (closes [#384](https://github.com/lwouis/alt-tab-macos/issues/384)) ([877c93c](https://github.com/lwouis/alt-tab-macos/commit/877c93c))
* show about item in menubar menu (closes [#574](https://github.com/lwouis/alt-tab-macos/issues/574)) ([78d1d8f](https://github.com/lwouis/alt-tab-macos/commit/78d1d8f))
* show apps with no open window (closes [#397](https://github.com/lwouis/alt-tab-macos/issues/397)) ([f0fa02c](https://github.com/lwouis/alt-tab-macos/commit/f0fa02c))
* update fi, hu, nl, pl, ru, zn-tw localizations ([df3010a](https://github.com/lwouis/alt-tab-macos/commit/df3010a))
* update japanese and korean localizations ([2a2368d](https://github.com/lwouis/alt-tab-macos/commit/2a2368d))


### Performance Improvements

* add preferences cache to reduce app latency by a few ms ([17863b5](https://github.com/lwouis/alt-tab-macos/commit/17863b5))
* menubar takes a few frame less to compute ([3b7350f](https://github.com/lwouis/alt-tab-macos/commit/3b7350f))
* reduce image assets size even further using optimage ([63d8545](https://github.com/lwouis/alt-tab-macos/commit/63d8545))

# [6.1.0](https://github.com/lwouis/alt-tab-macos/compare/v6.0.0...v6.1.0) (2020-08-31)


### Bug Fixes

* crash when user click a specific spot of shortcut ui (closes [#495](https://github.com/lwouis/alt-tab-macos/issues/495)) ([959a8ae](https://github.com/lwouis/alt-tab-macos/commit/959a8ae))
* focusing alt-tab own windows with alt-tab had jank (closes [#501](https://github.com/lwouis/alt-tab-macos/issues/501)) ([c927920](https://github.com/lwouis/alt-tab-macos/commit/c927920))
* some users have corrupted preferences, crashing on launch ([3062566](https://github.com/lwouis/alt-tab-macos/commit/3062566))


### Features

* add polish localization ([9fd25df](https://github.com/lwouis/alt-tab-macos/commit/9fd25df))
* update indonesian localization ([4ee875b](https://github.com/lwouis/alt-tab-macos/commit/4ee875b))


### Performance Improvements

* compress the 3 colored circle icons ([20e474b](https://github.com/lwouis/alt-tab-macos/commit/20e474b))

# [6.0.0](https://github.com/lwouis/alt-tab-macos/compare/v5.3.0...v6.0.0) (2020-08-27)


### Bug Fixes

* alt-tab own windows were not shown in alt-tab (closes [#555](https://github.com/lwouis/alt-tab-macos/issues/555)) ([8bcbc04](https://github.com/lwouis/alt-tab-macos/commit/8bcbc04))
* clicking the main window would steal focus ([de02e5b](https://github.com/lwouis/alt-tab-macos/commit/de02e5b))
* display firefox develop edition fullscreen windows (closes [#558](https://github.com/lwouis/alt-tab-macos/issues/558)) ([3250d37](https://github.com/lwouis/alt-tab-macos/commit/3250d37))
* guarantee alt-tab window is always up-to-date on display ([be4c5f1](https://github.com/lwouis/alt-tab-macos/commit/be4c5f1))
* ignore zombie processes ([50c8c82](https://github.com/lwouis/alt-tab-macos/commit/50c8c82))
* moving some of the preferences sliders was very laggy ([a552c4c](https://github.com/lwouis/alt-tab-macos/commit/a552c4c))
* shortcuts stop working if active app is quit (closes [#557](https://github.com/lwouis/alt-tab-macos/issues/557)) ([023561d](https://github.com/lwouis/alt-tab-macos/commit/023561d))


### Features

* display quickly even with many open windows (closes [#171](https://github.com/lwouis/alt-tab-macos/issues/171)) ([da16a0b](https://github.com/lwouis/alt-tab-macos/commit/da16a0b))
* improve the 3 colored buttons when hovering (closes [#516](https://github.com/lwouis/alt-tab-macos/issues/516)) ([3ddedff](https://github.com/lwouis/alt-tab-macos/commit/3ddedff))
* update chinese localization ([e150a9a](https://github.com/lwouis/alt-tab-macos/commit/e150a9a))


### Performance Improvements

* alt-tab appears quicker when summoned ([c2bb896](https://github.com/lwouis/alt-tab-macos/commit/c2bb896))
* main window appears (a few frames) faster on trigger ([2bc09e6](https://github.com/lwouis/alt-tab-macos/commit/2bc09e6))


### BREAKING CHANGES

* the window thumbnails are now updated *after* the UI is shown. AltTab will first display its window, with the first 3 thumbnails up-to-date, then asynchronously update the rest of the thumbnails one-by-one. This improves the experience of users with lots of windows open.

# [5.3.0](https://github.com/lwouis/alt-tab-macos/compare/v5.2.0...v5.3.0) (2020-08-25)


### Bug Fixes

* app badges would sometimes not be up-to-date ([8ad03a5](https://github.com/lwouis/alt-tab-macos/commit/8ad03a5))
* rare crash when alt-tab is triggered when the dock isn't running ([9c02ceb](https://github.com/lwouis/alt-tab-macos/commit/9c02ceb))
* second blacklist was too tall on some systems ([522633b](https://github.com/lwouis/alt-tab-macos/commit/522633b))
* the ui would not hide if capslock was active (closes [#551](https://github.com/lwouis/alt-tab-macos/issues/551)) ([b4b82b2](https://github.com/lwouis/alt-tab-macos/commit/b4b82b2))


### Features

* add norwegian localization ([c344da7](https://github.com/lwouis/alt-tab-macos/commit/c344da7))
* blacklist mcafee safari host by default (closes [#386](https://github.com/lwouis/alt-tab-macos/issues/386)) ([a7ef4c7](https://github.com/lwouis/alt-tab-macos/commit/a7ef4c7))

# [5.2.0](https://github.com/lwouis/alt-tab-macos/compare/v5.1.0...v5.2.0) (2020-08-24)


### Bug Fixes

* books.app windows were not always showing (closes [#481](https://github.com/lwouis/alt-tab-macos/issues/481)) ([9e92dfa](https://github.com/lwouis/alt-tab-macos/commit/9e92dfa))


### Features

* blacklisting apps can use start of the bundle id (closes [#549](https://github.com/lwouis/alt-tab-macos/issues/549)) ([de9cf46](https://github.com/lwouis/alt-tab-macos/commit/de9cf46))
* update french and portuguese localizations ([7a02ea5](https://github.com/lwouis/alt-tab-macos/commit/7a02ea5))


### Performance Improvements

* remove no-longer-used localization strings ([ce7836a](https://github.com/lwouis/alt-tab-macos/commit/ce7836a))

# [5.1.0](https://github.com/lwouis/alt-tab-macos/compare/v5.0.0...v5.1.0) (2020-08-20)


### Bug Fixes

* sometimes crashed when opening the preferences window (closes [#543](https://github.com/lwouis/alt-tab-macos/issues/543)) ([0f3c91a](https://github.com/lwouis/alt-tab-macos/commit/0f3c91a))


### Features

* update korean and portuguese localizations ([32ff753](https://github.com/lwouis/alt-tab-macos/commit/32ff753))


### Performance Improvements

* fix very small memory leaks ([8b7da21](https://github.com/lwouis/alt-tab-macos/commit/8b7da21))

# [5.0.0](https://github.com/lwouis/alt-tab-macos/compare/v4.19.0...v5.0.0) (2020-08-18)


### Bug Fixes

* app icon was not showing on macos 10.12 (see [#522](https://github.com/lwouis/alt-tab-macos/issues/522)) ([2a45dec](https://github.com/lwouis/alt-tab-macos/commit/2a45dec))
* battle.net installer and wow were not showing in alt-tab ([793b10b](https://github.com/lwouis/alt-tab-macos/commit/793b10b)), closes [#536](https://github.com/lwouis/alt-tab-macos/issues/536)
* portuguese from portugal was shown to brazil users ([e54c2de](https://github.com/lwouis/alt-tab-macos/commit/e54c2de))
* rare crash when the os was not providing the current space id ([cf05044](https://github.com/lwouis/alt-tab-macos/commit/cf05044))
* rewrote the preference window to fix crashes and jank (closes [#502](https://github.com/lwouis/alt-tab-macos/issues/502)) ([f9f5b8a](https://github.com/lwouis/alt-tab-macos/commit/f9f5b8a))


### Features

* change default key to select window from `return` to `space` ([eec694e](https://github.com/lwouis/alt-tab-macos/commit/eec694e))
* complete rewrite of the keyboard support (closes [#157](https://github.com/lwouis/alt-tab-macos/issues/157)) ([d3253ba](https://github.com/lwouis/alt-tab-macos/commit/d3253ba))
* show notification badges on top of app icons (closes [#523](https://github.com/lwouis/alt-tab-macos/issues/523)) ([fb62834](https://github.com/lwouis/alt-tab-macos/commit/fb62834))
* update portuguese (brazil) localization ([726acd3](https://github.com/lwouis/alt-tab-macos/commit/726acd3))
* updated japanese localization ([36c7b0a](https://github.com/lwouis/alt-tab-macos/commit/36c7b0a))


### BREAKING CHANGES

* the previous keyboard support implementation was not working if any app on the system activated Secure Input and didn't turn it off. This is a major hurdle for most global shortcut apps. This update introduces a new implementation which is unaffected by Secure Input. AltTab shortcuts should now work reliably

# [4.19.0](https://github.com/lwouis/alt-tab-macos/compare/v4.18.0...v4.19.0) (2020-08-11)


### Bug Fixes

* checkboxes not showing properly on macos 10.13 (see [#507](https://github.com/lwouis/alt-tab-macos/issues/507)) ([43a9cb1](https://github.com/lwouis/alt-tab-macos/commit/43a9cb1))
* menubar icon not showing on macos 10.13 (closes [#507](https://github.com/lwouis/alt-tab-macos/issues/507)) ([2fa0b8a](https://github.com/lwouis/alt-tab-macos/commit/2fa0b8a))


### Features

* update portuguese (brazil) and chinese (simplified) localizations ([2b1b5fa](https://github.com/lwouis/alt-tab-macos/commit/2b1b5fa))

# [4.18.0](https://github.com/lwouis/alt-tab-macos/compare/v4.17.2...v4.18.0) (2020-08-11)


### Bug Fixes

* "no menubar icon" preference has correct height ([025053d](https://github.com/lwouis/alt-tab-macos/commit/025053d))


### Features

* add portuguese localization ([fd705b4](https://github.com/lwouis/alt-tab-macos/commit/fd705b4))
* update portuguese (brazil) and russian localizations ([2cebaaa](https://github.com/lwouis/alt-tab-macos/commit/2cebaaa))

## [4.17.2](https://github.com/lwouis/alt-tab-macos/compare/v4.17.1...v4.17.2) (2020-08-07)


### Bug Fixes

* shortcut 2 was showing shortcut 1 value after restart (closes [#500](https://github.com/lwouis/alt-tab-macos/issues/500)) ([74ed25d](https://github.com/lwouis/alt-tab-macos/commit/74ed25d))

## [4.17.1](https://github.com/lwouis/alt-tab-macos/compare/v4.17.0...v4.17.1) (2020-08-07)


### Bug Fixes

* in dark mode, the colored menubar icon was too bright ([845ae5c](https://github.com/lwouis/alt-tab-macos/commit/845ae5c))
* preference window tab icons adapt to dark mode (closes [#498](https://github.com/lwouis/alt-tab-macos/issues/498)) ([0c44c50](https://github.com/lwouis/alt-tab-macos/commit/0c44c50))

# [4.17.0](https://github.com/lwouis/alt-tab-macos/compare/v4.16.0...v4.17.0) (2020-08-07)


### Bug Fixes

* rare crash when started at login ([80945c8](https://github.com/lwouis/alt-tab-macos/commit/80945c8))


### Features

* update korean localization ([640bad8](https://github.com/lwouis/alt-tab-macos/commit/640bad8))

# [4.16.0](https://github.com/lwouis/alt-tab-macos/compare/v4.15.0...v4.16.0) (2020-08-06)


### Bug Fixes

* removing shortcut 2 was not working properly (see [#493](https://github.com/lwouis/alt-tab-macos/issues/493)) ([fcdf40a](https://github.com/lwouis/alt-tab-macos/commit/fcdf40a))
* shortcut would not register if capslock was on (closes [#493](https://github.com/lwouis/alt-tab-macos/issues/493)) ([9db0fe4](https://github.com/lwouis/alt-tab-macos/commit/9db0fe4))


### Features

* let users minimize the preferences window ([2a0adf0](https://github.com/lwouis/alt-tab-macos/commit/2a0adf0))

# [4.15.0](https://github.com/lwouis/alt-tab-macos/compare/v4.14.0...v4.15.0) (2020-08-06)


### Features

* add new colorful menubar icon ([8f5c2a0](https://github.com/lwouis/alt-tab-macos/commit/8f5c2a0))


### Performance Improvements

* reduce size of app icon (closes [#169](https://github.com/lwouis/alt-tab-macos/issues/169)) ([bb49302](https://github.com/lwouis/alt-tab-macos/commit/bb49302))

# [4.14.0](https://github.com/lwouis/alt-tab-macos/compare/v4.13.1...v4.14.0) (2020-08-06)


### Bug Fixes

* rare crash at launch ([461840e](https://github.com/lwouis/alt-tab-macos/commit/461840e))


### Features

* can now pick between multiple menubar icons (closes [#191](https://github.com/lwouis/alt-tab-macos/issues/191)) ([30f0322](https://github.com/lwouis/alt-tab-macos/commit/30f0322))

## [4.13.1](https://github.com/lwouis/alt-tab-macos/compare/v4.13.0...v4.13.1) (2020-08-05)


### Bug Fixes

* increase app icon size in about tab ([94a0cd8](https://github.com/lwouis/alt-tab-macos/commit/94a0cd8))
* preference window now always appears centered ([e770f18](https://github.com/lwouis/alt-tab-macos/commit/e770f18))

# [4.13.0](https://github.com/lwouis/alt-tab-macos/compare/v4.12.2...v4.13.0) (2020-08-05)


### Features

* even more flexible controls (closes [#458](https://github.com/lwouis/alt-tab-macos/issues/458), closes [#463](https://github.com/lwouis/alt-tab-macos/issues/463)) ([a990bbe](https://github.com/lwouis/alt-tab-macos/commit/a990bbe))
* new icons for the preferences window tabs ([b20c71c](https://github.com/lwouis/alt-tab-macos/commit/b20c71c))


### Performance Improvements

* reduced size of app ([2df0c22](https://github.com/lwouis/alt-tab-macos/commit/2df0c22))

## [4.12.2](https://github.com/lwouis/alt-tab-macos/compare/v4.12.1...v4.12.2) (2020-08-04)


### Bug Fixes

* rare crash at launch if the app previously crashed ([6444732](https://github.com/lwouis/alt-tab-macos/commit/6444732))
* rare crash when being started twice quickly at login ([a6365fb](https://github.com/lwouis/alt-tab-macos/commit/a6365fb))

## [4.12.1](https://github.com/lwouis/alt-tab-macos/compare/v4.12.0...v4.12.1) (2020-08-03)


### Bug Fixes

* occasional wrong window order after focusing a window (closes [#484](https://github.com/lwouis/alt-tab-macos/issues/484)) ([d6b1fb4](https://github.com/lwouis/alt-tab-macos/commit/d6b1fb4))

# [4.12.0](https://github.com/lwouis/alt-tab-macos/compare/v4.11.1...v4.12.0) (2020-08-03)


### Features

* better default shortcuts on non-us keyboards (closes [#480](https://github.com/lwouis/alt-tab-macos/issues/480)) ([ea52111](https://github.com/lwouis/alt-tab-macos/commit/ea52111))
* update german, korean, chinese localizations ([fcbc89e](https://github.com/lwouis/alt-tab-macos/commit/fcbc89e))


### Performance Improvements

* slightly less latency for keyboard/mouse/os events ([28fb5f4](https://github.com/lwouis/alt-tab-macos/commit/28fb5f4))
* slightly reduce energy usage ([26e840c](https://github.com/lwouis/alt-tab-macos/commit/26e840c))

## [4.11.1](https://github.com/lwouis/alt-tab-macos/compare/v4.11.0...v4.11.1) (2020-07-30)


### Bug Fixes

* rare crash at launch if the app previously crashed ([12c27f1](https://github.com/lwouis/alt-tab-macos/commit/12c27f1))
* rare crash when user cycles while all windows get closed ([e901ca3](https://github.com/lwouis/alt-tab-macos/commit/e901ca3))

# [4.11.0](https://github.com/lwouis/alt-tab-macos/compare/v4.10.0...v4.11.0) (2020-07-29)


### Bug Fixes

* crash if accessibility permission is granted then removed quickly ([0bca1e0](https://github.com/lwouis/alt-tab-macos/commit/0bca1e0))
* prevent macos restoring the app (conflict with login items) ([62037a0](https://github.com/lwouis/alt-tab-macos/commit/62037a0))
* rare crash at launch if the app previously crashed ([69168f9](https://github.com/lwouis/alt-tab-macos/commit/69168f9))
* rare crash when the os doesn't return the main screen uuid ([2232f81](https://github.com/lwouis/alt-tab-macos/commit/2232f81))


### Features

* update korean localization ([d31e369](https://github.com/lwouis/alt-tab-macos/commit/d31e369))

# [4.10.0](https://github.com/lwouis/alt-tab-macos/compare/v4.9.1...v4.10.0) (2020-07-28)


### Features

* preference to hide colored circles on mouse hover (closes [#460](https://github.com/lwouis/alt-tab-macos/issues/460)) ([02776f0](https://github.com/lwouis/alt-tab-macos/commit/02776f0))
* preference to hide windows status icons (closes [#467](https://github.com/lwouis/alt-tab-macos/issues/467)) ([d305eb8](https://github.com/lwouis/alt-tab-macos/commit/d305eb8))
* update korean, chinese, russian localizations ([685bd10](https://github.com/lwouis/alt-tab-macos/commit/685bd10))

## [4.9.1](https://github.com/lwouis/alt-tab-macos/compare/v4.9.0...v4.9.1) (2020-07-22)


### Bug Fixes

* occasional crash when updating some preferences ([3d36cb7](https://github.com/lwouis/alt-tab-macos/commit/3d36cb7))

# [4.9.0](https://github.com/lwouis/alt-tab-macos/compare/v4.8.1...v4.9.0) (2020-07-22)


### Bug Fixes

* dr.betotte app wasn't listed in alt-tab (closes [#455](https://github.com/lwouis/alt-tab-macos/issues/455)) ([85b5ee7](https://github.com/lwouis/alt-tab-macos/commit/85b5ee7))
* occasional crash when focusing a window (closes [#459](https://github.com/lwouis/alt-tab-macos/issues/459)) ([19be9a1](https://github.com/lwouis/alt-tab-macos/commit/19be9a1))
* occasional crash when no there are no open window (closes [#459](https://github.com/lwouis/alt-tab-macos/issues/459)) ([6df92da](https://github.com/lwouis/alt-tab-macos/commit/6df92da))


### Features

* after a crash, suggest to send a crash report (closes [#132](https://github.com/lwouis/alt-tab-macos/issues/132)) ([a8970dd](https://github.com/lwouis/alt-tab-macos/commit/a8970dd))

## [4.8.1](https://github.com/lwouis/alt-tab-macos/compare/v4.8.0...v4.8.1) (2020-07-21)


### Bug Fixes

* rare crash when clicking while alt-tab is open ([#439](https://github.com/lwouis/alt-tab-macos/issues/439)) ([b3c6031](https://github.com/lwouis/alt-tab-macos/commit/b3c6031))

# [4.8.0](https://github.com/lwouis/alt-tab-macos/compare/v4.7.2...v4.8.0) (2020-07-21)


### Features

* hovering thumbnails reveals icons to close/min/max windows ([#9](https://github.com/lwouis/alt-tab-macos/issues/9)) ([11e0d2a](https://github.com/lwouis/alt-tab-macos/commit/11e0d2a))

## [4.7.2](https://github.com/lwouis/alt-tab-macos/compare/v4.7.1...v4.7.2) (2020-07-21)


### Bug Fixes

* dvdfab app wasn't listed in alt-tab (closes [#450](https://github.com/lwouis/alt-tab-macos/issues/450)) ([13e41ab](https://github.com/lwouis/alt-tab-macos/commit/13e41ab))

## [4.7.1](https://github.com/lwouis/alt-tab-macos/compare/v4.7.0...v4.7.1) (2020-07-21)


### Bug Fixes

* sanguosha game wasn't listed in alt-tab (closes [#441](https://github.com/lwouis/alt-tab-macos/issues/441)) ([e67b075](https://github.com/lwouis/alt-tab-macos/commit/e67b075))

# [4.7.0](https://github.com/lwouis/alt-tab-macos/compare/v4.6.0...v4.7.0) (2020-07-20)


### Bug Fixes

* android emulator not showing because of blacklist (closes [#444](https://github.com/lwouis/alt-tab-macos/issues/444)) ([60bf384](https://github.com/lwouis/alt-tab-macos/commit/60bf384))


### Features

* add second shortcut to active the app (closes [#237](https://github.com/lwouis/alt-tab-macos/issues/237)) ([a6285ba](https://github.com/lwouis/alt-tab-macos/commit/a6285ba))
* default layout based on screen aspect ratio (closes [#436](https://github.com/lwouis/alt-tab-macos/issues/436)) ([11fb95d](https://github.com/lwouis/alt-tab-macos/commit/11fb95d))
* easier back-cycling shortcut ([#420](https://github.com/lwouis/alt-tab-macos/issues/420)) ([a31544d](https://github.com/lwouis/alt-tab-macos/commit/a31544d))
* updated german and hungarian localizations ([7a23046](https://github.com/lwouis/alt-tab-macos/commit/7a23046))

# [4.6.0](https://github.com/lwouis/alt-tab-macos/compare/v4.5.0...v4.6.0) (2020-07-20)


### Features

* add indonesian and luxembourgish localizations ([d3432a9](https://github.com/lwouis/alt-tab-macos/commit/d3432a9))
* updating german, french, korean localizations ([53a2f5f](https://github.com/lwouis/alt-tab-macos/commit/53a2f5f))

# [4.5.0](https://github.com/lwouis/alt-tab-macos/compare/v4.4.0...v4.5.0) (2020-07-17)


### Bug Fixes

* alt-tab preferences panel was sometimes not listed ([e25716b](https://github.com/lwouis/alt-tab-macos/commit/e25716b))
* launch crash on macOS versions < 10.15 ([d817545](https://github.com/lwouis/alt-tab-macos/commit/d817545))


### Features

* allow backlisting apps, with 2 different types of blacklist ([d32951f](https://github.com/lwouis/alt-tab-macos/commit/d32951f)), closes [#239](https://github.com/lwouis/alt-tab-macos/issues/239)

# [4.4.0](https://github.com/lwouis/alt-tab-macos/compare/v4.3.0...v4.4.0) (2020-07-15)


### Bug Fixes

* update chinese localization ([95d75d3](https://github.com/lwouis/alt-tab-macos/commit/95d75d3))


### Features

* add preference for title truncation style ([3bddd7e](https://github.com/lwouis/alt-tab-macos/commit/3bddd7e))
* click outside alt-tab main window to cancel (closes [#341](https://github.com/lwouis/alt-tab-macos/issues/341)) ([1fc620d](https://github.com/lwouis/alt-tab-macos/commit/1fc620d))

# [4.3.0](https://github.com/lwouis/alt-tab-macos/compare/v4.2.0...v4.3.0) (2020-07-14)


### Features

* better system permissions onboarding (closes [#127](https://github.com/lwouis/alt-tab-macos/issues/127)) ([6ef0a6f](https://github.com/lwouis/alt-tab-macos/commit/6ef0a6f))

# [4.2.0](https://github.com/lwouis/alt-tab-macos/compare/v4.1.7...v4.2.0) (2020-07-11)


### Bug Fixes

* further chinese and french localizations ([99668ae](https://github.com/lwouis/alt-tab-macos/commit/99668ae))
* further chinese/korean/french localizations ([d638eb0](https://github.com/lwouis/alt-tab-macos/commit/d638eb0))


### Features

* add preference to hide menubar icon (closes [#103](https://github.com/lwouis/alt-tab-macos/issues/103)) ([6635117](https://github.com/lwouis/alt-tab-macos/commit/6635117))

## [4.1.7](https://github.com/lwouis/alt-tab-macos/compare/v4.1.6...v4.1.7) (2020-07-10)


### Bug Fixes

* on some machines, deadlocks happened at launch ([e2181c8](https://github.com/lwouis/alt-tab-macos/commit/e2181c8))
* reduce cpu utilization at launch ([5306a4b](https://github.com/lwouis/alt-tab-macos/commit/5306a4b))
* typo in chinese localization ([363ed3d](https://github.com/lwouis/alt-tab-macos/commit/363ed3d))

## [4.1.6](https://github.com/lwouis/alt-tab-macos/compare/v4.1.5...v4.1.6) (2020-07-08)


### Bug Fixes

* potential crash in very rare data-race scenario ([4ff5d89](https://github.com/lwouis/alt-tab-macos/commit/4ff5d89))
* tabs would sometimes show as separate windows (closes [#383](https://github.com/lwouis/alt-tab-macos/issues/383)) ([c03d48f](https://github.com/lwouis/alt-tab-macos/commit/c03d48f))
* update korean localization ([ecdeed8](https://github.com/lwouis/alt-tab-macos/commit/ecdeed8))

## [4.1.5](https://github.com/lwouis/alt-tab-macos/compare/v4.1.4...v4.1.5) (2020-07-03)


### Bug Fixes

* improve perf by only refreshing shown thumbnails (closes [#393](https://github.com/lwouis/alt-tab-macos/issues/393)) ([3c453f9](https://github.com/lwouis/alt-tab-macos/commit/3c453f9))
* update dutch and russian localizations ([ff96bc3](https://github.com/lwouis/alt-tab-macos/commit/ff96bc3))

## [4.1.4](https://github.com/lwouis/alt-tab-macos/compare/v4.1.3...v4.1.4) (2020-06-23)

## [4.1.3](https://github.com/lwouis/alt-tab-macos/compare/v4.1.2...v4.1.3) (2020-06-16)


### Bug Fixes

* rare crash if shortcut is pressed early during launch ([265c7a6](https://github.com/lwouis/alt-tab-macos/commit/265c7a6))
* show android emulator window (closes [#376](https://github.com/lwouis/alt-tab-macos/issues/376)) ([bb8a5ce](https://github.com/lwouis/alt-tab-macos/commit/bb8a5ce))
* show windows of apps without a bundle (e.g. not .app) ([fd0623a](https://github.com/lwouis/alt-tab-macos/commit/fd0623a))

## [4.1.2](https://github.com/lwouis/alt-tab-macos/compare/v4.1.1...v4.1.2) (2020-06-09)


### Bug Fixes

* releasing the shortcut works even with other modifiers pressed ([23b17c1](https://github.com/lwouis/alt-tab-macos/commit/23b17c1)), closes [#230](https://github.com/lwouis/alt-tab-macos/issues/230)

## [4.1.1](https://github.com/lwouis/alt-tab-macos/compare/v4.1.0...v4.1.1) (2020-06-07)


### Bug Fixes

* mouse hover during scroll bounce produced visual jank (closes [#259](https://github.com/lwouis/alt-tab-macos/issues/259)) ([c7e5daa](https://github.com/lwouis/alt-tab-macos/commit/c7e5daa))
* sometimes switching apps wouldn't be noticed ([96a6ae6](https://github.com/lwouis/alt-tab-macos/commit/96a6ae6))
* update korean localizations ([cec2756](https://github.com/lwouis/alt-tab-macos/commit/cec2756))

# [4.1.0](https://github.com/lwouis/alt-tab-macos/compare/v4.0.1...v4.1.0) (2020-05-28)


### Features

* prevent users from quitting finder (closes [#362](https://github.com/lwouis/alt-tab-macos/issues/362)) ([a1338c0](https://github.com/lwouis/alt-tab-macos/commit/a1338c0))

## [4.0.1](https://github.com/lwouis/alt-tab-macos/compare/v4.0.0...v4.0.1) (2020-05-28)


### Bug Fixes

* firefox fullscreen videos are not listed (closes [#360](https://github.com/lwouis/alt-tab-macos/issues/360)) ([ce63367](https://github.com/lwouis/alt-tab-macos/commit/ce63367))
* updated chinese/french/russian localizations ([797ed42](https://github.com/lwouis/alt-tab-macos/commit/797ed42))

# [4.0.0](https://github.com/lwouis/alt-tab-macos/compare/v3.24.1...v4.0.0) (2020-05-25)


### Bug Fixes

* center-aligned layout was sometimes broken (closes [#352](https://github.com/lwouis/alt-tab-macos/issues/352)) ([e25dcd2](https://github.com/lwouis/alt-tab-macos/commit/e25dcd2))
* crash in some rare scenarios with lots of windows ([a859347](https://github.com/lwouis/alt-tab-macos/commit/a859347))
* potentially fix shortcuts not working sometimes ([8d833f5](https://github.com/lwouis/alt-tab-macos/commit/8d833f5))
* rework all multi-threading to handle complex scenarios ([d144476](https://github.com/lwouis/alt-tab-macos/commit/d144476)), closes [#348](https://github.com/lwouis/alt-tab-macos/issues/348) [#157](https://github.com/lwouis/alt-tab-macos/issues/157) [#342](https://github.com/lwouis/alt-tab-macos/issues/342) [#93](https://github.com/lwouis/alt-tab-macos/issues/93)
* sometimes windows titles use the wrong font ([fa1095e](https://github.com/lwouis/alt-tab-macos/commit/fa1095e))
* update japanese localization ([acef0b2](https://github.com/lwouis/alt-tab-macos/commit/acef0b2))


### BREAKING CHANGES

* this rework should fix all sorts of issues when OS events happen in parallel: new windows, new apps, user shortcuts, etc. Here are example of use-cases that should work great now, without, and very quickly:

* AltTab is open and an app/window is launched/quit
* A window is minimized/deminimized, and while the animation is playing, the user invokes AltTab
* An app starts and takes a long time to boot (e.g. Gimp)
* An app becomes unresponsive, yet AltTab is unaffected and remains interactive while still processing the state of the window while its parent app finally stops being frozen

## [3.24.1](https://github.com/lwouis/alt-tab-macos/compare/v3.24.0...v3.24.1) (2020-05-22)


### Bug Fixes

* localized release notes were not working ([125da44](https://github.com/lwouis/alt-tab-macos/commit/125da44))

# [3.24.0](https://github.com/lwouis/alt-tab-macos/compare/v3.23.2...v3.24.0) (2020-05-21)


### Bug Fixes

* don't freeze when invoked while unity is recompiling (closes [#342](https://github.com/lwouis/alt-tab-macos/issues/342)) ([41cb701](https://github.com/lwouis/alt-tab-macos/commit/41cb701)), closes [#292](https://github.com/lwouis/alt-tab-macos/issues/292) [#200](https://github.com/lwouis/alt-tab-macos/issues/200)
* don't freeze when sending a command to an frozen window ([408b800](https://github.com/lwouis/alt-tab-macos/commit/408b800))
* show windows which are opened in fullscreen (closes [#335](https://github.com/lwouis/alt-tab-macos/issues/335)) ([2674c8f](https://github.com/lwouis/alt-tab-macos/commit/2674c8f))


### Features

* show indicator for fullscreen windows ([0138cd1](https://github.com/lwouis/alt-tab-macos/commit/0138cd1))

## [3.23.2](https://github.com/lwouis/alt-tab-macos/compare/v3.23.1...v3.23.2) (2020-05-21)


### Bug Fixes

* better handle apps that start as background processes ([49816ab](https://github.com/lwouis/alt-tab-macos/commit/49816ab))
* update contributors ([b303d2f](https://github.com/lwouis/alt-tab-macos/commit/b303d2f))
* update german localization ([b047443](https://github.com/lwouis/alt-tab-macos/commit/b047443))

## [3.23.1](https://github.com/lwouis/alt-tab-macos/compare/v3.23.0...v3.23.1) (2020-05-13)


### Bug Fixes

* duplicate windows shown after login (closes [#292](https://github.com/lwouis/alt-tab-macos/issues/292)) ([804b7e2](https://github.com/lwouis/alt-tab-macos/commit/804b7e2))
* update russian, chinese, chinese (tw) localizations ([bf97f53](https://github.com/lwouis/alt-tab-macos/commit/bf97f53))

# [3.23.0](https://github.com/lwouis/alt-tab-macos/compare/v3.22.6...v3.23.0) (2020-05-11)


### Bug Fixes

* update korean localization ([34e6877](https://github.com/lwouis/alt-tab-macos/commit/34e6877))


### Features

* localize release notes using google translate ([1927f2c](https://github.com/lwouis/alt-tab-macos/commit/1927f2c))

## [3.22.6](https://github.com/lwouis/alt-tab-macos/compare/v3.22.5...v3.22.6) (2020-05-10)


### Bug Fixes

* exotic scenario where the os reports no main screen (closes [#330](https://github.com/lwouis/alt-tab-macos/issues/330)) ([f83ef40](https://github.com/lwouis/alt-tab-macos/commit/f83ef40))

## [3.22.5](https://github.com/lwouis/alt-tab-macos/compare/v3.22.4...v3.22.5) (2020-05-10)


### Bug Fixes

* implement a 2min timeout for unresponsive apps (closes [#274](https://github.com/lwouis/alt-tab-macos/issues/274)) ([7ab7c82](https://github.com/lwouis/alt-tab-macos/commit/7ab7c82))

## [3.22.4](https://github.com/lwouis/alt-tab-macos/compare/v3.22.3...v3.22.4) (2020-05-10)


### Bug Fixes

* update korean localization ([0b61bce](https://github.com/lwouis/alt-tab-macos/commit/0b61bce))
* workaround some odd bug that's breaking protege.app (closes [#314](https://github.com/lwouis/alt-tab-macos/issues/314)) ([8f4efdf](https://github.com/lwouis/alt-tab-macos/commit/8f4efdf))

## [3.22.3](https://github.com/lwouis/alt-tab-macos/compare/v3.22.2...v3.22.3) (2020-05-10)

## [3.22.2](https://github.com/lwouis/alt-tab-macos/compare/v3.22.1...v3.22.2) (2020-05-10)


### Bug Fixes

* auto-update was pointing to the wrong release notes url ([b5f1499](https://github.com/lwouis/alt-tab-macos/commit/b5f1499))
* crash on launch trying to open a file that was renamed ([52b8666](https://github.com/lwouis/alt-tab-macos/commit/52b8666))

## [3.22.1](https://github.com/lwouis/alt-tab-macos/compare/v3.22.0...v3.22.1) (2020-05-10)

# [3.22.0](https://github.com/lwouis/alt-tab-macos/compare/v3.21.2...v3.22.0) (2020-05-10)


### Features

* add preference: fade out animation for the main ui (closes [#234](https://github.com/lwouis/alt-tab-macos/issues/234)) ([ee30725](https://github.com/lwouis/alt-tab-macos/commit/ee30725))

## [3.21.2](https://github.com/lwouis/alt-tab-macos/compare/v3.21.1...v3.21.2) (2020-05-08)


### Bug Fixes

* improved chinese localization ([3269a26](https://github.com/lwouis/alt-tab-macos/commit/3269a26))
* update cocoapod for letsmove ([0068dd2](https://github.com/lwouis/alt-tab-macos/commit/0068dd2))

## [3.21.1](https://github.com/lwouis/alt-tab-macos/compare/v3.21.0...v3.21.1) (2020-05-08)


### Bug Fixes

* arrow keys shortcuts for right-to-left languages ([33b7094](https://github.com/lwouis/alt-tab-macos/commit/33b7094))
* thumbnails layout issues (especially in right-to-left languages) ([f3cb544](https://github.com/lwouis/alt-tab-macos/commit/f3cb544))

# [3.21.0](https://github.com/lwouis/alt-tab-macos/compare/v3.20.0...v3.21.0) (2020-05-07)


### Features

* localize the main ui for right-to-left languages ([c9e72ee](https://github.com/lwouis/alt-tab-macos/commit/c9e72ee))

# [3.20.0](https://github.com/lwouis/alt-tab-macos/compare/v3.19.2...v3.20.0) (2020-05-07)


### Bug Fixes

* thumbnails have a minimum width to help with tall windows ([a60750c](https://github.com/lwouis/alt-tab-macos/commit/a60750c))


### Features

* smarter padding around thumbnails (closes [#126](https://github.com/lwouis/alt-tab-macos/issues/126)) ([a94582f](https://github.com/lwouis/alt-tab-macos/commit/a94582f))

## [3.19.2](https://github.com/lwouis/alt-tab-macos/compare/v3.19.1...v3.19.2) (2020-05-07)


### Bug Fixes

* would not correctly show windows/tabs from other spaces ([873f985](https://github.com/lwouis/alt-tab-macos/commit/873f985))

## [3.19.1](https://github.com/lwouis/alt-tab-macos/compare/v3.19.0...v3.19.1) (2020-05-06)


### Bug Fixes

* fast shortcut press would fail to switch windows ([2ee5eb5](https://github.com/lwouis/alt-tab-macos/commit/2ee5eb5))

# [3.19.0](https://github.com/lwouis/alt-tab-macos/compare/v3.18.0...v3.19.0) (2020-05-06)


### Bug Fixes

* don't display invalid windows (may fix [#292](https://github.com/lwouis/alt-tab-macos/issues/292) [#200](https://github.com/lwouis/alt-tab-macos/issues/200)) ([1bca012](https://github.com/lwouis/alt-tab-macos/commit/1bca012))
* don't display tabbed windows (closes [#258](https://github.com/lwouis/alt-tab-macos/issues/258)) ([8419ad9](https://github.com/lwouis/alt-tab-macos/commit/8419ad9))
* update french localization ([445980a](https://github.com/lwouis/alt-tab-macos/commit/445980a))


### Features

* add dutch localization ([b8eb0b4](https://github.com/lwouis/alt-tab-macos/commit/b8eb0b4))
* add preference: show standard tabs as windows ([3a11cc6](https://github.com/lwouis/alt-tab-macos/commit/3a11cc6))

# [3.18.0](https://github.com/lwouis/alt-tab-macos/compare/v3.17.2...v3.18.0) (2020-05-05)


### Bug Fixes

* activate shortcuts without updating their userdefaults ([6aad3e7](https://github.com/lwouis/alt-tab-macos/commit/6aad3e7))
* can close feedback window with escape key ([05fb4a2](https://github.com/lwouis/alt-tab-macos/commit/05fb4a2))
* correctly display right-to-left languages ([89f2df4](https://github.com/lwouis/alt-tab-macos/commit/89f2df4))
* more robust preference migrations (closes [#220](https://github.com/lwouis/alt-tab-macos/issues/220)) ([bf857e8](https://github.com/lwouis/alt-tab-macos/commit/bf857e8))


### Features

* add arabic localization ([0a1bb6e](https://github.com/lwouis/alt-tab-macos/commit/0a1bb6e))
* check for updates weekly instead of daily ([02920a7](https://github.com/lwouis/alt-tab-macos/commit/02920a7)), closes [#295](https://github.com/lwouis/alt-tab-macos/issues/295)
* update german localization ([1925777](https://github.com/lwouis/alt-tab-macos/commit/1925777))

## [3.17.2](https://github.com/lwouis/alt-tab-macos/compare/v3.17.1...v3.17.2) (2020-05-05)


### Bug Fixes

* fit preferences tabs on small screens ([6096ce5](https://github.com/lwouis/alt-tab-macos/commit/6096ce5))

## [3.17.1](https://github.com/lwouis/alt-tab-macos/compare/v3.17.0...v3.17.1) (2020-04-29)


### Bug Fixes

* plug some minor memory leaks ([0de7a55](https://github.com/lwouis/alt-tab-macos/commit/0de7a55))
* use windows nominal resolution for better performance ([a7cc3be](https://github.com/lwouis/alt-tab-macos/commit/a7cc3be))

# [3.17.0](https://github.com/lwouis/alt-tab-macos/compare/v3.16.3...v3.17.0) (2020-04-27)


### Bug Fixes

* shift key + scroll should scroll the ui ([d64a6a5](https://github.com/lwouis/alt-tab-macos/commit/d64a6a5))
* update russian localization ([942c4d7](https://github.com/lwouis/alt-tab-macos/commit/942c4d7))


### Features

* navigate with up/down arrow keys (closes [#270](https://github.com/lwouis/alt-tab-macos/issues/270)) ([cc61ed4](https://github.com/lwouis/alt-tab-macos/commit/cc61ed4))

## [3.16.3](https://github.com/lwouis/alt-tab-macos/compare/v3.16.2...v3.16.3) (2020-04-25)


### Bug Fixes

* suggest moving the app to the global applications folder ([91e31da](https://github.com/lwouis/alt-tab-macos/commit/91e31da)), closes [#267](https://github.com/lwouis/alt-tab-macos/issues/267)

## [3.16.2](https://github.com/lwouis/alt-tab-macos/compare/v3.16.1...v3.16.2) (2020-04-25)


### Bug Fixes

* removing accessibility permission breaks keyboard inputs ([0da3d33](https://github.com/lwouis/alt-tab-macos/commit/0da3d33)), closes [#269](https://github.com/lwouis/alt-tab-macos/issues/269)

## [3.16.1](https://github.com/lwouis/alt-tab-macos/compare/v3.16.0...v3.16.1) (2020-04-24)


### Bug Fixes

* app could sometimes crash on closing the ui ([61db5b4](https://github.com/lwouis/alt-tab-macos/commit/61db5b4))

# [3.16.0](https://github.com/lwouis/alt-tab-macos/compare/v3.15.0...v3.16.0) (2020-04-24)


### Features

* added russian localization ([f0971c2](https://github.com/lwouis/alt-tab-macos/commit/f0971c2))

# [3.15.0](https://github.com/lwouis/alt-tab-macos/compare/v3.14.0...v3.15.0) (2020-04-23)


### Bug Fixes

* debug profile spaces count was incorrect ([e98d401](https://github.com/lwouis/alt-tab-macos/commit/e98d401))
* handle windows assigned to all spaces (closes [#266](https://github.com/lwouis/alt-tab-macos/issues/266)) ([e35fe6b](https://github.com/lwouis/alt-tab-macos/commit/e35fe6b))


### Features

* add warning for email-less feedback ([1acd918](https://github.com/lwouis/alt-tab-macos/commit/1acd918))

# [3.14.0](https://github.com/lwouis/alt-tab-macos/compare/v3.13.0...v3.14.0) (2020-04-22)


### Features

* add portuguese and finish japanese localizations ([d1ab72f](https://github.com/lwouis/alt-tab-macos/commit/d1ab72f))
* update all localizations ([a2dd46d](https://github.com/lwouis/alt-tab-macos/commit/a2dd46d))

# [3.13.0](https://github.com/lwouis/alt-tab-macos/compare/v3.12.0...v3.13.0) (2020-04-21)


### Bug Fixes

* showed rows with 1 too-few windows sometimes (see [#256](https://github.com/lwouis/alt-tab-macos/issues/256)) ([0eac086](https://github.com/lwouis/alt-tab-macos/commit/0eac086))


### Features

* add hungarian localization ([ba7b5d3](https://github.com/lwouis/alt-tab-macos/commit/ba7b5d3))

# [3.12.0](https://github.com/lwouis/alt-tab-macos/compare/v3.11.0...v3.12.0) (2020-04-20)


### Bug Fixes

* updated localizations ([eec6912](https://github.com/lwouis/alt-tab-macos/commit/eec6912))


### Features

* collapsible debug profile in feedback report ([d6960d5](https://github.com/lwouis/alt-tab-macos/commit/d6960d5))

# [3.11.0](https://github.com/lwouis/alt-tab-macos/compare/v3.10.0...v3.11.0) (2020-04-19)


### Features

* add app quit shortcut ([7a94e4a](https://github.com/lwouis/alt-tab-macos/commit/7a94e4a))
* add close window shortcut ([8da8af8](https://github.com/lwouis/alt-tab-macos/commit/8da8af8))
* add hide/show app shortcut ([6be1c2c](https://github.com/lwouis/alt-tab-macos/commit/6be1c2c))
* add min/demin window shortcut ([2b752ef](https://github.com/lwouis/alt-tab-macos/commit/2b752ef))
* add preference: display the ui on screen including menu bar ([156957c](https://github.com/lwouis/alt-tab-macos/commit/156957c))
* faster initial display of some windows ([3286570](https://github.com/lwouis/alt-tab-macos/commit/3286570))

# [3.10.0](https://github.com/lwouis/alt-tab-macos/compare/v3.9.1...v3.10.0) (2020-04-19)


### Bug Fixes

* issues with preferences window on mojave (closes [#233](https://github.com/lwouis/alt-tab-macos/issues/233)) ([8d7f121](https://github.com/lwouis/alt-tab-macos/commit/8d7f121))


### Features

* trim fonticon to reduce app size (closes [#168](https://github.com/lwouis/alt-tab-macos/issues/168)) ([0d27cf7](https://github.com/lwouis/alt-tab-macos/commit/0d27cf7))

## [3.9.1](https://github.com/lwouis/alt-tab-macos/compare/v3.9.0...v3.9.1) (2020-04-18)


### Bug Fixes

* show windows from steam app (closes [#236](https://github.com/lwouis/alt-tab-macos/issues/236)) ([d17c9d5](https://github.com/lwouis/alt-tab-macos/commit/d17c9d5))
* thumbnails layout was wrong sometimes ([06c6f48](https://github.com/lwouis/alt-tab-macos/commit/06c6f48))

# [3.9.0](https://github.com/lwouis/alt-tab-macos/compare/v3.8.0...v3.9.0) (2020-04-18)


### Features

* allow shortcuts to be modifiers-only (closes [#243](https://github.com/lwouis/alt-tab-macos/issues/243)) ([d4be095](https://github.com/lwouis/alt-tab-macos/commit/d4be095))

# [3.8.0](https://github.com/lwouis/alt-tab-macos/compare/v3.7.3...v3.8.0) (2020-04-18)


### Bug Fixes

* clearer debug profile (i.e. no "optional") ([e2b94f7](https://github.com/lwouis/alt-tab-macos/commit/e2b94f7))


### Features

* add acknowledgments for third-party software (closes [#177](https://github.com/lwouis/alt-tab-macos/issues/177)) ([9398cff](https://github.com/lwouis/alt-tab-macos/commit/9398cff))
* remove runtime checker for better perf ([e9ce575](https://github.com/lwouis/alt-tab-macos/commit/e9ce575))

## [3.7.3](https://github.com/lwouis/alt-tab-macos/compare/v3.7.2...v3.7.3) (2020-04-09)


### Bug Fixes

* typos in korean and chinese labels (closes [#228](https://github.com/lwouis/alt-tab-macos/issues/228)) ([c655675](https://github.com/lwouis/alt-tab-macos/commit/c655675))

## [3.7.2](https://github.com/lwouis/alt-tab-macos/compare/v3.7.1...v3.7.2) (2020-04-09)


### Bug Fixes

* scrollbar works with all system preferences options (closes [#196](https://github.com/lwouis/alt-tab-macos/issues/196)) ([3289d3a](https://github.com/lwouis/alt-tab-macos/commit/3289d3a))
* some preferences were inactive but appeared active ([51ad28d](https://github.com/lwouis/alt-tab-macos/commit/51ad28d))

## [3.7.1](https://github.com/lwouis/alt-tab-macos/compare/v3.7.0...v3.7.1) (2020-04-08)


### Bug Fixes

* better handling of preference migration (up/down) ([078c359](https://github.com/lwouis/alt-tab-macos/commit/078c359))
* hiding window should be on main thread ([767f900](https://github.com/lwouis/alt-tab-macos/commit/767f900))
* scrollbar only shows on scroll (closes [#196](https://github.com/lwouis/alt-tab-macos/issues/196)) ([c2abff0](https://github.com/lwouis/alt-tab-macos/commit/c2abff0))
* updated localizations, especially Spanish ([bd92828](https://github.com/lwouis/alt-tab-macos/commit/bd92828))

# [3.7.0](https://github.com/lwouis/alt-tab-macos/compare/v3.6.2...v3.7.0) (2020-04-08)


### Bug Fixes

* avoid crash when upgrading due to old preferences (closes [#222](https://github.com/lwouis/alt-tab-macos/issues/222)) ([66a2bd8](https://github.com/lwouis/alt-tab-macos/commit/66a2bd8))


### Features

* add dark-mode in the debug profile on reports ([a54eb77](https://github.com/lwouis/alt-tab-macos/commit/a54eb77))

## [3.6.2](https://github.com/lwouis/alt-tab-macos/compare/v3.6.1...v3.6.2) (2020-04-08)


### Bug Fixes

* avoid text flickering on main ui (closes [#197](https://github.com/lwouis/alt-tab-macos/issues/197)) ([4eb9db0](https://github.com/lwouis/alt-tab-macos/commit/4eb9db0))
* dropdown preferences crashed in non-english (closes [#217](https://github.com/lwouis/alt-tab-macos/issues/217)) ([5447d5f](https://github.com/lwouis/alt-tab-macos/commit/5447d5f))

## [3.6.1](https://github.com/lwouis/alt-tab-macos/compare/v3.6.0...v3.6.1) (2020-04-08)


### Bug Fixes

* prevent hold/release shortcut from being empty ([1158a32](https://github.com/lwouis/alt-tab-macos/commit/1158a32))

# [3.6.0](https://github.com/lwouis/alt-tab-macos/compare/v3.5.0...v3.6.0) (2020-04-07)


### Bug Fixes

* focus correct window after app quits (see [#213](https://github.com/lwouis/alt-tab-macos/issues/213)) ([7f27cb9](https://github.com/lwouis/alt-tab-macos/commit/7f27cb9))
* workaround the bug in parsec (closes [#206](https://github.com/lwouis/alt-tab-macos/issues/206)) ([59c6afc](https://github.com/lwouis/alt-tab-macos/commit/59c6afc))


### Features

* let users disable shortcuts ([5b03415](https://github.com/lwouis/alt-tab-macos/commit/5b03415))
* updated localization for 7 languages ([bc2a38b](https://github.com/lwouis/alt-tab-macos/commit/bc2a38b))

# [3.5.0](https://github.com/lwouis/alt-tab-macos/compare/v3.4.1...v3.5.0) (2020-04-05)


### Bug Fixes

* **readme:** sort language list and add Finnish ([42dbd30](https://github.com/lwouis/alt-tab-macos/commit/42dbd30))


### Features

* **i18n:** add Finnish localization ([770d472](https://github.com/lwouis/alt-tab-macos/commit/770d472))

## [3.4.1](https://github.com/lwouis/alt-tab-macos/compare/v3.4.0...v3.4.1) (2020-04-05)

# [3.4.0](https://github.com/lwouis/alt-tab-macos/compare/v3.3.3...v3.4.0) (2020-04-03)


### Features

* updated some localizations ([b38d688](https://github.com/lwouis/alt-tab-macos/commit/b38d688))

## [3.3.3](https://github.com/lwouis/alt-tab-macos/compare/v3.3.2...v3.3.3) (2020-04-03)


### Bug Fixes

* "show all screens" pref was not respected (closes [#204](https://github.com/lwouis/alt-tab-macos/issues/204)) ([d4c13c4](https://github.com/lwouis/alt-tab-macos/commit/d4c13c4))

## [3.3.2](https://github.com/lwouis/alt-tab-macos/compare/v3.3.1...v3.3.2) (2020-04-02)


### Bug Fixes

* crashed if an invalid login item existed (closes [#202](https://github.com/lwouis/alt-tab-macos/issues/202)) ([48d5d63](https://github.com/lwouis/alt-tab-macos/commit/48d5d63))

## [3.3.1](https://github.com/lwouis/alt-tab-macos/compare/v3.3.0...v3.3.1) (2020-04-02)


### Bug Fixes

* blind fix trying to guess root cause of [#202](https://github.com/lwouis/alt-tab-macos/issues/202) ([fb4fe11](https://github.com/lwouis/alt-tab-macos/commit/fb4fe11))
* checkboxes preferences were unchecked initially ([b091282](https://github.com/lwouis/alt-tab-macos/commit/b091282))

# [3.3.0](https://github.com/lwouis/alt-tab-macos/compare/v3.2.1...v3.3.0) (2020-04-02)


### Bug Fixes

* .strings encoding should be utf-8 ([7109b08](https://github.com/lwouis/alt-tab-macos/commit/7109b08))
* avoid having multiple login items ([65816a2](https://github.com/lwouis/alt-tab-macos/commit/65816a2))
* preferences would not be live (closes [#188](https://github.com/lwouis/alt-tab-macos/issues/188)) ([d5b74a1](https://github.com/lwouis/alt-tab-macos/commit/d5b74a1)), closes [#194](https://github.com/lwouis/alt-tab-macos/issues/194)
* simpler/better window focus ([574a640](https://github.com/lwouis/alt-tab-macos/commit/574a640))


### Features

* localized in 5 new languages ([48bb3df](https://github.com/lwouis/alt-tab-macos/commit/48bb3df))
* more flexible shortcuts (closes [#72](https://github.com/lwouis/alt-tab-macos/issues/72)) ([5eade75](https://github.com/lwouis/alt-tab-macos/commit/5eade75)), closes [#50](https://github.com/lwouis/alt-tab-macos/issues/50) [#125](https://github.com/lwouis/alt-tab-macos/issues/125) [#133](https://github.com/lwouis/alt-tab-macos/issues/133)

## [3.2.1](https://github.com/lwouis/alt-tab-macos/compare/v3.2.0...v3.2.1) (2020-03-25)


### Bug Fixes

* chrome shortcuts apps don't show up (closes [#185](https://github.com/lwouis/alt-tab-macos/issues/185)) ([0b35ebf](https://github.com/lwouis/alt-tab-macos/commit/0b35ebf))
* don't hang waiting for faulty apps to reply (closes [#182](https://github.com/lwouis/alt-tab-macos/issues/182)) ([246cf69](https://github.com/lwouis/alt-tab-macos/commit/246cf69))
* hidden apps windows don't show hidden icon ([6e190bf](https://github.com/lwouis/alt-tab-macos/commit/6e190bf))

# [3.2.0](https://github.com/lwouis/alt-tab-macos/compare/v3.1.3...v3.2.0) (2020-03-24)


### Bug Fixes

* refresh both thumbnails on focus switch in bg ([4fee590](https://github.com/lwouis/alt-tab-macos/commit/4fee590))
* things in background properly reflect in ui ([fdf1524](https://github.com/lwouis/alt-tab-macos/commit/fdf1524))


### Features

* faster ui (closes [#171](https://github.com/lwouis/alt-tab-macos/issues/171), closes [#128](https://github.com/lwouis/alt-tab-macos/issues/128), closes [#89](https://github.com/lwouis/alt-tab-macos/issues/89)) ([311beef](https://github.com/lwouis/alt-tab-macos/commit/311beef))

## [3.1.3](https://github.com/lwouis/alt-tab-macos/compare/v3.1.2...v3.1.3) (2020-03-12)

## [3.1.2](https://github.com/lwouis/alt-tab-macos/compare/v3.1.1...v3.1.2) (2020-03-12)


### Bug Fixes

* send feedback crashed the app on submit (closes [#172](https://github.com/lwouis/alt-tab-macos/issues/172)) ([c34b8a5](https://github.com/lwouis/alt-tab-macos/commit/c34b8a5))

## [3.1.1](https://github.com/lwouis/alt-tab-macos/compare/v3.1.0...v3.1.1) (2020-03-11)


### Bug Fixes

* don't observe daemons to avoid infinite loops (closes [#170](https://github.com/lwouis/alt-tab-macos/issues/170)) ([e40f859](https://github.com/lwouis/alt-tab-macos/commit/e40f859))
* show alt-tab own windows in the thumbnail panel ([6018a53](https://github.com/lwouis/alt-tab-macos/commit/6018a53))

# [3.1.0](https://github.com/lwouis/alt-tab-macos/compare/v3.0.5...v3.1.0) (2020-03-10)


### Bug Fixes

* better subscription retry logic ([3a80cab](https://github.com/lwouis/alt-tab-macos/commit/3a80cab))


### Features

* output plist file as binary for better perf ([29a9f59](https://github.com/lwouis/alt-tab-macos/commit/29a9f59))

## [3.0.5](https://github.com/lwouis/alt-tab-macos/compare/v3.0.4...v3.0.5) (2020-03-10)


### Bug Fixes

* remove script from bundle ([4a8301e](https://github.com/lwouis/alt-tab-macos/commit/4a8301e))

## [3.0.4](https://github.com/lwouis/alt-tab-macos/compare/v3.0.3...v3.0.4) (2020-03-10)

## [3.0.3](https://github.com/lwouis/alt-tab-macos/compare/v3.0.2...v3.0.3) (2020-03-10)

## [3.0.2](https://github.com/lwouis/alt-tab-macos/compare/v3.0.1...v3.0.2) (2020-03-10)

## [3.0.1](https://github.com/lwouis/alt-tab-macos/compare/v3.0.0...v3.0.1) (2020-03-10)

# [3.0.0](https://github.com/lwouis/alt-tab-macos/compare/v2.3.4...v3.0.0) (2020-03-10)


### Bug Fixes

* a title change often means the content has change ([b8d6bc9](https://github.com/lwouis/alt-tab-macos/commit/b8d6bc9))
* add rough downscaling when there are many windows (closes [#69](https://github.com/lwouis/alt-tab-macos/issues/69)) ([ced5ee6](https://github.com/lwouis/alt-tab-macos/commit/ced5ee6))
* added releases link and aligned layout left on tab 3 ([6bb73dc](https://github.com/lwouis/alt-tab-macos/commit/6bb73dc))
* also codesign debug builds ([a5f9911](https://github.com/lwouis/alt-tab-macos/commit/a5f9911))
* app launched while in fullscreen shows first window ([c5cbcdb](https://github.com/lwouis/alt-tab-macos/commit/c5cbcdb)), closes [/github.com/lwouis/alt-tab-macos/pull/114#issuecomment-576384795](https://github.com//github.com/lwouis/alt-tab-macos/pull/114/issues/issuecomment-576384795)
* auto-update preferences sync with os from launch ([b3fb222](https://github.com/lwouis/alt-tab-macos/commit/b3fb222))
* avoid rendering if app is not used ([fdddb0f](https://github.com/lwouis/alt-tab-macos/commit/fdddb0f))
* better float rounding = sharper cell contents ([9a96e49](https://github.com/lwouis/alt-tab-macos/commit/9a96e49))
* better focus/order for preferences (closes [#80](https://github.com/lwouis/alt-tab-macos/issues/80)) ([4a8bdeb](https://github.com/lwouis/alt-tab-macos/commit/4a8bdeb))
* better textareas ([efc9bd3](https://github.com/lwouis/alt-tab-macos/commit/efc9bd3))
* bring back the window delay that regressed with v2 ([bb95e55](https://github.com/lwouis/alt-tab-macos/commit/bb95e55))
* compare correctly since pid can go away when an app dies ([4ded030](https://github.com/lwouis/alt-tab-macos/commit/4ded030))
* compiler warnings ([1faa74c](https://github.com/lwouis/alt-tab-macos/commit/1faa74c))
* cpu and memory leaks (see discussion in [#117](https://github.com/lwouis/alt-tab-macos/issues/117)) ([52626aa](https://github.com/lwouis/alt-tab-macos/commit/52626aa))
* dock being shown was blocking alt-tab ([2826a1b](https://github.com/lwouis/alt-tab-macos/commit/2826a1b))
* don't show floating windows + efficiencies ([3f8e3ea](https://github.com/lwouis/alt-tab-macos/commit/3f8e3ea))
* don't show ui on fast trigger ([f8e1b00](https://github.com/lwouis/alt-tab-macos/commit/f8e1b00))
* don't trigger ui refreshes if the app is not active ([b9a0152](https://github.com/lwouis/alt-tab-macos/commit/b9a0152))
* don't upscale thumbnails of small windows ([0bc7472](https://github.com/lwouis/alt-tab-macos/commit/0bc7472))
* feedback token injected during ci ([effdc5f](https://github.com/lwouis/alt-tab-macos/commit/effdc5f))
* getting sparkle ready for release ([9f1f522](https://github.com/lwouis/alt-tab-macos/commit/9f1f522))
* handle on-all-spaces windows better ([4abe9f3](https://github.com/lwouis/alt-tab-macos/commit/4abe9f3))
* ignore build folder ([a2bb19f](https://github.com/lwouis/alt-tab-macos/commit/a2bb19f))
* ignore trigger shortcuts if mission control is active ([b03b0aa](https://github.com/lwouis/alt-tab-macos/commit/b03b0aa))
* initial discovery when single space was glitching the os ([3cd4b6d](https://github.com/lwouis/alt-tab-macos/commit/3cd4b6d))
* keyboard shortcuts didn't work without a menu ([cf92dc1](https://github.com/lwouis/alt-tab-macos/commit/cf92dc1))
* layout is now correct; also removed layout preferences for now ([a1b5266](https://github.com/lwouis/alt-tab-macos/commit/a1b5266))
* layout regression introduced by eed0353 ([bdc41be](https://github.com/lwouis/alt-tab-macos/commit/bdc41be))
* layout was incorrect resulting in thumbnails clipping ([fd906f4](https://github.com/lwouis/alt-tab-macos/commit/fd906f4))
* letsmove was not active on release builds ([6ac0658](https://github.com/lwouis/alt-tab-macos/commit/6ac0658))
* list temporary AXDialog windows like activity monitor ([51a8838](https://github.com/lwouis/alt-tab-macos/commit/51a8838))
* more robust screen-recording permission check ([ce574a2](https://github.com/lwouis/alt-tab-macos/commit/ce574a2))
* notarization issues ([d125dd3](https://github.com/lwouis/alt-tab-macos/commit/d125dd3))
* observer leak would throw and crash the app sometimes ([9ca28eb](https://github.com/lwouis/alt-tab-macos/commit/9ca28eb))
* only test permissions on the correct os versions ([4612e37](https://github.com/lwouis/alt-tab-macos/commit/4612e37))
* open alt-tab during space transitions (closes [#92](https://github.com/lwouis/alt-tab-macos/issues/92)) ([141562d](https://github.com/lwouis/alt-tab-macos/commit/141562d))
* prevent visual flickering (closes [#115](https://github.com/lwouis/alt-tab-macos/issues/115)) ([9a8c83e](https://github.com/lwouis/alt-tab-macos/commit/9a8c83e))
* quitting apps was not properly removing apps from the list ([10b2c71](https://github.com/lwouis/alt-tab-macos/commit/10b2c71))
* quitting multiple apps would refresh the ui multiple times ([bfc2700](https://github.com/lwouis/alt-tab-macos/commit/bfc2700))
* regression on collectionviewitem titles (not showing) ([8cb6d86](https://github.com/lwouis/alt-tab-macos/commit/8cb6d86))
* remove debug colors ([e588d55](https://github.com/lwouis/alt-tab-macos/commit/e588d55))
* remove unnecessary/wrong layout code ([9e719e6](https://github.com/lwouis/alt-tab-macos/commit/9e719e6))
* sharper images on non-retina displays ([1bb4d2a](https://github.com/lwouis/alt-tab-macos/commit/1bb4d2a))
* smaller payload for the icons ([bddb6fa](https://github.com/lwouis/alt-tab-macos/commit/bddb6fa))
* some apps have messy launch behavior ([7eb216d](https://github.com/lwouis/alt-tab-macos/commit/7eb216d)), closes [/github.com/lwouis/alt-tab-macos/issues/117#issuecomment-583868046](https://github.com//github.com/lwouis/alt-tab-macos/issues/117/issues/issuecomment-583868046)
* some apps should retry observing until it works ([0c731f4](https://github.com/lwouis/alt-tab-macos/commit/0c731f4))
* using floor() everywhere to avoid blurry rendering ([2a36196](https://github.com/lwouis/alt-tab-macos/commit/2a36196))


### Code Refactoring

* complete rework of the internals ([547311e](https://github.com/lwouis/alt-tab-macos/commit/547311e)), closes [#93](https://github.com/lwouis/alt-tab-macos/issues/93) [#24](https://github.com/lwouis/alt-tab-macos/issues/24) [#117](https://github.com/lwouis/alt-tab-macos/issues/117) [/github.com/lwouis/alt-tab-macos/issues/45#issuecomment-571898826](https://github.com//github.com/lwouis/alt-tab-macos/issues/45/issues/issuecomment-571898826)


### Features

* add an app icon and menubar icon (closes [#38](https://github.com/lwouis/alt-tab-macos/issues/38)) ([a345dae](https://github.com/lwouis/alt-tab-macos/commit/a345dae))
* add back the preferences for the new layout algo ([d52eb6d](https://github.com/lwouis/alt-tab-macos/commit/d52eb6d))
* add debug profile to feedback message ([a14f965](https://github.com/lwouis/alt-tab-macos/commit/a14f965))
* add feedback button on about window ([4046136](https://github.com/lwouis/alt-tab-macos/commit/4046136))
* add in-app feedback form (closes [#145](https://github.com/lwouis/alt-tab-macos/issues/145)) ([725a030](https://github.com/lwouis/alt-tab-macos/commit/725a030))
* add licence to about page ([cb66b79](https://github.com/lwouis/alt-tab-macos/commit/cb66b79))
* add preference to start at login (closes [#159](https://github.com/lwouis/alt-tab-macos/issues/159)) ([982fe6c](https://github.com/lwouis/alt-tab-macos/commit/982fe6c))
* adding cocoapods and letsmove/sparkle ([606bae7](https://github.com/lwouis/alt-tab-macos/commit/606bae7))
* better packing; tall thumbnails are 1/2 the width of wide ones ([e34e3b1](https://github.com/lwouis/alt-tab-macos/commit/e34e3b1))
* bump major version ([3c3b18c](https://github.com/lwouis/alt-tab-macos/commit/3c3b18c))
* cleaner layout and explanation text ([fd3e768](https://github.com/lwouis/alt-tab-macos/commit/fd3e768))
* debug build has code-signing to preserve permissions ([34a32f3](https://github.com/lwouis/alt-tab-macos/commit/34a32f3))
* divide preferences by topic (closes [#130](https://github.com/lwouis/alt-tab-macos/issues/130)) ([291f872](https://github.com/lwouis/alt-tab-macos/commit/291f872))
* drag-and-drop files on the ui (closes [#74](https://github.com/lwouis/alt-tab-macos/issues/74)) ([e1e3633](https://github.com/lwouis/alt-tab-macos/commit/e1e3633))
* german and spanish localization ([6c440a7](https://github.com/lwouis/alt-tab-macos/commit/6c440a7))
* improved translations ([debd3ae](https://github.com/lwouis/alt-tab-macos/commit/debd3ae))
* integrate sparkle for auto-updates (closes [#131](https://github.com/lwouis/alt-tab-macos/issues/131)) ([069382c](https://github.com/lwouis/alt-tab-macos/commit/069382c))
* localization (closes [#134](https://github.com/lwouis/alt-tab-macos/issues/134)) ([36e4bb0](https://github.com/lwouis/alt-tab-macos/commit/36e4bb0))
* make system calls more parallel (closes [#160](https://github.com/lwouis/alt-tab-macos/issues/160)) ([a29b39f](https://github.com/lwouis/alt-tab-macos/commit/a29b39f))
* migrate to standard os-backed preferences (closes [#161](https://github.com/lwouis/alt-tab-macos/issues/161)) ([e28c43f](https://github.com/lwouis/alt-tab-macos/commit/e28c43f))
* more appealing presentation + minor refac ([67f291d](https://github.com/lwouis/alt-tab-macos/commit/67f291d))
* nicer layout for about preferences ([03a5f77](https://github.com/lwouis/alt-tab-macos/commit/03a5f77))
* quit button is clearer with explicit mention of the name ([6b6d748](https://github.com/lwouis/alt-tab-macos/commit/6b6d748))
* replace default copyright with correct licence ([60b49ea](https://github.com/lwouis/alt-tab-macos/commit/60b49ea))
* separating the quit button as it is a special case ([9fa0c06](https://github.com/lwouis/alt-tab-macos/commit/9fa0c06))
* slightly increase contrast (mitigates [#82](https://github.com/lwouis/alt-tab-macos/issues/82)) ([291770e](https://github.com/lwouis/alt-tab-macos/commit/291770e))
* support macos "sudden termination" ([671fdab](https://github.com/lwouis/alt-tab-macos/commit/671fdab)), closes [/developer.apple.com/documentation/foundation/processinfo#1651129](https://github.com//developer.apple.com/documentation/foundation/processinfo/issues/1651129)


### BREAKING CHANGES

* bump major version
* Instead of asking the OS about the state of the whole system on trigger (what we do today; hard to do fast), or asking the state of the whole system on a timer (what HyperSwitch does today; inaccurate) - instead of one of 2 approaches, v3 observes the Accessibility events such as "an app was launched", "a window was closed". This means we build a cache as we receive these events in the background, and when the user trigger the app, we can show accurate state of the windows instantly.

Of course there is no free lunch, so this approach has its own issues. However from my work on it from the past week, I'm very optimistic! The thing I'm the most excited about actually is not the perf (because on my machine even v2 is instant; I have a recent macbook and no 4k displays), but the fact that we will finally have the thumbnails in order of recently-used to least-recently-used, instead of the order of their stack (z-index) on the desktop. It's a big difference! There are many more limitations that are no longer applying also with this approach.

## [2.3.4](https://github.com/lwouis/alt-tab-macos/compare/v2.3.3...v2.3.4) (2020-01-22)


### Bug Fixes

* escape key was absorbed by the inactive app (closes [#123](https://github.com/lwouis/alt-tab-macos/issues/123)) ([5260619](https://github.com/lwouis/alt-tab-macos/commit/5260619))

## [2.3.3](https://github.com/lwouis/alt-tab-macos/compare/v2.3.2...v2.3.3) (2020-01-21)


### Bug Fixes

* touch bar's escape key works on mbp 15 2019 (closes [#119](https://github.com/lwouis/alt-tab-macos/issues/119)) ([eda6b7e](https://github.com/lwouis/alt-tab-macos/commit/eda6b7e))

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
