# Native browser icons: experimental review scope

This branch is based directly on upstream 11.6.1 (`850a7235`). It contains only the opt-in native provider, renderer, fixture tooling and the TileView icon hook. It excludes local layout, selection, hover, Device Hub, Safari companion, entitlements and preview patches. It is a reviewable experiment, not a release candidate.

Normal app launches retain upstream behavior. `python3 ai/run-native-icon-demo.py /path/to/AltTab.app` enables the reviewed-origin experiment for that process. No settings, login items or extra permissions are installed by this launcher. Quit the experiment and reopen the ordinary app to restore normal behavior.

The provider discovers AX document URLs with bounded traversal off-main and maps eight reviewed HTTPS origins to clean public homepages. It never forwards document paths, queries or fragments. Network access remains restricted to the exact configured homepages and icon resources. It uses ephemeral, credential-free requests, bounded responses and redirects, and a generic renderer copied unchanged from the Safari companion. It can produce a different icon from the actual browser document.

Limits: 32 pending page resolutions, 32 pending asset resolutions, 256 waiters per key, eight active URLSession transfers globally, 32 queued transfers, 32 entries per cache, 1MiB retained response buffers, and 30s positive / 5s negative cache lifetimes. Excess demand completes without artwork and can retry later. Window freshness is checked on subsequent UI updates without a polling timer.

## Development path: extension first, then native integration

| Stage | Work and evidence | Why the approach changed |
| --- | --- | --- |
| Safari companion | Built and locally tested a Safari extension, native messaging/snapshot bridge and AltTab receiver. Iterated on navigation retention, missing-icon placeholders, transparent artwork, appearance contrast and companion icon packaging. | Established the desired behavior, but added a separately installed component, permissions and distribution work. The audit also found repeated batch publication and rendering work to reduce before shipping that route. |
| Browser capability research | Probed Accessibility URLs/images and Apple Events in Safari and Chrome. Safari exposed favicon pixels in a controlled toolbar test with our extension disabled. Chrome's lightweight extension favicon-cache prototype passed a navigation test. A direct Chrome database read failed with a lock in the tested setup. | These results supported several possible providers, not a universal native bitmap API. Apple Events URL reads worked without enabling browser JavaScript; direct toolbar bitmap access did not generalize across the tested browsers. |
| Integrated native prototype | Moved URL discovery and independent icon retrieval into AltTab. Same-title red/blue fixtures appeared correctly in Safari and Chrome in the actual switcher, with the Safari companion disabled and its receiver bypassed. Later tests covered eight public origins. | Demonstrated a shared extension-free baseline instead of requiring a Safari-native/Chrome-extension split. Independent homepage artwork remains an approximation of the browser's selected icon. |
| Reused presentation and audited resources | Reused the companion renderer as a byte-identical vendored copy with parity checks. Added rounded white-first artwork, coalesced requests/decodes, cache and transfer limits, obsolete-result checks and performance measurements. | Keeps successful artwork work while changing acquisition. The clean upstream branch excludes unrelated local UI and window-management patches. |

The selected direction for this proposal is the integrated native provider. It is a working restricted prototype, not a completed replacement for every extension capability. Exact active-tab metadata, private-state detection, script-updated icons and broad browser/OS coverage remain important differences. Neither the Safari companion nor the Chrome probe was published to an extension store as part of this proposal.

Earlier implementation and dated evidence remain available in the [Safari companion source](https://github.com/josdyr/dotfiles/tree/52dd5be/macos/alt-tab-site-icons), [capability experiments](https://github.com/josdyr/dotfiles/blob/52dd5be/macos/alt-tab-site-icons/prototypes/README.md) and [research journal](https://github.com/josdyr/dotfiles/blob/52dd5be/docs/alt-tab-browser-icon-research.md). The journal preserves superseded recommendations; this document describes the current proposal.

### Why an arbitrary site still shows its browser icon

The running demo only resolves origins listed in `ai/native-icon-sites.json`. A document on another origin returns no native artwork before fetching, even if that site has a valid favicon. Article paths, query parameters and fragment anchors are removed for lookup on admitted origins, so an article or `#section` does not itself prevent matching. This is the test boundary, not a finding that other websites or browsers are unsupported. Broader operation requires replacing the laboratory list with the reviewed general network policy and product opt-in; adding individual reported sites is not the intended release design.

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
