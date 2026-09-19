# Accessibility P0: canvas-painted surfaces are reachable by a screen reader

Two surfaces had the same defect: everything on them is painted into a canvas, so
a screen reader found no node for any app. Both are fixed and verified against
the device's real accessibility tree.

- Status: implemented, installed on the Find N6 (CPH2765).
- Verified: `flutter analyze` clean, `flutter test` 89 passed (10 new), on-device
  `uiautomator dump` shows the app nodes on both surfaces.

## Surface 1 — the galaxy home screen (the audit's P0)

Everything on the unfolded home screen is painted into a single `CustomPaint`
(`galaxy_interactive_canvas.dart`), and apps were reachable only through manual
coordinate hit-testing in `_hitTestApp`. Labels are drawn by `TextPainter`, so
the widget tree contained no node for any app. With TalkBack running, the
primary task — launch an app — was impossible: the entire surface was one
unlabeled graphic. `Semantics(` appeared 8 times in the whole repo, none of them
in a canvas file.

## Surface 1 fix

`lib/canvas/galaxy_interactive_canvas.dart`

1. **A semantic node per target**, positioned from the same
   `camera.worldToScreen` mapping the painter uses, so the focus rectangle sits
   exactly over the painted bubble.
   - Each open-constellation app: label = app name, hint "Open app",
     `onTap` → launch.
   - Each constellation hub: label = name, hint "<n> apps. Double tap to
     open." / "Open, <n> apps. Double tap to close.", `onTap` → expand/collapse.
   - Every rectangle is grown to a 48dp minimum, because a reader explores by
     touching a point.
2. **One shared activation path.** `_handleTapUp`'s inline app and constellation
   handling was extracted into `_activateApp` / `_activateConstellation`, now
   called by both the gesture handler and the semantic actions, so a TalkBack
   activation cannot drift from a finger tap.
3. **Collapsed constellations report the hub, not its apps.** When a
   constellation is closed its apps are condensed onto one point; announcing
   them all at the same coordinate would be worse than useless. A collapsed
   constellation is reachable through its hub — which is also the only way in.
4. **Only what is on screen.** Nodes are filtered to the viewport, so a reader
   never focuses off-screen content and the node count stays bounded.
5. **Gated on the reader being active** (`SemanticsBinding.semanticsEnabled`) —
   the layer is skipped entirely for users who cannot benefit, and a
   `addSemanticsEnabledListener` rebuild means switching TalkBack on while the
   home screen is already up takes effect immediately.

Two traps found while building it, both worth remembering:

- **`IgnorePointer` breaks accessibility.** The obvious way to keep an overlay
  from stealing canvas gestures sets `isBlockingUserActions`, which strips the
  tap action off every descendant: the nodes appeared with correct labels and
  `actions=0`, so a reader could *hear* an app but not open it. The nodes are
  bare `SizedBox`es, which are not hit-testable, so no wrapper is needed at all.
- **`semanticsEnabled` is true by default in the Flutter test binding.** A test
  asserting "no nodes when no reader is running" cannot be written that way here;
  the gate is verified by reading the getter, not by a widget test.

## Surface 1 verification

On device, unfolded via the app's own posture controls, `uiautomator dump` —
which reads the same tree TalkBack uses — now reports:

```
Chrome, Open app          Waze, Open app        YouTube, Open app
Phone, Open app           Gmail, Open app       Messages, Open app
Essentials, Open, 6 apps. Double tap to close.
Studio, 8 apps. Double tap to open.
Connect, 8 apps. Double tap to open.
```

Those six apps match the six visible bubbles on screen exactly. Before this
change the surface contributed no app nodes.

`test/galaxy_a11y_test.dart` (5 tests) holds the contract:

- every app of the open constellation is exposed;
- a collapsed constellation exposes its hub but not its apps;
- activating an app node launches **that** app, and no other;
- nodes carry a tap action and a hint that says what they will do;
- nodes sit over their apps **and do not swallow canvas touches** (a real tap at
  the node's position still reaches the gesture handler).

## Surface 2 — the lock screen bubbles

The same defect on the surface used most: the bouncing apps are painted into
`bouncing_apps_painter.dart`, so a reader could not launch an app from the lock
screen. The chrome around them (chips, shortcuts, swipe) was already reachable,
which is why the audit ranked the galaxy as the P0.

### Surface 2 fix

`lib/features/lockscreen/cosmic_lock_screen.dart`

1. **One node per bubble**, at the position the canvas paints it, label = app
   name, hint "Open app", `onTap` → the existing authenticate-then-launch path.
   Rectangles use the same generous hit radius as touch and grow to a 48dp floor.
2. **The simulation is held still while a reader is active.** A moving target is
   not merely hard to touch — its rectangle would have to be rebuilt every frame
   to stay truthful, which is the per-frame work the performance pass removed.
   Holding it still solves both. `_syncPhysicsLoop` now stops the ticker for
   reduce-motion *or* an active reader, and drags still repaint via `markDirty`.
   Nothing changes for a sighted user: the drift returns the moment the reader
   is switched off.
3. **The SHAKE control** gained a real button node. It previously exposed the
   text "SHAKE" with no button trait, so a reader was never told it was
   actionable. The action is declared on the `Semantics` rather than left to the
   gesture detector, so the node a reader lands on carries both the label and
   the action.

### Surface 2 verification

`uiautomator dump` with the lock panel up reports 12 app nodes, matching the 12
visible bubbles exactly:

```
Contacts, Open app     Camera, Open app     Browser, Open app    Signal, Open app
Home, Open app         Brave, Open app      ABP for Samsung Internet, Open app
Clone Phone, Open app  Chrome, Open app     Contacts, Open app
TextNow, Open app      Messages, Open app
```

plus `Scatter apps` as an actionable button. `test/lockscreen_a11y_test.dart`
holds the contract: every bubble is exposed; nodes are actionable and hint
"Open app"; activating one opens that app and not another; the bubbles are held
still while a reader is active; SHAKE is announced as a button.

Note that semantics are enabled by default in the Flutter test binding, so
**every existing lock screen test now runs with the simulation held still** —
the whole suite was re-run to confirm that changes no behaviour under test.


## Still open on accessibility

- **Touch targets (P1-6)**: dock buttons 36dp, A-Z scrubber ~13dp, cover chips
  40dp — below the 48dp baseline. The SHAKE control now has a button trait but
  its ~26px pill is still under the minimum, which is a layout change.
- **Text scaling (P2-1)**: canvas `TextPainter` labels ignore the system font
  scale; fixed-height chip rows clip text that does scale.
- **The galaxy canvas has no zoom/pan affordance for a reader** — the nodes are
  reachable, but a reader cannot tell where they are in a pannable field, nor
  recentre it. Possible follow-up: a semantic action for "recenter galaxy".
- Reduce-motion (P2-2) is done — see `perf-architecture.md`. The lock screen now
  also holds still for an active reader, for the same reason.

