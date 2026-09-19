# Text scaling: the last accessibility item (P2-1)

- Status: implemented and installed on the Find N6 (CPH2765).
- Verified: `flutter analyze` clean, `flutter test` 99 passed (7 new), and on the
  device at `font_scale = 1.6` — with **zero** overflow or layout errors logged,
  and the font setting restored to 1.0 afterwards.

## The defect

App names and constellation titles are painted into canvases rather than laid out
as widgets. A `TextPainter` defaults to `TextScaler.noScaling`, so those labels
stayed at 1.0x while every real `Text` on the same screen grew with the system
font setting — a half-scaled interface: chips scaled until their fixed-height
rows clipped them, while the app names stayed tiny.

## What changed

**Painted text now follows the system scale.**

- `app_entry.dart` — `ensurePainters` takes a `TextScaler`, lays the label out
  with it, and invalidates its cache when the scale changes (the painters are
  cached per app, so without that a scale change would keep the old layout).
- `constellation.dart` — same for the title and the app-count badge.
- `bouncing_apps_painter.dart` / `galaxy_custom_painter.dart` accept the scaler
  and forward it, and both now repaint when it changes.
- `galaxy_interactive_canvas.dart` / `cosmic_lock_screen.dart` supply
  `MediaQuery.textScalerOf(context)`, which also registers the dependency, so a
  scale change rebuilds the canvas.

**The icon glyphs deliberately do not scale.** Where an app has no decoded icon
the bubble draws its `fallbackIcon` glyph, and constellation pods draw their
emblem. Those are sized to the node they sit in — scaling them with the font
would push them out of their own bubble. Only words the user reads scale. There
is a test for each side of that line.

**Rows that clipped scaled text.** In `search_overlay.dart` the search capsule's
fixed 50 and the category filter bar's fixed 44 are gone. The capsule uses a
min-height. The filter bar cannot: it wraps a *horizontal* `ListView`, whose
cross-axis needs a bounded height (a first attempt with `shrinkWrap` failed with
"Horizontal viewport was given unbounded height" — caught by the existing tests).
It is now sized from the scale, bounded at 1.8x so a large setting cannot push
the list off screen.

`answer_body.dart` used a raw `RichText`, which also defaults to no scaling, so
search answers ignored the setting while the surrounding panel scaled.

## Verification

On the device with the system font at **1.6x**:

- lock screen: the canvas-painted bubble labels grow from ~10px to ~16px, along
  with the HUD, chips and hint text;
- cover screen: shelf labels, section headings, chips and the search pill all
  grow;
- `adb logcat | grep -icE "overflowed|RenderFlex"` → **0** on both surfaces.

Screenshots: `.agent-shots/` captures at 1.6x and after restoring 1.0.

`test/text_scaling_test.dart` (7 tests) holds the contract: a scaled label lays
out wider; changing the scale relayouts instead of reusing the cached painter;
the fallback glyph and the constellation emblem do *not* scale; and both canvases
pass the ambient scaler from the widget tree into their painter.

## Honest limitations at large scales

Observed on the device at 1.6x, not hidden:

- **Lock screen bubble labels overlap.** The bubbles cluster, and wider labels
  collide ("TextNow" over "Clone Phone"). They remain individually legible, but
  a very large font on a dense physics field is inherently crowded. A future
  pass could hide labels below a zoom/cluster threshold, or lay them out with
  collision avoidance.
- **Cover screen tile labels truncate** ("ESSE…", "Messa…", "YouTu…") because
  the grid's tile width is fixed. The standard fix is to drop the column count
  as the scale rises, so a larger font gets wider tiles instead of ellipses.

Both are cosmetic trade-offs at the extreme end of the setting, not clipping or
lost content, and neither appeared at 1.0x.

## Still open on accessibility

- **The lock screen SHAKE control** is ~26dp tall. Giving it a button trait was
  the accessibility fix; growing it shifts the header row and therefore the
  clock, which is a deliberate layout change rather than part of this pass.
- **The galaxy has no semantic zoom/pan affordance** — nodes are reachable, but
  a reader cannot tell where they are in a pannable field or recentre it.
