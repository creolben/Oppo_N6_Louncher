# ChronoFold launcher — combined critique (design + technical + features)

- Method: dual-agent (A: design-director review `7cd68772` · B: native technical audit `cb3432b1`), synthesized by the parent with an independent features analysis.
- Target: whole launcher (`lib/`), scored against the impeccable native references for Android (OPPO Find N6, ColorOS 16, 120Hz OLED cover 1140x2616 / inner 2248x2480).
- Review mode: **Operate** — the visitor completes tasks (launch an app, search, check the time).
- Assessor A's screenshot measurements were independently verified where possible: its claim that `.agent-shots/polish/09-lock-final.png` and `08-cover-final.png` are the same surface was re-checked by BMP conversion — only ~0.8% of bytes differ, confirming the goldens are mislabeled (both show the cover screen). A's code-grounded findings were independently confirmed by B and the parent.

## Scores

| Assessment | Score | Band |
|---|---|---|
| Design (Nielsen 10, avg) | **1.7 / 4** | — |
| Technical audit | **10 / 20** | Acceptable — significant work needed |

Technical dimensions: Accessibility 1, Performance 2, Appearance & Theming 2, Platform Conformance 2, Adaptivity 3.

Nielsen: visibility-of-status 1, error-prevention 1, help/docs 1; user-control 2, match-real-world 2, consistency 2, recognition 2, flexibility 2, minimalism 2, error-recovery 2.

## The verdict

The craft floor is high — real design tokens on the cover screen, a genuinely good repaint architecture on the galaxy canvas, honest platform probes, foldable integration far beyond typical Flutter apps. But **the budgets are inverted**: the brightest pixels, the most motion, and the richest vocabulary are spent on decoration, while the primary controls (dock, search pill, unlock hints) are the dimmest elements on screen, the lock screen carries ~20 interactive targets on a security surface, and the launcher-features an Android user judges a home app by (widgets, badges, wallpaper) are absent.

Platform conformance verdict (B): **FAIL as a full native launcher; PASS as an exotic launcher shell.**

## Look

- **Specificity is real but undistributed.** The physics bubbles, orbit arcs, constellation filaments, posture-aware surfaces could not belong to another product. The control chrome (capsule pills, 18%-alpha glass, cyan accent, 10px uppercase labels) is generic premium-dark that any fintech could ship. The specific material lives in the canvases; the generic grammar owns every control surface.
- **Luminance inversion (measured).** Cover search pill: p90 = 19/255 (effectively invisible); dock icons peak 131/255 — dimmer than the 10.5px app labels; while clock glow, orbit arcs and auras take the luminance budget. The efficient paths are the least findable elements on the device.
- **The lock screen is a playground on a security surface.** 6 category chips + SHAKE pill + ~11 bouncing, flingable bubbles + fake battery + hint + shortcuts ≈ 20 interactive targets; auras measurably wash into the chip row; a tap drifting >12px becomes a drag that launches whatever bubble was under the thumb. Mis-tapping SHAKE scatters the entire field.
- **Three taxonomies organize the same apps** (lock categories vs cover sectors vs galaxy orbits), and the empty-category fallback silently shows *all* apps — a filter that appears active but lies.
- **Two clocks in different formats** (system vs zero-padded cosmic), and the hero clock is w100 hairline with more glow than stroke.
- **Fake status:** the lock screen battery is a hardcoded `Text('92%')` with a charging glyph, on the most-glanced surface of a phone.
- Strengths: the cover screen is the disciplined model (tokens, tabular figures, orphan-aware grids, pressed-state feedback, screen-reader long-press routing); the comet surface is honest by construction (chooser-aware labels, failure panels, citation chips).

## Performance

