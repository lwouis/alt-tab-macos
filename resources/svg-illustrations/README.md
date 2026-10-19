# Native illustrations

The SVG files are the editable artwork. Each opens independently with English text and embedded JPEG thumbnails. Window frames, app-icon silhouettes, switchers and lettering remain vector. No website build or raster conversion is needed to edit them.

The visual reference is the website's `docs/design/vector-assets/scenes.mjs` and `reference-shapes.json` at commit `41bd90f3d0f11fbedbaa5485734269265f6e0f90`, including the compact App Icons spacing from `fab3b2880413b4f5a894144adf360bde1cec53a8`. Compositions are adapted to native card sizes and omit the website menu bar. Repeated paths, icon groups and images use local `<defs>` / `<use>` references. These preserve native placement without the symbol viewports that differ between native and browser renderers.

- `settings-*`: all three style cards and the matching Customize examples. Used by Settings and the Day 4 tour.
- `*-comparison`: the four Pro features, including both Titles and App Icons. The two panels share a stationary desktop. Only the switcher scales in Auto Size.
- `permission-*`: Device Control and Screen Recording explanations.

Text carries stable `data-i18n` identifiers with English defaults. Text that reads the same in every language (digits, key glyphs, key names, app names like Safari) has no `data-i18n`, so it is drawn as written and never sent to translators. Keep `font-family`, `font-size`, `data-max-width`, `data-min-font-size`, anchors and clip bounds on each text item. The shared native drawer supplies existing translations, measures the resolved text, shrinks to the declared minimum, and truncates by complete characters if necessary. Keep clips inside any RTL positioning wrapper. `data-dark-fill` supplies theme-dependent labels; `data-rtl-transform` repositions comparison panels without mirroring their contents.

Do not put a Pro badge in an SVG. `ProComparisonView` supplies the existing native badge above the artwork. English heading overrides for unknown trial history use stable text IDs and do not move layout into Swift.

The app targets macOS 12.0 and draws illustrations using public Core Graphics and Core Text. Run `python3 scripts/assets/compile_illustrations.py` after editing the SVGs. It generates `resources/native-illustrations/scenes.plist` plus shared, separate JPEGs; only that directory ships in the app. The SVGs remain independently editable source files. Run the compiler with `--check` to verify generated files are current. The compiler intentionally supports only the primitives used here and rejects unsupported features rather than losing them.

The drawer reuses shared paths, gradients, JPEGs and prepared text. Localization, theme and RTL remain runtime choices, with no per-locale artwork files. The native renderer was verified on macOS 12.7.6, 13.7.4 and 27.0.1; no 12.0 or Intel runtime test is implied.

The existing `scripts/l10n/extract_l10n_strings.sh` workflow also extracts SVG defaults
through `svg_strings.py`. It feeds temporary source into genstrings; no duplicate English catalog or locale-specific SVG is shipped.

## Optimization

Run `npx --yes svgo@4.1.0 --config scripts/assets/svgo.config.mjs -f resources/svg-illustrations` after editing. The configuration preserves the text attributes and grouping used by localization, dark appearance and RTL positioning. Do not replace it with the default preset: inherited fonts or transformed clipping groups can change native rendering. Stable localization IDs live in `data-i18n`; internal SVG reference IDs may be shortened.

Embed each distinct JPEG once per SVG and reference it locally. Crop photos to their visible region before encoding, rather than storing pixels hidden by `xMidYMid slice`. The current crops use optimized JPEG quality 82 with 4:2:0 chroma subsampling. Size them for the largest native view at 2× Retina density: Settings previews are 496 points wide, Pro comparisons 690, and permission scenes 378. The root's `data-raster-width` records that whole-scene pixel budget. Apply ancestor scales to determine each photo's budget; do not upscale smaller originals. Smaller cards reuse the same standalone SVG, so some downsampling at smaller view sizes is intentional.

Compare native renders at the largest view size after changing paths, references or photos. Include light/dark appearance and long/RTL substitutions; browser output alone does not establish native compatibility. Keep SVG text editable and never convert lettering or complete scenes to bitmap images.
