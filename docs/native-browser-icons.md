# Native browser icons: experimental review scope

This branch is based directly on upstream 11.6.1 (`850a7235`). It contains only the opt-in native provider, renderer, fixture tooling and the TileView icon hook. It excludes local layout, selection, hover, Device Hub, Safari companion, entitlements and preview patches. It is a reviewable experiment, not a release candidate.

Normal app launches retain upstream behavior. `python3 ai/run-native-icon-demo.py /path/to/AltTab.app` enables the reviewed-origin experiment for that process. No settings, login items or extra permissions are installed by this launcher. Quit the experiment and reopen the ordinary app to restore normal behavior.

The provider discovers AX document URLs with bounded traversal off-main and maps eight reviewed HTTPS origins to clean public homepages. It never forwards document paths, queries or fragments. Network access remains restricted to the exact configured homepages and icon resources. It uses ephemeral, credential-free requests, bounded responses and redirects, and a generic renderer copied unchanged from the Safari companion. It can produce a different icon from the actual browser document.

Limits: 32 pending page resolutions, 32 pending asset resolutions, 256 waiters per key, eight active URLSession transfers globally, 32 queued transfers, 32 entries per cache, 1MiB retained response buffers, and 30s positive / 5s negative cache lifetimes. Excess demand completes without artwork and can retry later. Window freshness is checked on subsequent UI updates without a polling timer.

## Release gates

- Native AX discovery does not reliably identify private windows across supported browsers. The public-site allowlist must remain in place until the privacy contract is settled and tested. Ephemeral requests still contact websites.
- Add a user-facing opt-in and a supported provider/privacy policy before unrestricted operation.
- Qualify temporary AX loss, cross-origin continuity, missing-icon globe behavior, window recycling and cancellation.
- Compare full-process CPU, memory, wakeups and keyboard latency against the same upstream binary with the feature disabled, on supported macOS versions. Isolated resolver timings are not sufficient.
- Review actual browser favicon selection, dynamic icons, formats, appearance, profile behavior and distribution with maintainers.

## Local checks

Compile a standalone test with both `src/switcher/main-window/IconRenderer.swift` and `src/switcher/main-window/FixtureIconResolver.swift`, plus one test entry point under `ai`. Fixture resolver, stress and admission tests use `python3 ai/native-icon-server.py`; real-site tests use `ai/run-native-icon-demo.py`. Compile `ai/IconRendererTests.swift` with the renderer alone. Renderer source/test parity can be checked with `ai/check-icon-renderer-parity.py /path/to/macos/alt-tab-site-icons`.

The admission test completes 1,000 unique slow-page callers, admits at most 32 concurrent resolutions, and verifies recovery. Artwork regressions cover white-first backing and corner protection. These checks do not claim private-mode exclusion or release readiness.

## Preparation evidence

The local-patch development binary completed five equal 5-second cycles per mode: native off sampled 4.46s CPU and 232,080 KiB peak RSS, native on 3.91s CPU and 228,816 KiB. This is one noisy pair, not evidence of an improvement or a measurement of this clean review branch. It exposed background self-process AX inspection; excluding the current process removed the AppKit warning on rerun. The clean review project separately builds and passes strict signature verification, but has not undergone the same live comparison.

Private-window support should use browser-owned artwork where available and otherwise fall back. Release method is still pending: integration-backed context versus a disclosed opt-in independent-fetch mode. No generic Safari private-state signal has been validated. This branch must not be described as ready for unrestricted browsing or distribution.
