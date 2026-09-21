# Home surfaces

Mode: Operate

Scope: unfolded animated home, folded cover home, tabletop home, and native handoff backgrounds.

Audience and job: a foldable ColorOS user launching and organizing apps many times each day. The home must remain legible at a glance, reachable one-handed where appropriate, and unmistakably animated without becoming visually noisy.

Constraints: preserve all existing motion geometry, controllers, gestures, hit testing, fold behavior, callbacks, Android security boundaries, and user-provided ambient-wallpaper work. Use no proprietary ColorOS assets.

## Direction contract

**THESIS:** Luminous Horizon turns the constellation into a calm field of depth and light, refusing the incumbent cockpit of neon outlines, instrument grids, and nested icon frames. Motion remains the product; chrome recedes.

**OWN-WORLD:** An original Aquamorphic world uses ink-blue OLED depth, a low cobalt horizon, drifting aqua and orchid light, milky translucent shelves, soft white typography, and unframed squircle app icons. Accent color identifies state, never every edge.

**STORY:** The clock establishes orientation, apps float as the primary content, and compact utilities wait at the edges. A user can read, launch, search, recenter, edit, lock, and change posture exactly as before, with less visual competition.

**FIRST VIEWPORT:** A large quiet clock sits at top left; a compact glass utility strip sits top right. The living constellation occupies the uninterrupted center over a fluid dawn-like field. A single translucent dock floats above the navigation inset, showing icon-first controls and horizontally scrollable constellation shortcuts without clipped labels.

**FORM:** Grounded direction 7, a seamless cyclorama translated through the user-pinned ColorOS-inspired constraint; horizon light carries hierarchy while constellation depth carries navigation. Seed key: 68a09476.

**FINISH:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Signature interaction: existing constellation expansion pulls a colored light field into focus while app icons keep their current orbital choreography; the surface changes atmosphere, never geometry.

Unresolved: exact OEM visual parity is intentionally out of scope because the implementation must remain original and portable across ColorOS builds.