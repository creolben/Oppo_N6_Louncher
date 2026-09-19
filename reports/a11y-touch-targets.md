# Touch targets: the P1 accessibility pass

- Status: implemented and installed on the Find N6 (CPH2765).
- Verified: `flutter analyze` clean, `flutter test` 92 passed (3 new), and the
  node bounds were **measured on the device** with `uiautomator dump`.

## The defect (audit P1-6)

Primary controls were below the Android 48dp minimum, and the small ones were
the most-used ones. Most of them were *visually* small but padded, so the fix is
mostly about the hit area rather than the drawing.

## What changed

| Control | Before | After |
|---|---|---|
| Cockpit dock icons (`foldable_cockpit_bar.dart`) | 36dp | **52dp** measured |
| Comet / web-search button | 36dp, `tapTargetSize: shrinkWrap` (explicitly opting out) | 48dp |
| Cover dock icons | 36dp | **52dp** measured |
| Cover search pill | 46dp | **48dp** measured |
| Cover card action buttons, chips | 40dp | 48dp |
| Tabletop search pill | 36dp + no label | **48dp + labelled** ("Search apps") |
| Tabletop chip bar | 36dp (clipped scaled text) | 48dp |
| A-Z scrubber rail | 27 taps on ~13px glyphs | see below |
| `CoverStyle.touchTarget` token | 44 | 48 |

### The A-Z scrubber

This was the worst: 27 hand-aimed taps on 9px glyphs. It is now **one drag
surface** — the whole rail maps a vertical position to a letter — with a
**48dp-wide corridor** over a 324dp-tall run. Measured on device: each letter is
now 42.5dp wide (from ~13dp), and the drag corridor spans the full rail.

Letters stay individually tappable, deliberately: that is what a screen reader
navigates, so replacing 27 letter buttons with one drag node would have made the
reader's job worse. The drag is for fingers; the letters remain for TalkBack.

## Two bugs found on the way

- **A stranded timer.** The scrub feedback used a fire-and-forget
  `Future.delayed(800ms)` and was never cancelled, so it outlived the widget.
  It was guarded by `mounted` (no crash), but it leaked past teardown — and it
  made the scrubber untestable, since the test binding fails on a timer pending
  after disposal. Now a `Timer` cancelled in `dispose`.
- **A guessed height.** The rail's total height was computed by hand and forgot
  the container's 1.6px border, overflowing by exactly that. It now sizes
  itself, and the drag mapping measures against the border and padding it
  actually has. Worth noting the old code hid the same class of problem behind a
  `NeverScrollableScrollPhysics` scroll view that silently clipped instead of
  reporting the overflow.

## Verification

Measured on the device rather than asserted. `uiautomator dump` node bounds,
48dp = 156px at this panel's 3.25 density:

```
OK  Search Apps        169x169px  (52x52dp)
OK  Fold Simulator     169x169px  (52x52dp)
OK  Lock Screen        169x169px  (52x52dp)
OK  Launcher Settings  169x169px  (52x52dp)
OK  search pill       1036x156px  (319x48dp)
OK  Open Phone         214x221px  (66x68dp)
```

`test/scrubber_test.dart` (3 tests) covers the rail: dragging the corridor
scrolls the list; a drag starting 47dp from the edge still lands on it (the
corridor really is 48dp); and tapping the `Z` letter still jumps the list.

## Still open

- **Text scaling (P2-1)** is the remaining accessibility item: canvas
  `TextPainter` labels ignore the system font scale, and fixed-height rows clip
  text that does scale. The chip bars raised here are part of that and are now
  48dp, but the painters still need the ambient `textScaler` threaded through.
- **The lock screen SHAKE control** has a button trait now, but its pill is
  ~26dp tall. Growing it to 48dp shifts the header row and therefore the clock
  on a screen whose layout was deliberately left alone — worth doing as a
  deliberate layout change rather than smuggled into a touch-target pass.
- **The galaxy has no semantic zoom/pan affordance** — nodes are reachable, but
  a reader cannot tell where they are in a pannable field or recentre it.
