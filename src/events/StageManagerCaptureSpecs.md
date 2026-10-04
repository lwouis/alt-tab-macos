# Stage Manager capture protection

The General setting is off by default. On macOS 26 and later, it is active only while `com.apple.WindowManager` reports `GloballyEnabled`. Older macOS versions keep the private `.fullSize` capture path.

Protected requests only capture the focused window of the frontmost application. Focus-triggered captures wait 250 ms for the stage transition. Other windows retain their last verified thumbnail, or use the existing app-icon placeholder until visited. Enabling protection discards thumbnails captured without protection and session preview frames, which could already be distorted.

Fresh Core Graphics bounds are checked off-main before creating the capture configuration and after the callback: reject missing, non-finite or non-positive geometry, or both dimensions below 70% of the normal Accessibility size. That size is obtained off-main through `AXCallScheduler` before capture. `Window.size` is refreshed by WindowServer and can itself be scaled; an unavailable AX size leaves the cache unchanged. ScreenCaptureKit output dimensions alone cannot detect a sidebar transform because it rescales to a configured canvas. Reject images smaller than 16 pixels on either axis or with fewer than 5% visible samples in a 16-by-16 alpha grid (alpha greater than 16).

Before publication on main, require the same mode generation, focus generation, tracked Window object, owner PID, and focused window. Full-resolution frames also require the original switcher session. A mode toggle invalidates queued results, including an observed off/on cycle. System state is read on demand, without a timer or preference writes. Failed geometry/pixel validation gets at most three 250-ms thumbnail retries while the same window remains focused. Partial-frame retry exhaustion cannot replace a protected thumbnail with a known partial frame.

The pure geometry, pixel threshold, and mode-generation contracts are covered by `StageManagerCapturePolicyTests`. Real Stage Manager animations, settings layout, and cold/warm switcher use need E2E validation, deferred for this draft.
