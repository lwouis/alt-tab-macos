# Partial thumbnail captures

The ScreenCaptureKit path separates image dimensions from alpha/content bounds. Image dimensions below
90% of the configured output width or height indicate a partial frame. Child windows are included in
the expected capture area, so a sheet changing its aspect ratio does not make it partial.

## Transparency and cached content

- Alpha alone cannot distinguish intentional transparent margins from a Stage Manager shelf image.
  A first full-size image establishes the window's reference coverage even if its drawn content is small.
- Sample-buffer captures use the metadata content rectangle converted to pixels with its display scale
  factor and clipped to the actual buffer. Invalid metadata falls back to image dimensions.
- Screenshot alpha is sampled off-main at 64 × 64. The threshold is one eighth of the peak alpha, with a
  minimum of one, so a low-opacity window is not mistaken for an empty capture. Fully clear images and
  images without alpha provide no content-bound evidence and use their image dimensions.
- An unfocused window's content is suspicious below 55% of its established reference coverage. Accepted
  background frames can improve this reference but cannot gradually lower it.
- The focused, non-minimized window may change its content coverage. It can become transparent and
  refresh the cached image even after the background retry budget was exhausted. Its image dimensions
  must still pass the partial-frame check.
- A changed logical size, display scale, fullscreen state, or expected output size starts a new reference
  and retry budget. Geometry is tracked even when thumbnail downscaling produces the same pixel size.
- Full-resolution preview checks compare normalized coverage with the thumbnail reference and do not
  consume thumbnail retry budget.

## Bounded recovery

- Suspicious frames never become acceptable merely because three retries were exhausted. Keep the last
  accepted image until a valid ordinary capture, a focused content change, or new geometry arrives.
- Allow at most three delayed retries with one pending per tracked window. Ordinary capture events
  cannot multiply pending retries or restart an exhausted budget.
- A valid frame or geometry change invalidates an outstanding retry. A token can be consumed only once.
- Discard a result if the logical size, display scale, or fullscreen state changed while it was in flight.
- Each tracked window owns its policy, so recycled WindowServer IDs inherit no exhausted budget.
- Retry callbacks obey the usual permission, switcher visibility, and screen-lock guards.

This is a cache-protection workaround. An initial shelf image may be accepted when no better reference
exists. Legitimate background content that becomes much smaller may remain stale until the window is
focused. Opaque padding and unavailable capture metadata remain indistinguishable from real content.
The policy does not change the capture backend or bypass screen-recording restrictions.