- **Lock screen calls `setState` every frame** (cosmic_lock_screen.dart:131, 314-317), rebuilding a ~330-line tree at up to 120Hz; `BouncingAppsPainter` has `shouldRepaint => true` and no `RepaintBoundary`. The correct pattern already exists in-repo (galaxy canvas: `CustomPainter(repaint: notifier)`).
- **Nothing ever idles.** Galaxy render ticker never stops; the physics engine re-energizes resting bubbles forever (`minDriftSpeed` floor); cover stardust pulses with no boundary; and while locked, the hidden galaxy canvas keeps ticking behind the opaque lock overlay — two full-screen loops at once on an OLED.
- **Icon pipeline:** every icon PNG-encoded at intrinsic size and marshaled in one platform-channel message, then all decoded concurrently at 96x96 with no cache and no disposal — repeated wholesale on every package event. Widget grids then re-decode the raw PNG via `Image.memory` (11 sites) while the decoded 96x96 `ui.Image` sits unused.
- **Full-screen 20-sigma blur** over the still-animating galaxy in search; per-frame gradient allocations (~8,600 objects/sec) and per-label `saveLayer`s in paint loops; two full galaxy canvases mounted during posture transitions.
- Good: galaxy repaint architecture, self-stopping kinetic camera ticker, virtualized lists, background-thread app scan, minute-gated clocks, idle throttle.

## Features

Present and good: posture-aware surfaces (folded cover / galaxy / cockpit), constellation organization with persistence, A-Z scrubber drawer-in-search with escalation to web search, honest intent handoffs, long-press app actions (hide / info / uninstall).

The launcher paradox — verified gaps:

1. **No widget host at all** (no `APPWIDGET` binding anywhere) — the single biggest launcher feature gap.
2. **Notification badges are fixtures** — `notificationCount` is only set in `_generateMockApps()`; no `NotificationListenerService`; the painter's badge pips can never fire on-device.
3. **Wallpaper is suppressed** (`windowShowWallpaper=false`) and there is no Material You dynamic color.
4. **No first-run flow** — `isDefaultLauncher()` / `requestDefaultLauncher()` exist in the bridge but are never called; nothing sets the launcher as default or teaches the gesture vocabulary.
5. **Web search answers are fixture-backed**, not live (documented in code).
6. **No in-app settings** — the settings button deep-links to system HOME settings; no theme, gestures, or organization preferences.
7. **No backup/restore** of the galaxy configuration.
8. **Dev tooling in production** — fold simulator in the dock, `OPPO N6 FLEX MODE` badge, release signed with the debug key.
9. **Accessibility P0:** the unfolded home screen is a semantics-free canvas — TalkBack cannot see or launch any app node; canvas text ignores system font scale; dock buttons are 36px, scrubber letters ~13px.
10. **The self-lock is friction without security** — the launcher locks itself on every backgrounding, and swipe-up-to-enter authenticates no one (app launches are properly gated; the overlay is not).

## Suggested roadmap

**Quick wins (hours):** wire real battery state or delete the row · remove SHAKE + category chips from the lock · build-flag the fold simulator · 48dp targets on dock/chips/scrubber · dispose old `ui.Image`s · standardize on clamping scroll physics · make the empty-category filter show an explicit empty state.

**Structural (days):** lock-screen repaint via the in-repo `RepaintBoundary` + listenable pattern · idle/sleep states for every loop, pause canvases hidden behind overlays · icon pipeline (native-scale, raw bytes, paged decode, cache by package+version) · a semantics overlay for the galaxy canvas · thread `textScaler` into painters · gate perpetual motion on reduce-motion (CometOrb pattern) · real battery + launch-result feedback on the galaxy.

**Strategic (weeks):** decide the product stance — widget hosting, wallpaper + Material You fallback, real badges; unify on one taxonomy; write the first-run flow (the bridge methods already exist); isolate the deprecated `FingerprintManager` path behind an AndroidX fallback; release signing; remove device branding.

## Open questions

1. What is the lock screen *for* — time + unlock + phone + camera in two seconds, or a physics playground?
2. Would a first-time owner, unaided, know that Essentials is a pinned shelf, Sectors are folders, and stars are apps?
3. Should this be a daily-driver launcher (widgets, badges, wallpaper) or a deliberate exotic shell that ships without them?
4. What single token would make "dimmest pixels = primary controls" unshippable — and would the app pass that audit today?