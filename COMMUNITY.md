# AltTab Free

This is an independent GPL-3.0 fork of [AltTab](https://github.com/lwouis/alt-tab-macos),
based on upstream v11.10.2 (`2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab`).
It is not an official AltTab release. Original authorship and licensing are retained.

All window switching, Search, App Icons and Titles styles, Auto Size, search-on-release,
and additional keyboard shortcuts are available without a license or trial expiration.
The application uses an explicit unrestricted state. It never validates a license,
reads the original license keys, or changes the original license storage.
Purchase prompts, account links, and Pro badges are hidden.

The app is fully offline. Sparkle and AppCenter are removed from the app's build dependencies.
The HTTP license client is excluded from the app target; it remains in the upstream mocked tests.
Feedback submission is replaced by local diagnostics export. External web links are inert.
Before application initialization, macOS's NoNetwork Seatbelt profile blocks socket networking
for the process and its children, including TCP and UDP. Startup fails closed if the profile
cannot be applied. Local Mach IPC, used by the CLI and native window APIs, remains available.

Official update menu items are removed.
The update preference is fixed to manual, including after importing old settings.
To update this fork, review and merge upstream source changes, then rebuild it.

Build with Xcode command line tools:

```sh
bash scripts/build_community.sh
```

The app is produced at `build/Community/Build/Products/Release/AltTab.app`.
This script uses local ad-hoc signing, not the upstream developer's identity or Apple notarization.
The original bundle identifier is retained so an existing installation keeps its preferences.
macOS may require Accessibility and Screen Recording permission to be granted again because
the signer changed. The original application's Keychain items are never accessed by this fork.

The delivery build was compiled successfully. The full test suite was not run at the user's request.
For future development, run the upstream checks with `bash ai/test.sh`. Local signing overrides, if needed for the
Debug app build, belong in the ignored `config/local.xcconfig`.

Run `bash scripts/check_offline.sh` to verify that macOS denies TCP and UDP while permitting
the local command message port. The Seatbelt API is deprecated by Apple; verify this probe
when moving the fork to a new major macOS version. It is used here because App Sandbox would
also restrict the broad local Accessibility access that a window switcher needs.
