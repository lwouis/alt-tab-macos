---
name: assets-optimization
description: Audit and optimize every image asset shipped with AltTab. Apply the right format per asset class (PDF for vectors, HEIC for raster) and the right post-processing (strip Figma cruft from PDFs, extract SF Symbols as minimal vector PDFs, encode raster sources to HEIC at q50 with visual review). Use whenever new assets are added, when the bundle size needs shrinking, or whenever you want a full assets audit.
---

# /assets-optimization — AltTab asset audit and optimization

## Goal

Every byte that ships in `AltTab.app/Contents/Resources/` should justify itself. Vectors stay vector, rasters compress to HEIC, and neither carries metadata, color profiles, accessibility tags, or producer signatures that AppKit doesn't use.

This skill applies a known-good pipeline to each asset class. It is opinionated about the right format and the right encoder for each kind of content.

## When to use

- A designer drops new exports into `~/Desktop/` or `resources/`.
- Someone asks "why is the bundle so big?".
- After adding a new icon, illustration, app icon variant, or menubar variant.
- Periodic audit when nothing else is broken.

## Step 1: Inventory

Run a one-shot enumeration so you know what you're working with:

```sh
find resources -type f \( -iname '*.pdf' -o -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.heic' -o -iname '*.svg' -o -iname '*.icns' \) \
  -exec ls -la {} \; | awk '{printf "%8d  %s\n", $5, $9}' | sort -k2
```

Group what you see by directory. For AltTab the relevant buckets are:

- `resources/icons/menubar/` — small template icons shown in the macOS menubar.
- `resources/icons/tabs/` — Preferences sidebar icons (template, sized ~13pt).
- `resources/icons/permission-window/` — first-launch permission window icons (~32pt).
- `resources/icons/app/` — the macOS app icon (`.icns` + `.iconset/`). **Don't touch** — `.icns` is required by the bundle and Apple's tooling produces near-optimal output already.
- `resources/illustrations/` — the appearance-tab preview thumbnails. Raster (screenshots inside).

For each asset, decide what category it falls into:

| Source content | Right format | Why |
|---|---|---|
| Custom vector design (Figma/Sketch/Illustrator) | **PDF** | macOS 10.13 doesn't accept SVG; PDF is the universal vector container AppKit reads natively. |
| SF Symbol (Apple system glyph) | **Font glyph** in the bundled `SF-Pro-Text-Regular.otf` subset | Render via `NSImage.fromSymbol(.foo, pointSize:)` (or as text via the `Symbols` enum). Smaller than per-icon PDFs, picks up Apple's latest glyph refinements automatically when the developer updates SF Symbols.app. |
| Photographic / screenshot-heavy | **HEIC** | HEIC at q50 beats JPEG by ~30% at the same perceptual quality. |
| Tiny pixel-precise UI sprite | **PNG @2x** | Below ~40×40px the PDF overhead exceeds the bitmap savings. PNG wins. |
| App icon (the macOS bundle one) | **`.icns`** | Required by `CFBundleIconFile`. |

If an asset is in the wrong format, flag it. If it's in the right format but unoptimized, run the matching pipeline below.

## Step 2: Vector PDFs — Figma exports

Figma's "Export → PDF" output is bloated. For each menubar/illustration/icon vector PDF that came from Figma, you can strip ~50–75% of the bytes without losing a single rendered pixel.

What Figma adds that AppKit doesn't need:

