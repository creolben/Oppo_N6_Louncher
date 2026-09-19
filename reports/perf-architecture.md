# Performance architecture pass

- Status: implemented and installed on the Find N6 (CPH2765).
- Verified: `flutter analyze` clean, `flutter test` (79 passed), `flutter build apk --debug` succeeds, app launches with no exceptions and no icon-decode failures, lock screen renders with real icons.
- Scope: the performance architecture items from `reports/launcher-critique.md`, in the order the critique recommended. The lock screen's visual design was deliberately left intact — the physics field, chips, shake and shortcuts all still behave as before.

## On-device measurement

Lock screen visible and animating, CPU seconds read from `/proc/<pid>/stat` over a
10-second window, device otherwise idle.

| Build | CPU (share of one core) |
|---|---|
| Per-frame rebuild (baseline) | **143.8%** |
| Repaint-only (this change) | **74.0% / 80.0% / 85.1%** (mean ~80%) |

That is roughly **1.8x less CPU** while the physics field animates: the tree
rebuild per frame was the dominant cost, not the paint.

Caveats: the baseline was sampled once (the fixed build three times), and
`dumpsys gfxinfo` does not capture Flutter engine frames — it recorded 1 frame in
6 seconds — so this is process CPU rather than frame-time percentiles. The
backgrounded-idle saving is not attributable to this measurement.

## 1. Lock screen: repaint instead of rebuild (was P1-1)

The lock screen ran `setState(() {})` inside its physics ticker, so a ~330-line widget tree was rebuilt at up to 120Hz, and the slide animation did the same for its 360ms. The dead `animationProgress` painter argument confirmed the canvas only ever needed the physics state.

- `bouncing_physics_engine.dart` — `BouncingPhysicsEngine` is now a `ChangeNotifier` and notifies at the end of `update()`, plus on `initializeBubbles`/`resize`/`triggerShakeScatter`. New `markDirty()` covers direct manipulation.
- `bouncing_apps_painter.dart` — takes `super(repaint: physics)`, dropped the unused `animationProgress`, and `shouldRepaint` now compares `draggedBubble`/`physics` instead of returning `true` unconditionally.
- `cosmic_lock_screen.dart` — the per-frame `setState` is gone; the canvas sits in a `RepaintBoundary` so simulation frames repaint one layer. Panel movement moved to a `ValueNotifier<double>` (`_panelOffset`) driving a `ValueListenableBuilder` around only the `Transform`/`Opacity`, so drags and the unlock slide no longer rebuild the tree either.

Cost per simulation frame is now one canvas repaint instead of a full-tree rebuild plus paint.

## 2. Hidden surfaces stop animating (was P1-2, P2-3, P2-8)

- `main.dart` — the launcher content (galaxy canvas, cover stardust, cockpit bar, comet orb) is wrapped in `TickerMode(enabled: !(_isLocked || _isSearchOpen || _isCometSearchOpen))`. An invisible 120Hz starfield behind an opaque lock panel no longer burns battery, and the search blur no longer re-filters a moving background every frame.
- `folded_cover_screen.dart` — the stardust pulse painter is wrapped in a `RepaintBoundary` so the breathing no longer repaints the scrollable body with it.

Folding while locked can leave a transition paused until unlock; the lock panel is opaque over it, so nothing is visible and the transition completes on unlock.

## 3. Reduce-motion honored by the big loops (was P2-2)

`MediaQuery.maybeDisableAnimationsOf` now gates the three perpetual loops, each synced in `didChangeDependencies`:

- galaxy render loop — stops and paints one resting frame;
- cover stardust pulse — rests at a mid value;
- lock screen physics ticker — holds the bubbles at rest.

Drags still repaint with the ticker stopped, because drag input pushes through `markDirty()`. The comet orb already honored the setting.

## 4. Icon pipeline (was P1-3, P2-5, P3-4)

- `MainActivity.kt` — `drawableToByteArray` now renders every icon into a 96x96 bitmap and recycles it, instead of shipping PNGs at intrinsic size (432px for adaptive icons on this device). This is where the channel cost and the `Image.memory` cache bloat actually came from.
- `launcher_bridge.dart` — a static `_iconCache` keyed by package name means a package-change event only decodes genuinely new apps; decoding runs through a 4-wide window instead of one un-awaited future per app; the scan awaits decode so icons are ready rather than popping in after first frame; `_pruneIconCache` drops uninstalled packages so the engine can reclaim them. Nothing is disposed eagerly, because a widget painting the previous list may still hold an image.

The 11 `Image.memory` call sites needed no change: they were decoding full-size PNGs, and the source no longer sends any.

## 5. Tabletop clock (was P3-1)

`tabletop_cockpit_view.dart` rebuilt once a second unconditionally; it now repaints only when the visible minute rolls over, matching the cover and lock screens.

## New tests

`test/lockscreen_physics_test.dart` guards the architecture the canvas now depends on — if the engine regresses to a plain class, the bubbles would silently freeze while every behavioural test still passed:

- notifies listeners per simulation step;
- notifies on a direct-manipulation repaint request;
- notifies when a shake scatters the field.

## Not done in this pass

- **Idle-to-zero on the visible galaxy/cover loops.** They still animate whenever visible, by design (perpetual orbit is the product's identity). Pausing when hidden is done; fully idling an on-screen launcher would change the look.
- **Per-frame gradient allocations in the paint loops** (was P2-4). With the rebuild removed, paint is the remaining per-frame cost; caching gradients keyed on position/radius buckets is the next measurable win.
- Everything from the critique's a11y P0 (semantics overlay on the galaxy canvas) and the daily-driver feature set (widgets, real badges, wallpaper/Material You) — those are the next milestones.
