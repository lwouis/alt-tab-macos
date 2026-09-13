# Native browser icons: experimental review scope

This branch is based directly on upstream 11.6.1 (`850a7235`). It contains only the opt-in native provider, renderer, fixture tooling and the TileView icon hook. It excludes local layout, selection, hover, Device Hub, Safari companion, entitlements and preview patches. It is a reviewable experiment, not a release candidate.

Normal app launches retain upstream behavior. `python3 ai/run-native-icon-demo.py /path/to/AltTab.app` enables the reviewed-origin experiment for that process. No settings, login items or extra permissions are installed by this launcher. Quit the experiment and reopen the ordinary app to restore normal behavior.

The provider discovers AX document URLs with bounded traversal off-main and maps eight reviewed HTTPS origins to clean public homepages. It never forwards document paths, queries or fragments. Network access remains restricted to the exact configured homepages and icon resources. It uses ephemeral, credential-free requests, bounded responses and redirects, and a generic renderer copied unchanged from the Safari companion. It can produce a different icon from the actual browser document.

Limits: 32 pending page resolutions, 32 pending asset resolutions, 256 waiters per key, eight active URLSession transfers globally, 32 queued transfers, 32 entries per cache, 1MiB retained response buffers, and 30s positive / 5s negative cache lifetimes. Excess demand completes without artwork and can retry later. Window freshness is checked on subsequent UI updates without a polling timer.

## Release gates

- Native AX discovery does not reliably identify private windows across supported browsers. Private-window rendering is not proof of private-state detection. The public-site allowlist remains in place for this review. Ephemeral requests still contact websites outside the browser session.
- Add a user-facing opt-in and a supported provider/privacy policy before unrestricted operation.
- Qualify temporary AX loss, cross-origin continuity, missing-icon globe behavior, window recycling and cancellation.
- Compare full-process CPU, memory, wakeups and keyboard latency against the same upstream binary with the feature disabled, on supported macOS versions. Isolated resolver timings are not sufficient.
- Review actual browser favicon selection, dynamic icons, formats, appearance, profile behavior and distribution with maintainers.

## Local checks

Run `python3 ai/test-native-icons.py` for the renderer and loopback resolver, stress and admission checks. It compiles into a temporary directory, starts its own fixture server and stops that server on completion or failure. It refuses an occupied fixture port. Add `--real-sites` to make independent requests to the eight reviewed public homepages and icons. These live-site checks depend on current network responses and are not deterministic CI tests.

Compile a standalone test with both `src/switcher/main-window/IconRenderer.swift` and `src/switcher/main-window/FixtureIconResolver.swift`, plus one test entry point under `ai`. Fixture resolver, stress and admission tests use `python3 ai/native-icon-server.py`; real-site tests use `ai/run-native-icon-demo.py`. Compile `ai/IconRendererTests.swift` with the renderer alone. Renderer source/test parity can be checked with `ai/check-icon-renderer-parity.py /path/to/macos/alt-tab-site-icons`.

The admission test completes 1,000 unique slow-page callers, admits at most 32 concurrent resolutions, and verifies recovery. Artwork regressions cover white-first backing and corner protection. These checks do not claim private-mode exclusion or release readiness.

## Preparation evidence

Final clean-branch validation on 2026-09-13: Debug build and strict bundle signature verification passed; the Test scheme passed all 1,266 project tests. The standalone runner passed 44 artwork checks, loopback resolver/stress/admission checks, and all eight live public-site resolutions, including Google and DuckDuckGo. Local Xcode commands used macOS 12 deployment and disabled warnings-as-errors for the installed macOS 27 SDK; this does not validate upstream's full supported-OS matrix. CI is unverified.

The local-patch development binary completed five equal 5-second cycles per mode: native off sampled 4.46s CPU and 232,080 KiB peak RSS, native on 3.91s CPU and 228,816 KiB. This is one noisy pair, not evidence of an improvement or a measurement of this clean review branch. It exposed background self-process AX inspection; excluding the current process removed the AppKit warning on rerun. The clean review project separately builds and passes strict signature verification, but has not undergone the same live comparison.

## Proposed release behavior

Recommend one explicit, default-off setting: **Show website icons**. Explain beneath it: "Fetches website icons directly, including for private windows. Requests happen outside your browser session, without its cookies or sign-in information." This is proposed product copy, not an implemented preference. The experimental launcher now prints this disclosure before starting.

Keep a ready icon while a replacement is loading; show a neutral globe for a confirmed webpage without usable artwork, and retain the browser app icon for settings or unidentified windows. The native prototype still needs the globe and full navigation continuity work. Do not silently broaden this branch's reviewed URL list into arbitrary fetching.

This proposal does not require browser extensions or claim browser-selected favicon parity. Safari exposes a [private-browsing property to app extensions](https://developer.apple.com/documentation/safariservices/sfsafaripageproperties/usesprivatebrowsing); Chrome exposes [incognito state and favicon URLs to extensions](https://developer.chrome.com/docs/extensions/reference/api/tabs). Neither establishes a generic private-state signal for this standalone AX provider. Browser integrations remain an alternative if maintainers require private-window exclusion or browser-owned artwork.

Publish this as a separate **draft PR for architecture review**, with the release gates above open. It is not an unrestricted browsing release or a request to merge unfinished behavior. Maintainers decide whether to proceed with independent fetching before distribution work or extension-store publication.

Related upstream discussions: [Show selected tab favicon on browser windows](https://github.com/lwouis/alt-tab-macos/issues/527) and [Use Website Favicon for Chrome Window Icons](https://github.com/lwouis/alt-tab-macos/issues/4651). This experiment addresses feasibility with independent public-homepage discovery; it does not claim direct access to the exact active-tab favicon or close those feature requests.