1. **Embedded ICC color profile** (`/ICCBased ...`, ~3.2 KB compressed). Replace every `[/ICCBased N R]` reference with `/DeviceRGB` (or `/DeviceGray` for monochrome). Patches needed in:
   - the page `Resources/ColorSpace` dict
   - every Form XObject's `Resources/ColorSpace` dict (these are streams, not plain dicts — pikepdf's `pdf.objects` will only catch them if you accept both `Dictionary` and `Stream`)
   - every Image XObject's direct `/ColorSpace` key
   - every Shading dict inside `Pattern` entries (Figma's color icons use 8+ patterns, each with its own `/ColorSpace N R` reference)
2. **`/Metadata`** XMP packet (~830 B) — Figma's XML manifest.
3. **`/StructTreeRoot`, `/ParentTree`, `/StructElem`** — accessibility tags ("Document" / "Part" structural roles). AppKit's PDF renderer ignores them.
4. **`/Info` dict** — `Producer="Figma"`, `Title="Menubar 22x22@1x white"`. In Figma's exports the Info dict sometimes lives **inline inside the Catalog** rather than at the trailer level, so deleting `pdf.docinfo` isn't enough — also `del root[Name('/Info')]`.
5. **`/Lang`, `/MarkInfo`, `/Annots`, `/StructParents`, `/Tabs`** — empty or trivial page-level entries.
6. **`/ProcSet [/PDF]`** — deprecated since PDF 1.4.

Use the script:

```sh
python3 scripts/assets/optimize_figma_pdf.py resources/icons/menubar/*.pdf
```

It edits in place and prints the savings per file. After running, also pipe through `mutool clean -ggg -z` and `qpdf --object-streams=generate --recompress-flate --compression-level=9` for the final 1–2% squeeze.

Verify each file still renders by sips'ing it back to PNG and eyeballing:

```sh
for f in resources/icons/menubar/*.pdf; do
  sips -s format png "$f" --out "/tmp/$(basename $f .pdf).png" -Z 300 >/dev/null 2>&1
done
```

Open the PNGs in Preview to confirm nothing visual changed.

## Step 3: SF Symbols via font subset

Every SF Symbol shipped in AltTab — switcher status icons, sidebar tab icons, button icons, permission/feedback icons — is rendered as a text glyph from a subsetted SF Pro Text font. There are no SF-Symbol PDFs in the bundle.

How it works: SF Symbols are glyphs in the Private Use Area of SF Pro Text. Apple's `SF-Pro-Text-Regular.otf` contains every symbol they've ever shipped. We subset it down to just the codepoints AltTab needs (currently ~36 glyphs, ~17 KB) into `resources/SF-Pro-Text-Regular.otf`, and register it via `Info.plist:ATSApplicationFontsPath = ""`. At runtime, `NSFont(name: "SF Pro Text", size:)` resolves to the bundled subset on macOS <11 (where the system font isn't installed) and to the system font on macOS 11+, with identical glyph appearance either way.

To add a new SF Symbol:

1. Open [SF Symbols.app](https://developer.apple.com/sf-symbols/), search for the symbol, press **Cmd-C** to copy the symbol character to the clipboard. (Apple's name→codepoint mapping is not exposed via public API, and the SF Pro Text font's cmap uses `uniXXXXXX.medium`-style names rather than semantic ones, so this manual lookup is the authoritative path.)
2. Paste the character into a new case on the `Symbols` enum in [src/switcher/main-window/TileFontIconView.swift](src/switcher/main-window/TileFontIconView.swift) — e.g., `case foo = "􀝥"  // SF Symbol name`.
3. Paste the same character at the end of the `--text=` argument in [scripts/assets/subset_font.sh](scripts/assets/subset_font.sh).
4. Run `bash scripts/assets/subset_font.sh`. It reads `/Library/Fonts/SF-Pro-Text-Regular.otf` (installed by SF Symbols.app — a standard developer prerequisite) and writes the regenerated subset to `resources/SF-Pro-Text-Regular.otf`. Picks up Apple's latest glyph refinements automatically.
5. Use it in code: `NSImage.fromSymbol(.foo, pointSize: 14)` returns a template `NSImage`; or `TileFontIconView(symbol: .foo, ...)` for the cached-attributed-string path in the switcher hot loop.

The script runs `pyftsubset` via the project's pipenv environment. Warnings about `MERG`/`meta`/`trak` tables being dropped are normal — those tables aren't relevant to glyph rendering.

### Historical note: SF Symbols via PDF (deprecated, scripts removed)

A previous pipeline shipped each SF Symbol as a per-glyph PDF in `resources/icons/`. The pipeline lives only in git history now (`scripts/assets/export_sf_symbol_pdf.swift` was deleted alongside the migrated PDFs). The technique is worth knowing in case a future need arises (e.g., a multi-color symbol that fonts can't represent):

- The naive route — `NSImage(systemSymbolName:).draw(in:)` against a PDF `CGContext` — produces a **black rectangle**, because Quartz emits `image-mask + fill-rectangle` operators where the rectangle paints over the mask. AppKit bug at the PDF emission level; `paletteColors` config does not fix it.
- The working route was to extract the symbol's vector path directly via private selectors that have been stable across macOS 11–15:
  `NSImage(systemSymbolName:).representations[0] (NSSymbolImageRep) → .perform("vectorGlyph") (CUINamedVectorGlyph) → .perform("CGPath") (real CGPath)`.
- The CGPath lives in CUI's internal coordinate space (~2× display points, Y-down) — scale to fit the canvas and flip Y. Walk the path via `CGPath.applyWithBlock` and emit raw PDF operators (`m`, `l`, `c`, `h`, `f`). Non-zero winding fill. Fill with DeviceGray (`0 g`), **not** `NSColor.black.cgColor`, which drags in a ~3.4 KB ICC color profile.
- Final PDF wrapper: 4 objects (Catalog, Pages, Page, Content), no `/Info`, no `/Metadata`, no `/Resources/ColorSpace`. ~750–1800 bytes per icon.

Git: see commit `990c1e79` ("feat: pro improve assets") for the PDF pipeline as-it-was; subsequent commit migrated the SF-Symbol PDFs back to font glyphs.

## Step 4: Raster → HEIC at q50

For anything raster (illustration thumbnails, screenshots inside an icon, anything photographic), HEIC at quality 50 is the baseline. q50 is roughly 50% smaller than JPEG at perceptually-equivalent quality, and at the small display sizes used in this app the artifacts are invisible.

Pipeline (built-in to macOS via `sips`):

```sh
sips -Z 1000 -s format heic -s formatOptions 50 input.png --out output.heic
```

- `-Z 1000` resizes the longest edge to 1000px **preserving aspect ratio**. AltTab's illustration display is 500pt wide, so 1000px is the correct @2x ship size. Anything larger wastes bytes; anything smaller looks soft on Retina.
- `formatOptions 50` is the quality. q50 was chosen after a side-by-side comparison at q20/q35/q50/q65/q80 — q50 was the lowest setting where text in screenshots stayed legible and gradient backgrounds didn't band.

Use the script for batch conversion:

```sh
bash scripts/assets/encode_heic.sh ~/Desktop 1000 50
```

That walks all PNG/JPEG files in the source directory, resizes to longest-edge 1000px at q50 HEIC, writes outputs to `/tmp/heic-out/`.

### Visual review (mandatory)

Before swapping the new HEICs into `resources/`, **always** decode a representative sample back to PNG and visually compare against the source:

```sh
sips -s format png /tmp/heic-out/sample.heic --out /tmp/sample-decoded.png >/dev/null 2>&1
open /tmp/sample-decoded.png /Users/you/Desktop/sample.png
```

Pick the visually most demanding file from the batch — usually one with the most text or the strongest gradients. Confirm:

- No banding in flat color regions
- Text edges still crisp at native display size
- No haloing around anti-aliased edges
- Color rendition matches

If anything looks degraded, bump quality to q60 or q65 and re-batch. The user, not the script, is the final arbiter — show them the sample with sizes before committing.

### Bumping quality

If q50 isn't acceptable, the next quality steps are q60 and q65 — beyond that, returns diminish quickly. q80 is the previous default in this repo and roughly 2× the bytes of q50 for no visible improvement on AltTab's content.

## Step 5: pbxproj registration

Whenever you change the file extension of a resource (.jpg → .heic, .png → .pdf, etc.), update [alt-tab-macos.xcodeproj/project.pbxproj](alt-tab-macos.xcodeproj/project.pbxproj). The places that need patching:

1. **PBXBuildFile section** — comment + the comment inside `fileRef = ... /* name.ext */`.
2. **PBXFileReference section** — comment, `lastKnownFileType` (e.g. `image.pdf`, `image.heic`, `image.png`), and `path = "name.ext"`.
3. **PBXGroup section** — the file's entry inside its parent group's `children`.
4. **PBXResourcesBuildPhase section** — the entry in the main app target's `files`.

For pure extension swaps (no new files), `sed -i '' 's|old\.ext|new.ext|g'` plus a `lastKnownFileType` substitution covers it. For new files, generate new 24-char uppercase-hex object IDs (`python3 -c "import secrets; print(secrets.token_hex(12).upper())"`) and insert in all four places.

If you removed an asset entirely (file deleted from disk), delete its 4 entries from pbxproj — otherwise the build fails with "missing file" or ships dangling references.

## Step 6: Verify

```sh
bash ai/build.sh        # must show ** BUILD SUCCEEDED **
bash ai/run.sh          # launch the app and visually inspect every asset
```

Walk through every UI surface that loads an asset:

- Menubar icon (default + the two alternates from Preferences → General → Menubar icon)
- Preferences sidebar — 4 tab icons (SF Symbol on macOS 11+, bundled PDF below)
- Permissions window — open by revoking a permission
- Preferences → Appearance — illustration thumbnails change per show/hide row

Compare `git diff --stat` before committing. Asset replacements should net negative on bundle size.

## Reporting

After the run, report:

- File-by-file before/after sizes for everything that changed.
- Total bundle delta in KB.
- Any files left untouched and why (e.g., `app.icns` — bundle-required format).
- The encoder settings used (especially HEIC quality if not q50, so the next person knows).
- Anything the visual review revealed (e.g., "had to bump to q60 for `thumbnails_dark` because gradient banding at q50").
