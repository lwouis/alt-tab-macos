# Localized native illustrations

Each illustration is one self-contained SVG, including English text, fonts, positions,
alignment, clipping, and optional `data-max-width` / `data-min-font-size` fit rules.
`data-i18n` is a stable text identifier. The build-time compiler preserves it in shared drawing instructions. The app resolves the default English value
through its string table; tests can supply strings by identifier. No translated asset
copies or native text overlays are required. Embedded JPEG window content is allowed;
frames, icons, switchers, and text remain vector artwork.

Repeated images and geometry are shared through local definitions and references within
each SVG. References must resolve to an existing ID, and an SVG must not repeat an embedded
JPEG payload. Native rendering of shared images must match inline images, including translated
and scaled placements inside clips. Photos are cropped and sized offline for their largest
native view at Retina density; `data-raster-width` records that scene-wide pixel budget.
The runtime loader does not preprocess or resize embedded JPEG data.

`scripts/assets/compile_illustrations.py` compiles the supported SVG subset into a binary
property list and separate, content-addressed JPEGs. It shares identical drawing nodes,
paths, gradients and JPEGs across all illustrations. Unsupported drawing features and
external resources fail compilation instead of silently disappearing. `--check` verifies
that the checked-in native resources still match the canonical SVGs; the local build and
test entry points run it. SVG authoring files are not copied into the application bundle.

`IllustrationDrawer` decodes the instructions once, creates reusable Core Graphics paths,
gradients and JPEG images, and prepares Core Text lines for each localized image. Drawing
replays those objects through NSCustomImageRep, preserving vector scaling at the requested
size. It does not load SVG, PDF, WebKit, or rasterize a complete illustration resource.
The app targets macOS 12.0. The renderer was tested on 12.7.6, 13.7.4 and 27.0.1; this does
not establish testing on 12.0 or Intel. The pre-12.3 permission-capture fallback is retained.

Translated strings are literal Core Text content. Fit rules shrink to the source's minimum
font size, then truncate at a Swift Character boundary with an ellipsis. The same font is
used for measuring and drawing. Font fallback and Unicode shaping remain native. Zero
kerning and centered offsets based on the floored half-width of the glyph outline bounds
preserve the approved native SVG placement. A 116-case pixel comparison covers light/dark,
long text and Arabic.

Optional `data-rtl-transform` values move comparison groups and reverse their arrow without
mirroring window contents. `data-dark-fill` changes only declared text colors. Both are
compiled from the artwork, not hardcoded per illustration in Swift. Prepared images are
cached by bundle, resource, locale, appearance, direction and text overrides, bounded at
48 entries. Shared drawer caches are bounded at four bundles. Drawing an existing image
does not repeat string substitution or fitting. Illustrations stay outside switcher input.

All Settings appearance cards, Customize previews, Day 4 cards, Pro feature comparisons,
and permission scenes use these resources. The rabbit and app/menu icons remain branding;
interactive keycaps, success ticks, speech bubbles and ordinary controls remain native.
Pro badges are native ProBadgeView overlays, never part of SVG artwork. Comparison headings
and captions remain SVG text. An optional ID-to-string override supplies evidence-dependent
wording (such as “With Pro”); overrides participate in the image cache key.

Every compiled resource is checked for native vector drawing. The compiler rejects unsupported
features and external resources. Canonical sources retain bounded text metadata and no Pro badge. The two comparison desktops remain stationary;
only the switcher is scaled for Auto Size. All three Settings styles are reviewed at native sizes.
Switcher illustrations select the second item when available, consistently across Show/Hide
and comparison variants. Search places its field inside the switcher above two matching
Japan windows, compared with twelve smaller unfiltered windows. Shortcut captions sit
below their examples, with a clear gap after the continuation dots. Comparison captions share
a 218-unit baseline. Search shows tightly bounded yellow query matches in the two result
titles, without a caret in its query field. Permission scenes retain their content scale with 12 extra points of desktop padding
on each side, and use the same centered shaft-and-chevron arrow as the comparisons.
English example titles fit at their authored font sizes without truncation; use shorter examples
instead of relying on localization fitting. Customize Show/Hide pairs retain the same scene.
The visible state outlines the affected accessory in red; the hidden state removes both the
accessory and its outline. Status and Space indicators are circled at the title's trailing edge.
The recording permission comparison shows app icons and names before permission, then window
previews and concrete window titles afterward.
App Icons uses a 24-unit inset around the visible 60-unit icon silhouettes on every side.
Its icon clips and borders share a rounded continuous contour. The selection centerline
is offset four units along that contour's normals, keeping an even gap through the corners.
The 272-by-108 switcher extends the same squircle profile across its straight edges.
The middle icon is selected so its title stays clear of the switcher's rounded corners.
The selected title fits inside the bottom inset, with a small gap below the selection outline
and at least four units below the text. Space numbers use explicit positions based on their native glyph
outlines; text advance widths alone do not visually center the digits.

Illustrations are decorative and excluded from the accessibility tree. Their surrounding headings,
instructions and interactive controls provide the meaning without narrating example window content.

All example window names, page content and comparison captions have entries in all 21 app
language tables. Short examples must fit without truncation in every authored text slot.
Safari branding, physical keycap legends and numeric Space labels are language-independent.
The coverage test reads the shipped language tables and checks every compiled text node.

Search result titles are translated as complete phrases, so word order can vary by language.
`data-highlight-query` and `data-highlight-i18n` identify the localized matching word;
`data-highlight-fill`, `data-highlight-text-fill` and `data-highlight-layout` own its colors
and baseline-relative offset, height, horizontal padding and corner radius. Native drawing
uses shaped glyph bounds to position the highlight, including RTL text and combining marks.
`data-preview-only` shapes/text preserve the English highlight in a standalone SVG editor;
the compiler omits them because runtime highlighting follows the localized title instead.
