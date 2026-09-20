---
target: the launcher and its lock screen auth
total_score: 16
max_score: 40
na_heuristics: 
p0_count: 2
p1_count: 2
target_identity: "file:/Users/benjerome/Documents/Dev/mylauncher/lib/features/lockscreen/cosmic_lock_screen.dart"
target_fingerprint: "sha256:6d8362ca64fc77d05d80a2e69b6458a2809c2c7f07760e04de2a9c6042886bae"
target_path: /Users/benjerome/Documents/Dev/mylauncher/lib/features/lockscreen/cosmic_lock_screen.dart
timestamp: 2026-09-20T16-10-14Z
slug: lib-features-lockscreen-cosmic-lock-screen-dart
---
Method: ⚠️ DEGRADED: single-context (sub-agent assessments A and B were cancelled by the user; both were run inline by the parent)

Scope: whole launcher (`lib/` + `android/`), reviewed as **Operate** mode. Grounded in a direct read of the tree at `06b71b5` plus two uncommitted files, `flutter analyze` (clean), `flutter test` (116 passing), and one temporary verification test written and deleted during the review.

Deterministic scan: `impeccable detect --json lib` returned `[]`. The detector scans markup/CSS, not Dart, so no automated design scan is available for this codebase. All findings below are code-grounded or empirically verified.

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 1 | Hardcoded `Text('92%')` battery + charging glyph on the lock screen; surface says "LOCKED" while enforcing nothing |
| 2 | Match System / Real World | 2 | Invented vocabulary (constellations, galaxies, turbulence, comet, pods) carries recall cost on a task surface |
| 3 | User Control and Freedom | 2 | `canPop: false` traps back with no exit branch; no undo for hide/constellation edits |
| 4 | Consistency and Standards | 1 | Three taxonomies for the same apps; two clock formats; no widgets/badges/shortcuts/Material You |
| 5 | Error Prevention | 1 | 12px drag threshold turns taps into launches; SHAKE adjacent to content; empty-category filter silently shows all apps |
| 6 | Recognition Rather Than Recall | 2 | Sector vs star vs Essentials must be memorized; gesture hint is the only teaching |
| 7 | Flexibility and Efficiency | 2 | Search + scrubber + constellations are real; no app shortcuts, no widgets, no preferences |
| 8 | Aesthetic and Minimalist Design | 2 | Canvases are distinctive; control chrome is generic and the dimmest thing on screen |
| 9 | Error Recovery | 2 | Turbulence messages are honest but are 10px transient toasts with no retry |
| 10 | Help and Documentation | 1 | No first-run flow, no in-app settings, no explanation of the vocabulary |
| **Total** | | **16/40** | **Needs significant work** |

## Design Specificity Verdict

The canvases are unmistakably this product. Physics bubbles, orbit filaments, posture-aware surfaces, the hinge-driven cockpit — none of it could be lifted into another app. The control chrome is the opposite: capsule pills, low-alpha glass, cyan accent, 10px uppercase tracking. That grammar is generic premium-dark.

The budgets are inverted. The specific material owns the decoration; the generic grammar owns every control the user actually needs to hit.

## Priority Issues

### [P0] The lock screen enforces nothing, and says it does

Verified empirically. With the keyguard reported as locked, a swipe-up clears the overlay:

```
unlockCalled=true  authCalled=false  credentialCalled=false  keyguardQueried=false
```

`_onPointerUp` → `_panelOffset > 140` → `_unlock()` → `widget.onUnlock()` → `_isLocked = false`. The swipe path never calls `authenticate`, never calls the credential fallback, and never asks whether the device is locked. The comment reads "Anyone can swipe up to enter the launcher."

Because `MainActivity` sets `showWhenLocked`, the launcher draws over the ColorOS keyguard. So on a locked phone, a swipe reveals the full app inventory, the search overlay over every installed app name, the constellation editors (which persist), and the NATIVE toggle that disables the lock overlay entirely.

