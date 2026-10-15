# Search and extra-shortcut discovery

One local, nonactivating child panel belongs to one switcher session. The isolated rabbit introduces a benefit headline and a separate keyboard instruction. It is placed above the switcher on its actual screen, within the visible frame. When the switcher leaves no room above it, the bubble overlaps the switcher's bottom edge instead; nothing appears only when the bubble is larger than the screen. The window preview is ordered below the switcher and never affects placement. The pointer over the bubble does not hover, select or middle-click-close the tile beneath it. It never resizes the switcher or takes keyboard focus.

The shared mascot is bundled without outer transparent margins at 152 × 140 pixels,
covering its 76-point slot at Retina resolution in discovery, feedback and trial messages.
It loads directly without runtime cropping and preserves the complete artwork.

The existing Search history is the shared budget: at most three exposures, 72 hours apart, days 2–11 except day 4, with no discovery after purchase. No independent budget is added for shortcuts. Unknown adoption history is ineligible. The existing showSearchHint preference and persistent Pro opt-out suppress both tips. Each feature stops after actual use. Dismissal disables discovery. Preview mode writes nothing.

Search requires at least eight relevant windows, inactive Search, and a configured key that has a representation on the current keyboard and does not conflict with the current interaction. Extra-shortcut discovery requires at least two relevant active-app windows and another app, a configured extra slot targeting the active app, the same other window filters, the same hold modifiers, and no conflicting key. It names the actual active app. It never assumes Option or the grave key is configured.

The global next-window matcher permits switching to another indexed shortcut during the same session. Only the newly active slot's release action can commit the selected window. Both production-shaped bindings and same-session identity are tested.

Presentation waits one second and a 500ms navigation quiet period. Onboarding, queued Pro prompts, menus, modal or permission UI, active Search and locked sessions block it. Dismissal, preference changes, screen/Space changes and adoption cancel it. Rendering and ordering are deferred past the switcher's visible work; no polling, server requests or telemetry are introduced.

SearchDiscoveryTests cover history migration, shared cooldown/cap, per-feature adoption, keyboard labels, preview isolation, click/drag routing, geometry and light/dark/high-contrast native rendering. The period counter elsewhere describes a started search; it does not claim a successful result.

The bubble reuses the switcher's effect kind and appearance, including system transparency accessibility behavior. A single closed silhouette joins the tail and rounded body; there is no border across the tail's base. A 12-point gap separates the 76-point rabbit from the bubble. Width hugs measured text up to 560 points and the screen limit; AppKit measures wrapped label height including the keycap attachment. RTL mirrors the silhouette and spacing. The material is reused until its kind changes, and presentation remains deferred outside the switcher's critical path.
