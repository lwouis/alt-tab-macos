# Integrated browser website icons

One main implementation is built into AltTab. The Safari extension and Chrome probes are deprecated development history, not additional supported products, installation requirements or runtime fallbacks.

## Current behavior

**Show website icons** in Appearance defaults off. Its disclosure explains that public website requests also apply to private windows, outside the browser session and without browser cookies or sign-in information. Turning it off cancels pending transfers and clears native icon state.

Normal operation is no longer restricted to laboratory sites. Bounded Accessibility discovery obtains a document URL and resolves its public HTTPS homepage without the document path, query or fragment. Declared artwork and a root favicon fallback use the shared white-first, rounded renderer. Ready icons remain while replacements resolve; confirmed webpages without usable artwork receive a globe. Settings and unidentified windows keep app icons.

This does not claim generic private-window detection or exact browser-selected favicon parity. Authenticated, script-generated, article-specific or unsupported artwork can differ or fall back.

## Resource boundaries

Four background AX workers, 32 pending window probes and 128 window cache entries bound discovery. Page and asset caches each hold 32 entries. Pending page and asset resolutions are limited to 32 each, with 256 waiters per key. Eight transfers run concurrently and 32 can queue. Responses are capped at 1 MiB; positive and negative cache lifetimes are 30 and 5 seconds. No continuous refresh timer runs.

Ephemeral URLSession requests omit browser credentials and cookies. Public HTTPS destinations and redirects undergo address screening, rejecting local names, private addresses, credentials and unusual ports. DNS screening is not transport pinning and cannot guarantee protection against DNS rebinding or proxy behavior. System DNS calls are not cancellable. Maintainer security review remains necessary before distribution.

## Development path: extension first, then native integration

| Stage | Work and evidence | Why the approach changed |
| --- | --- | --- |
| Safari companion | Built and locally tested a Safari extension, native messaging/snapshot bridge and AltTab receiver. Iterated on navigation retention, missing-icon placeholders, transparent artwork, appearance contrast and companion icon packaging. | Established the desired behavior, but added a separately installed component, permissions and distribution work. The audit also found repeated batch publication and rendering work to reduce before shipping that route. |
| Browser capability research | Probed Accessibility URLs/images and Apple Events in Safari and Chrome. Safari exposed favicon pixels in a controlled toolbar test with our extension disabled. Chrome's lightweight extension favicon-cache prototype passed a navigation test. A direct Chrome database read failed with a lock in the tested setup. | These results supported several possible providers, not a universal native bitmap API. Apple Events URL reads worked without enabling browser JavaScript; direct toolbar bitmap access did not generalize across the tested browsers. |
| Integrated native prototype | Moved URL discovery and independent icon retrieval into AltTab. Same-title red/blue fixtures appeared correctly in Safari and Chrome in the actual switcher, with the Safari companion disabled and its receiver bypassed. Later tests covered eight public origins. | Demonstrated a shared extension-free baseline instead of requiring a Safari-native/Chrome-extension split. Independent homepage artwork remains an approximation of the browser's selected icon. |
| Reused presentation and audited resources | Reused the companion renderer as a byte-identical vendored copy with parity checks. Added rounded white-first artwork, coalesced requests/decodes, cache and transfer limits, obsolete-result checks and performance measurements. | Keeps successful artwork work while changing acquisition. The clean upstream branch excludes unrelated local UI and window-management patches. |

The integrated provider is the selected product direction. Historical extension instructions remain archived for traceability. Neither extension was published to an extension store for this proposal.

Historical evidence: [companion source](https://github.com/josdyr/dotfiles/tree/52dd5be/macos/alt-tab-site-icons), [capability experiments](https://github.com/josdyr/dotfiles/blob/52dd5be/macos/alt-tab-site-icons/prototypes/README.md), and [research journal](https://github.com/josdyr/dotfiles/blob/52dd5be/docs/alt-tab-browser-icon-research.md).

## Verification and remaining qualification

Run `python3 ai/test-native-icons.py` for artwork, resolver, stress, admission, cancellation and public-URL policy checks. Add `--real-sites` for eight network-dependent examples. Laboratory mode remains for loopback fixtures only.

On September 13, builds and 1,266 project tests passed, as did 44 artwork checks and the standalone suite. General-policy resolution produced icons for Dario Amodei's site, Google and DuckDuckGo without the laboratory allowlist. The preference was verified on and off in the running local app.

Local Xcode validation used a macOS 12 deployment override and disabled warnings-as-errors for the installed macOS 27 SDK. CI, the complete supported-OS/browser matrix, general-mode whole-process performance and final installed-app navigation remain unverified. The proposal remains open for review, not universally release-qualified.

Related discussions: [browser favicons](https://github.com/lwouis/alt-tab-macos/issues/527) and [Chrome window icons](https://github.com/lwouis/alt-tab-macos/issues/4651).