App launches are still gated — they go through native `requestDismissKeyguard`. The exposure is information disclosure and config tampering, not arbitrary app access. That distinction matters, and it does not rescue the design: the surface displays a padlock and the word LOCKED while being a decorative curtain.

Fix: pick one. Either gate `_unlock()` on `isKeyguardLocked()` and route the swipe through real authentication, or drop every security signifier and call it a cover dashboard.

### [P0] Authentication success is asserted, not established

In production `authenticateWithCredential` is null (main.dart constructs `CosmicLockScreen` without it), so `_useCredentialFallback()` reaches `_resolveAuth(true)` — reporting authenticated with nothing verified. It survives only because native `requestDismissKeyguard` prompts for real. The Dart contract returns a `bool` that does not mean what it says, and `startWhenUnlocked`'s `onDismissError` branch starts the activity anyway.

Fix: make the Dart layer return a tri-state or make the native dismissal the only thing that can resolve a launch. Never synthesize `true`.

### [P1] Lock state cannot survive the process

`_isLocked` is an in-memory bool initialized to `false`, with `android:stateNotNeeded="true"`. Per the repo's own device measurements the launcher sits at `PREVIOUS_APP_ADJ` with ~415MB RSS — among the most attractive eviction candidates. Any recreation while the device is locked renders the launcher home with no overlay.

Fix: derive the overlay from `KeyguardManager` at every resume rather than remembering a flag.

### [P1] A security surface carrying ~20 interactive targets

Six category chips, a SHAKE pill that scatters the field, ~11 flingable bubbles, a fake battery, hint text, two shortcuts. The 12px threshold means a slightly drifting tap launches whatever was under the thumb. Nothing here serves time, unlock, phone, camera in two seconds.

### [P2] A launcher that is not using the launcher APIs

`QUERY_ALL_PACKAGES` + `queryIntentActivities` + broadcast receivers, where `LauncherApps` is the API built for this: managed-profile support, `getShortcuts`, and `registerCallback` instead of manual receivers. No `AppWidgetHost`, no wallpaper, no Material You, no badges (`notificationCount` is only ever set in `_generateMockApps()`).

## Persona Red Flags

**The owner who just picked up a locked phone**: sees LOCKED and a padlock; one swipe reads their entire app list and can rename their layout.

**Jordan (first-timer)**: no first-run flow. Nothing explains that stars are apps, sectors are folders, Essentials is a shelf. The settings button leaves the app for system HOME settings. COSMIC/NATIVE means nothing to them.

**Alex (power user)**: no widgets, no long-press app shortcuts, no badges, no backup. Back is trapped with no exit. Loses the layout on reinstall.

## Minor Observations

- Empty-category filter falls back to all apps, so an active filter lies.
- `_iconCache` keys on package name only; an app update keeps the stale icon.
- Mock apps ship in release and are shown whenever a real scan returns empty; `launchApp` then simulates success.
- `INTERNET` is missing from the main manifest — a release build has no network for the search provider.
- Release is signed with the debug key; debug symbols retained.
- `taskAffinity=""` is the prime suspect for the launcher not registering as the home process.
- `screenOrientation="portrait"` is ignored on the `sw692dp` inner display under Android 16.

## Credit where the tree earned it

Several items from the previous critique are genuinely fixed: the lock screen no longer `setState`s per frame (`ValueNotifier` + `RepaintBoundary` + listenable painter), hidden canvases are muted with `TickerMode`, the icon pipeline downscales natively at 96px with a package cache and a bounded decode window, the painted bubbles now carry screen-reader nodes, self-lock on backgrounding is gone, and default-launcher wiring is live.

The native layer is the best-documented code in the repo. The comments record measured device behavior with error codes and build numbers, and the `ACTION_WEB_SEARCH` chooser handling is honest about what the platform will not do.

## Questions to Consider

1. What is the lock screen for — time, unlock, phone, camera in two seconds, or a physics playground?
2. Is this a daily driver or a deliberate exotic shell? The widget/badge/wallpaper answer follows from that and nothing else.
3. What would make "the dimmest pixels are the primary controls" unshippable?
