# README artwork

`main.svg` is the self-contained “Promesse centrée” composition: the website's
headline and subtitle, a download button, download and GitHub star counts, and
an eight-second looping window-switching demonstration. The README links the
whole image to https://alt-tab.app/.

Regenerate it with Python's standard library:

```sh
python3 scripts/build_readme_svg.py
```

The generator preserves the counts in `main.svg`. Release automation updates
their `<!--downloads-->` and `<!--stars-->` markers. To set counts manually:

```sh
python3 scripts/build_readme_svg.py --downloads 9.4M --stars 16K
```

Source artwork was copied from the `alt-tab-website` repository:

- `window-demo.svg`: `frontend/public/hero/flow.en.svg`.
- `app-icon.webp`: `frontend/public/icon-small.webp`.
- Copy: `frontend/_data/i18n/en/home.yml`.
- Button and social-proof artwork: `frontend/_includes/components/download-button.html`,
  `download-stats.html`, and `star-cluster.html`.

The SVG is displayed as an image, so the animation must use native SVG animation,
with no scripts or external resources. Keep the demo inline in the generated
image and its raster artwork embedded. The website's playback controls are not
part of the image. Check the generated image in an `img` element when changing
the artwork; opening the SVG as a document exercises a different rendering mode.
