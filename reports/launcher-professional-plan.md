# ChronoFold: plan to make it look and feel native on ColorOS 16, and professional

Branch `fix/lockscreen-followups` @ `3043b18`. Baseline gate: `flutter analyze` clean, **133 tests pass**.
Device CPH2765 (ColorOS 16 / Android 16). Builds on `launcher-critique.md`, `coloros16-clash-analysis.md`
and `lockscreen-handoff-spec.md`. This file does not repeat them; it decides what to do about them.

## 1. Critique: where it is today

**Strong:** posture-aware surfaces, a real cover-screen token system, honest intent handoffs, lock
ownership single-sourced (PR #2), no fake battery, fingerprint no longer arms while the keyguard is up.

**Why it still does not feel native or professional:**

| # | Problem | Evidence |
|---|---|---|
| L1 | **The lock screen is blind to media.** With YouTube/Spotify playing, ColorOS shows a now-playing card with transport controls; ChronoFold shows bubbles. The moment the user most needs the lock screen (pause, skip) is the one it cannot serve. | no `MediaSession`/`NotificationListener` anywhere in `lib/` or `android/`; `dumpsys media_session` on the device lists YouTube + Spotify sessions |
| L2 | **"Own the lock screen in every state" is not true.** Screen-off inside an app the launcher opened is left to the ColorOS keyguard (`foreignTaskOwnsScreen`, `MainActivity.kt:179`). That was the right call *for the HOME activity*: raising home over the keyguard returned the user to the launcher instead of their app. The fix is structural, not a flag. | handoff spec §3 |
| L3 | **Two design languages.** The lock screen hard-codes its own palette (`cosmic_lock_screen.dart` build: `0xFF0D1426`, `0x3300E5FF` …); `LuminousHomeTheme` is used by 8 files. 256 raw `Color(0x…)` literals across 21 files. | grep |
| L4 | **The lock screen is a playground on a security surface** — ~20 targets (chips, SHAKE, flingable bubbles); a drift >12px turns a tap into a drag. | critique §Look |
| L5 | **Not the home process** → evicted at `PREVIOUS_APP_ADJ` 700, cold starts on return. Prime suspect `taskAffinity=""`. | clash §1 |
| L6 | Portrait lock ignored on the `sw692dp` inner display; `INTERNET` missing from main manifest; wallpaper suppressed; no dynamic colour. | clash §5, §6, §8 |
| L7 | Lock screen `setState` per frame, galaxy ticks behind the opaque lock, perpetual motion never idles. | critique §Performance |
| L8 | Notification badges are fixtures only. | critique §Features 2 |

## 2. Settled design decisions

1. **Lock surface = a dedicated `LockActivity`**, not the HOME activity. Its own task
   (`taskAffinity=".lock"`, `excludeFromRecents`, `showWhenLocked`, `turnScreenOn`), hosting the
   Flutter lock UI on a cached engine entrypoint. On screen-off it is started over *whatever* is on
   screen — home or YouTube. Unlock = `requestDismissKeyguard` → platform fingerprint → `finish()`, so
   the user lands back exactly where they were. That removes the reason `foreignTaskOwnsScreen` exists
   and lets the HOME activity stop toggling `showWhenLocked` entirely.
   *Probe first* (rule from the handoff spec): a home-role app starting an activity from the
   background on SCREEN_OFF may hit background-activity-launch limits. Fallback is a
   `fullScreenIntent` notification on a high-importance channel, which is how shipping third-party
   lock screens do it.
2. **Fingerprint:** the platform prompt is the only reader while locked (measured). The panel never
   pretends otherwise: one affordance, one `requestDismissKeyguard` per user intent, triggered by the
   swipe-up or a tap on the fingerprint glyph drawn exactly over the in-display sensor. Lock happens on
   screen-off only — not on plain backgrounding.
3. **Media first:** a `NotificationListenerService` (user-granted once) gives
   `MediaSessionManager.getActiveSessions`. The lock screen shows a now-playing card (art, title,
   artist, progress, prev/play-pause/next) whenever a session is PLAYING or recently PAUSED. When media
   is active, the bubble field dims and freezes. The same listener feeds real badges (L8).
4. **One design system:** `LuminousHomeTheme` becomes the only source of colour, radius, type and
   motion tokens. Lock, galaxy, cover, search and modals all consume it; raw literals are removed.
5. **Calm lock screen:** clock + date + media card + notifications count + two corner shortcuts
   (phone, camera) + unlock affordance. Bubbles stay as ambient decoration only: non-interactive,
   slow, idle after 10 s, gated by reduce-motion. SHAKE and category chips go.

## 3. Implementation phases (each = one dsh round, gate after each)

| Phase | Scope | Done when |
|---|---|---|
| **P1 Media + native hygiene** | `MediaListenerService` + `media` method/event channel (sessions, metadata, art PNG, position, transport actions) · permission check/request bridge · Dart `NowPlaying` model + `MediaController` · now-playing card on the lock screen in theme tokens · remove `taskAffinity=""` · add `INTERNET` · drop portrait lock (manifest + `setPreferredOrientations`) | card shows/controls YouTube on device; `mHomeProcess` non-null; tests for the model + card |
| **P2 LockActivity** | probe BAL; `LockActivity` + cached engine + `lockMain` entrypoint; start on SCREEN_OFF over any task; dismiss→finish; delete `foreignTaskOwnsScreen` path and HOME-activity `showWhenLocked` toggling; cold-boot path | lock over YouTube shows ChronoFold, unlock returns to YouTube; lock from home unchanged; logcat markers |
| **P3 Lock redesign** | calm layout (§2.5), sensor-aligned fingerprint glyph, remove SHAKE/chips, bubble idle + reduce-motion, per-frame `setState` → listenable painter | ≤ 6 interactive targets; no frame work when idle |
| **P4 One design system** | extend `LuminousHomeTheme` (type scale, motion, elevation, semantic roles, dynamic-colour seed from ColorOS); migrate every raw literal; wallpaper visible behind home | `grep -c "Color(0x" lib` only in theme file |
| **P5 Launcher polish** | real badges from listener · pause galaxy ticker while locked/hidden · icon cache + disposal · first-run (default launcher, notification access, OPPO battery checklist) · hide dev tooling behind a build flag · 48dp targets | perf trace idle = 0 fps; first-run shown once |

Out of reach without root (document, do not chase): ColorOS's own launcher flashing on HOME (~1 s),
recents/gesture animations owned by OPPO QuickStep.

## 4. Verification per phase

```bash
flutter analyze && flutter test && flutter build apk --debug --target-platform android-arm64
adb -s 3B164U00HXG00000 install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s 3B164U00HXG00000 shell "dumpsys window | grep -m1 mKeyguardOccluded; dumpsys trust | grep -m1 trustState"
adb -s 3B164U00HXG00000 logcat -d | grep -E "CF_LOCK|CF_FP|CF_MEDIA"
```
