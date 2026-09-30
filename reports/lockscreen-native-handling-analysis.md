# Lock-screen ownership & fingerprint UX — root-cause analysis and solution plan

- **Scope:** analysis only. No file under `lib/`, `android/`, or `test/` was modified; every claim below was reached by static reading of this tree (`fix_lock_screen` branch).
- **Device reality is taken from the existing reports, not re-measured:** `reports/repro-fingerprint-unlock.md` (Red 1/Red 2) and `reports/lockscreen-fingerprint-prompt.md`. Items marked **[measured]** come from those device sessions; items marked **[inference]** are code traces; items marked **[probe]** are claims only the device can settle, with the exact adb/logcat command given.
- The reports describe two different eras of this code. `repro-fingerprint-unlock.md` ends with `showWhenLocked` *removed*; the current tree re-introduces occlusion at runtime in Cosmic mode (`main.dart:245`, `main.dart:303`, `MainActivity.kt:953-969`). Where a measured fact depends on the occluded window state (`mKeyguardOccluded=true`), it applies to the current branch because the window state is identical — one probe re-confirms it (§6.1).

## 1. The constraint set (what this device has already proven)

1. **[measured]** While the keyguard is occluded (`mKeyguardOccluded=true`), *no one* reads the side sensor: app-owned sessions are cancelled in 1–6 ms and "no unlock ever follows a touch" — the platform's lock-screen biometric path is disabled too (`reports/repro-fingerprint-unlock.md:46-62`). The only reader that works in that state is the platform's own bouncer dialog raised through `requestDismissKeyguard`/`BiometricService` (`reports/lockscreen-fingerprint-prompt.md:52-66`).
2. **[measured]** While the device is locked, every arm of an app-owned `FingerprintManager` session is refused — cold start, no competing session, key-bound or bare (same report, lines 15-51). Once the keyguard is dismissed, the panel's reader *is* allowed (lines 53-54).
3. **[measured]** Arming while the panel is off burns the retry budget and left the sensor dead for the session (Red 1, lines 14-44); the native side now refuses to arm when `!PowerManager.isInteractive` (`MainActivity.kt:996-1002`).
4. **[measured, comment-recorded]** The Flutter lifecycle "stays resumed through doze on this build" while the launcher is the occluding top activity (`cosmic_lock_screen.dart:157-163`) — this is what makes the native `launcherResumed` flag a meaningful signal.
5. **[platform fact, no API in tree]** A launcher activity cannot draw over another task's window. `setShowWhenLocked` promotes only the launcher's own window; behind a foreign task the launcher task is simply not visible. Nothing in the tree, and no public Android API short of reordering tasks in front of the user's app, changes that.

---

## 2. Defect 1 — "when I have app running on the lock screen, the launcher is not handling"

### 2.1 Reproduction paths (device step sequences)

**Path A — power pressed inside an app the launcher launched (no lock surface at all).**
1. On the cover screen, launch an app → `markForeignTaskHandoff()` sets `foreignTaskForeground=true` (`MainActivity.kt:118-121`, called from `startActivityQuietly:829`); `onPause` sets `pausedForForeignTask=true` (`MainActivity.kt:221-223`).
2. Inside the app, press power. SCREEN_OFF fires with `foreignTaskOwnsScreen == true` → the event is **dropped** with the log `Screen off while a launched app owns the screen; leaving the lock to the platform keyguard` (`MainActivity.kt:155-162`). Dart never receives `lockScreen`; `_isLocked` stays false; the overlay flag was already cleared by the launch itself (`MainActivity.kt:741` for a launch from home, `758` for one from the locked panel; `cosmic_lock_screen.dart:1072` pushes the same from Dart).
3. Wake → ColorOS keyguard; unlock → back inside the app; `USER_PRESENT` is also dropped (`MainActivity.kt:181`).
4. Close the app → the cover screen appears with no lock interaction at all.

The launcher was invisible for the whole cycle and mounted nothing — the user sees "ColorOS handled it, ChronoFold didn't".

**Path B — power pressed inside an app the launcher did NOT launch (spurious lock panel after unlock).**
1. Open an app from a notification/recents/share (anything that does not go through `startActivityQuietly`). `markForeignTaskHandoff` is never called, so `foreignTaskOwnsScreen == false` even though the launcher is paused behind the app (`MainActivity.kt:104-109`).
2. Inside the app, press power → SCREEN_OFF is **not** dropped this time → Dart `_lockForScreenOff()` runs behind the foreign app: `setLockScreenOverlayEnabled(true)` + `_isLocked = true` (`main.dart:239-247`). No frame is built (the launcher is invisible), so the panel element is *not* inflated yet.
3. Wake, unlock with the sensor → `USER_PRESENT` reaches Dart (`keyguardWasLocked` was recorded before the foreign check, `MainActivity.kt:143-144`; `foreignTaskOwnsScreen` is false so it is not dropped, `MainActivity.kt:179-185`) — **but the listener is null**: `_onUserPresent` is registered in the panel's `initState` (`cosmic_lock_screen.dart:534-535`), which has not run. The unlock signal is lost.
4. Close the app → the first frame inflates the cosmic lock panel on an **already-unlocked** device. The user must swipe to get rid of it (`_enterLauncher` finds `isKeyguardLocked() == false` and unlocks, `cosmic_lock_screen.dart:1010-1016`).

This is the exact "lock panel leaking behind a foreign app / asking after the fact" the user describes.

**Path C — lock from the HUD/dock lock button, then a power cycle (inconsistent wake surface).**
1. From the cover screen, tap the lock button: `onLock: () => setState(() => _isLocked = true)` (`main.dart:474-475`; also `495-496`, `544-545`, `570-571`) — the panel mounts but **`setLockScreenOverlayEnabled(true)` is not pushed**.
2. Whether this shows the cosmic panel on wake depends on history: the overlay was disabled by any earlier launch handoff (`cosmic_lock_screen.dart:1072,1090`; `MainActivity.kt:741,758`).
3. Press power → `_lockForScreenOff` hits `if (_isLocked) return;` (`main.dart:241`) — the early-return happens **before** `setLockScreenOverlayEnabled(true)` (`main.dart:245`), so the overlay is never re-asserted.
4. Wake → **ColorOS keyguard** instead of the cosmic panel; unlock → panel slide-away. The same physical action (lock + power) yields a different lock surface depending on whether an app was launched earlier in the session.

**Path D — process (re)start while the device is locked. [probe]**
`_loadApplications` pushes `setLockScreenOverlayEnabled(!_nativeMode)` unconditionally (`main.dart:299-303`), and `_isLocked` starts `false` (`main.dart:76`) with no `isKeyguardLocked()` check at startup. On a cold start behind a locked keyguard (reboot is the clean case), the tree asserts `showWhenLocked` and then draws the **home surface**, not the lock panel, over the keyguard — the exact scenario `MainActivity.kt:126-135` says must never happen ("a surface that authenticates nobody was the first thing on a locked screen"). Probe in §6.4.

### 2.2 Responsible code

| Behaviour | Code |
|---|---|
| SCREEN_OFF dropped only for launcher-initiated handoffs | `MainActivity.kt:104-109, 118-121, 155-162` |
| `lockScreen` re-asserts overlay only when `_isLocked` is false | `main.dart:239-247` |
| Manual lock buttons mount the panel without the overlay | `main.dart:474-475, 495-496, 544-545, 570-571` |
| Handoff disables the overlay (per-launch) | `cosmic_lock_screen.dart:1068-1074`; `MainActivity.kt:741, 753-759` |
| `userPresent` listener exists only while the panel is inflated | `cosmic_lock_screen.dart:534-535`; `launcher_bridge.dart:62-65` |
| Unconditional overlay push at startup, no locked-state check | `main.dart:296-303` |

### 2.3 Root cause (one sentence each)

The launcher's lock surface is an ordinary activity window gated by three *separate* state machines — the Dart `_isLocked` flag, the window's `showWhenLocked` flag, and the native `foreignTask*` latch — and nothing keeps them equivalent, so "which lock surface will I see" depends on *how the launcher got backgrounded* (launcher-launched vs notification-launched) and *what happened earlier in the session* (any launch handoff disables the overlay and the early-return in `_lockForScreenOff` never re-enables it).

Deeper: for Path A the gap is a **platform fact, not a bug** — behind a foreign task the launcher cannot draw anything (§1.5), and occluding would kill the sensor anyway (§1.1); the ColorOS keyguard is the only lock surface that case can have. The launcher's job there is to delegate consistently, which Path B/C/D show it currently does not.

### 2.4 Why the existing mitigations did not close it

- **Foreign-task gating** (`MainActivity.kt:155-162, 173, 181`) closed the reported bug it was built for — a lock panel re-asserting `showWhenLocked` behind a launcher-launched app and prompting on return (comments at `main.dart:230-238`, `MainActivity.kt:92-98`). It did not close Path B because the latch is set *only* by `markForeignTaskHandoff()`, i.e. only for intents this launcher starts (`MainActivity.kt:118-121`; callers at `549, 829, 1194, 1218`). Any notification-, recents-, or assistant-originated task bypasses it.
- **Reader arming policy** (`MainActivity.kt:996-1019`, `cosmic_lock_screen.dart:597-647`) is irrelevant to Path A–D: it governs the sensor, not the window flag or the panel mount. The relevant asymmetry is that the *arm* path refuses when `!launcherResumed` (`MainActivity.kt:1004-1019`) while the *lock* path does not.
- **`_handedOff` latch** (`cosmic_lock_screen.dart:211-226, 775-776`) closed the "fingerprint request out of the blue on return from a launched app" bug (its own comment, lines 211-223) and is not implicated here — Path B's panel is *newly* inflated after the signal was lost, not revived.
- **`_sensorUnusable`** (`cosmic_lock_screen.dart:337-345`) closed the arm storm (§3.2) and is not a window/panel-state mitigation at all.

### 2.5 Ranked solutions

**D1-1 (P0) — Gate SCREEN_OFF on "is the launcher the foreground surface", not on "did we launch the app".**
Change `MainActivity.kt:142-166`: drop the event when `foreignTaskOwnsScreen || !launcherResumed` (keep the existing log for the first branch; add a second marker, §6.2). Justification: on this build the occluding launcher *stays resumed through doze* (§1.4), so `launcherResumed` distinguishes "screen off on my own surface" from "screen off behind anything" — including the notification-origin tasks the latch never marks. Consequence: Path B's panel never mounts; the platform keyguard owns every lock that happens inside a foreign app, symmetrically with Path A.
- Constraint respected: no new window state; it *removes* a wrong window-state assertion.
- Risk accepted: **[probe]** if ColorOS delivers `onPause` before the SCREEN_OFF broadcast even for the top activity, lock-from-home would break. The recorded measurement (§1.4) says the *occluding* launcher stays resumed, but the launcher can also be top-and-not-occluding (right after a launch round-trip, overlay still false), and there `onPause` plausibly arrives with the keyguard engaging — the same race `main.dart:236-238` warns about. §6.3 tests both window states and is the 30-second falsification test. Belt-and-braces if either probe fails: keep the native drop for `foreignTaskOwnsScreen` only, and reconcile at panel inflation instead — in `initState`, if `isKeyguardLocked()` is false and the panel was not mounted by an explicit user action, auto-clear (the same check `_enterLauncher` already performs at `cosmic_lock_screen.dart:1010-1016`); that variant is race-free because it runs when frames are definitely pumping.
- Tests: no Dart test pins the notification-origin path (it is native); all 13 suites unaffected.

**D1-2 (P0) — Single-source the overlay flag with the panel state.**
(a) In `_lockForScreenOff` (`main.dart:239-247`), move `setLockScreenOverlayEnabled(true)` above the `if (_isLocked) return;` early-out (or delete the early-out). (b) Route the four manual lock callbacks (`main.dart:474, 495, 544, 570`) through one `_mountLockPanel()` helper that pushes the overlay before `setState(_isLocked = true)`. Invariant: in Cosmic mode, *panel mounted ⟺ overlay enabled*, so every wake shows the same surface. Consequence: Path C becomes deterministic (cosmic panel after any lock, regardless of launch history).
- Constraint respected: occlusion is already the Cosmic default (`main.dart:296-303`); no new platform interaction.
- Verification: §6.2 markers `CF_LOCK: overlay re-asserted for screen-off lock` / `CF_LOCK: panel mounted by user action`.

**D1-3 (P0, security) — Never start cold over a locked keyguard.**
In `_loadApplications` (`main.dart:296-303`): query `LauncherBridge.isKeyguardLocked()` (`launcher_bridge.dart:341-353`) before pushing the overlay; if locked, set `_isLocked = true` (mount the lock panel) *instead of* exposing home over the keyguard. Alternative if the product prefers maximum safety: leave the overlay off until the first real screen-off and let ColorOS own the first post-boot wake. Consequence: closes Path D's disclosure (search/editors/app inventory over a locked device — the same class of hole the swipe-up fix closed at `cosmic_lock_screen.dart:991-1006`).
- Constraint respected: restores the invariant documented at `MainActivity.kt:126-135`.
- Verification: §6.4 (`adb reboot` probe).

**D1-4 (decision, no code) — Lock-inside-a-foreign-app stays with the platform keyguard.**
The user asks for the cosmic surface in *every* case; for Path A the device forbids it twice: the launcher window is invisible behind the foreign task (§1.5), and forcing the launcher task to the front would (i) displace the user's app so that unlock lands on home instead of their app, and (ii) occlude the keyguard and kill the sensor (§1.1) — a strictly worse unlock than today's. "Handling" this case means delegating consistently: D1-1 makes the delegation invisible (no spurious panel), D1-2/D1-3 make the launcher's own lock surfaces consistent everywhere else. If the user wants the OEM-look wake at all times instead, the existing Native toggle (`main.dart:174-190`, `README.md:64-67`) already provides it; the fixes above make both modes honest.

**D1-5 (P2) — Optional consistency polish.** On `USER_PRESENT` while `foreignTaskOwnsScreen` (`MainActivity.kt:181`), keep dropping it, but if D1-1 is ever rejected, emit it so Dart can reconcile `_isLocked` for a panel mounted invisibly (today that signal is lost because the listener registers only at inflation, `cosmic_lock_screen.dart:534-535`). Only needed as a fallback to D1-1.

---

## 3. Defect 2 — "the request for the fingerprint can be excessive and showing the wrong time"

### 3.1 The dead fingerprint card (the main "excessive, wrong moment" complaint)

**Repro (locked device, Cosmic mode, cover display):**
1. Power off on the cover screen → wake → cosmic panel over the keyguard (`main.dart:245`, `MainActivity.kt:953-969`).
2. During the wake the panel armed its reader and was refused twice (§3.3), so `_sensorUnusable == true` (`cosmic_lock_screen.dart:729`).
3. Tap any bubble → `_unlockAndLaunchApp` → keyguard is locked → `_authenticate` → capability ready → `_authenticateWithSensor` (`cosmic_lock_screen.dart:1105-1151, 234-312`) — which **raises the card unconditionally** (`_authTarget = target`, lines 289-294) and then, because `_sensorUnusable` is true, runs the `_sensorUnusable` branch: in production that branch does *nothing* (lines 299-307: `_useCredentialFallback()` is called only `if (widget.authenticateWithCredential != null)` — and that hook has **no production default**, lines 68-78).
4. The card is now modal (`ModalBarrier(dismissible: false)` at 1628-1634; pointer handlers refuse while `_authTarget != null`, 908-910/957) and the `_authCompleter` **never resolves**: on a device where the sensor is dead while occluded (§1.1), no sensor match, no `USER_PRESENT`, no fallback will ever arrive. The only exits are the CANCEL button ("AUTH REQUIRED TO LAUNCH X", 1137-1141) or USE PIN → `_useCredentialFallback` → production branch completes `AuthOutcome.deferToPlatform` (357-366) → `_unlock()` → `launchApp` → `requestDismissKeyguard` → the one platform bouncer → app opens.
5. Net experience: **tap → card that asks for a finger that can never answer → tap USE PIN → bouncer → app** — a fake fingerprint ask inserted into every lock-screen launch, on the device where it can never succeed. The second tap in the same lock session repeats the card even though the code now knows no arm will even be attempted (lines 299-307 raise the card before the `_sensorUnusable` check short-circuits arming at 604).

**Root cause.** The card was promoted from "shown when the platform actually hands the reader over (`listening`)" to "shown immediately on every tap" (comment at `cosmic_lock_screen.dart:279-288`; the raise at 289-294; the now-dead `listening` promotion at 660-670 proves the original design — also documented in `reports/lockscreen-fingerprint-prompt.md:69-78` as "refused? no card; platform prompt reads → app opens"), but the refusal path's resolution was left gated on `widget.authenticateWithCredential != null` (`cosmic_lock_screen.dart:305-307, 730-734, 757-761`), a hook that only tests inject. In production the refusal strands the completer behind a modal card.

**Why the mitigations did not close it.** `_sensorUnusable` correctly stops the re-arm storm (604) and correctly offers USE PIN (1643-1647), but the design assumes *someone else* resolves the request when the reader is refused — in tests that is the injected credential hook; in production there is no one. The `_handedOff` latch and foreign-task gating are not involved in this path. The test suite pins only the injected-hook behaviour: `test/lockscreen_auth_prompt_test.dart:319-364` ("a refused reader keeps the card up while the platform asks") and 366-413 both inject `authenticateWithCredential` (lines 332-338, 373-383), so the production dead-end is untested.

### 3.2 The futile arm cycle at every wake

[measured + inference] While the panel is up over a locked keyguard, every wake runs: `_onScreenOn` resets `_sensorUnusable = false` and arms (`cosmic_lock_screen.dart:582-589`), the native side arms and emits `listening` optimistically (`MainActivity.kt:1021-1072`), ColorOS cancels in 1–6 ms (§1.2), Dart retries once (`cosmic_lock_screen.dart:719-723`), cancelled again, `_sensorUnusable = true` (729). The panel's `initState` arm (536) and the resume arm (788) can each add another cycle on the first wake — **2–6 futile sensor arms per wake**, exactly the "excessive request" pattern Red 1 documented, now merely bounded. Logcat proof: pairs of `Fingerprint reader armed` (`cosmic_lock_screen.dart:659`) and `Fingerprint sensor stopped: 5 Fingerprint operation canceled` (706) per wake (§6.5).

### 3.3 The clock — verdict per surface

- **Value correctness: sound on all four surfaces. [inference, evidence]** Every clock captures `DateTime.now()` at State creation (`cosmic_lock_screen.dart:121`, `folded_cover_screen.dart:79`, `tabletop_cockpit_view.dart:51`, `main.dart:656`) and re-reads it on a 1 s `Timer.periodic` gated on the visible minute (`cosmic_lock_screen.dart:493-503`, `folded_cover_screen.dart:89-97`, `tabletop_cockpit_view.dart:67-76`, `main.dart:661-668`). The lock panel mounts at the *first frame after screen-on* (no vsync → no build while the panel is off), so its `initState` timestamp is fresh at first paint, not the screen-off time. After a suspend/freeze, the overdue tick fires on the event loop before the first vsync, so the first visible frame is corrected. **No fix is proposed for the value.** The one residual is a race that could show one stale frame after a process unfreeze: [probe] §6.6.
- **Format: hardcoded 24-hour zero-padded on every surface. [inference, defect]** `hour.toString().padLeft(2, '0')` with no consultation of `MediaQuery.alwaysUse24HourFormat` / the platform time format — `cosmic_lock_screen.dart:1228-1229`, `folded_cover_screen.dart:331`, `tabletop_cockpit_view.dart:173`, `main.dart:678-681`. If the device's system clock is 12-hour, every ChronoFold clock disagrees with the ColorOS status bar and keyguard the user compares it against — the most plausible reading of "showing the wrong time" (the same observation as `reports/launcher-critique.md:31`, "two clocks in different formats"). [probe] §6.7 settles which format the device uses.
- **Waste nit:** the HUD clock alone lacks the minute gate — it rebuilds its whole subtree every second and keeps doing so while paused (`main.dart:661-668`); the other three screens gate on the minute.

### 3.4 Ranked solutions

**D2-1 (P0, test-neutral) — Resolve the stranded request instead of stranding it.**
In `_onFingerprintEvent` 'error' (and the `_authenticateWithSensor`/`unavailable` branches), call `_useCredentialFallback()` regardless of `widget.authenticateWithCredential` (`cosmic_lock_screen.dart:730-734`, `305-307`, `757-761`). In production its existing body already completes `AuthOutcome.deferToPlatform` (357-366), which drives the launch through the platform's single `requestDismissKeyguard` bouncer (`MainActivity.kt:798-825`). Consequence: tap → (≤ one frame of card) → the one platform prompt → app. No dead card, no USE PIN ceremony, no second ask — the exact "one prompt per intention" contract the comments at 250-258 and 358-365 state. The injected-hook tests keep their behaviour (the hook is asked first, `cosmic_lock_screen.dart:352-355`), so no test changes.

**D2-2 (P1) — Restore the `listening`-gated card.**
Remove the unconditional raise at `cosmic_lock_screen.dart:289-294`; let `_authWanted` (180-188) and the `listening` promotion (654-670) put the card on screen only when the platform actually handed the reader over. On a refused reader the card then never appears; the request resolves via D2-1. Consequence: no fake ask at all; the card survives only where a finger can really answer it (keyguard already dismissed — the privacy-lock panel — or non-ColorOS devices that allow app readers while locked). Constraint respected: this is the *original* design of `reports/lockscreen-fingerprint-prompt.md:69-78, 180-188`; the deviation is newer than the report. Risk accepted: **one pinned test expectation changes** — `test/lockscreen_auth_prompt_test.dart:343` ("The card answers the tap immediately, before the reader is consulted") and the comment at 327-331; update the two tests at 319-364/366-413 with the production/test split documented. If touching that suite is off-limits this round, ship D2-1 alone (the card then flashes ≤1 frame instead of hanging).

**D2-3 (P1) — Stop asking a locked keyguard for the sensor.**
Native: in `startFingerprintScan` (`MainActivity.kt:989-1083`), refuse with a new event type (e.g. `keyguardLocked`) when `KeyguardManager.isKeyguardLocked`, next to the existing `screenOff`/`background` refusals (996-1019). Dart: treat it like a refusal → `deferToPlatform` via D2-1. Justification: the only reader sessions this device ever grants are on the keyguard-dismissed path (§1.2, `reports/lockscreen-fingerprint-prompt.md:53-54` — the dock privacy lock, exactly the "residual uncertainty" case `reports/repro-fingerprint-unlock.md:110-113` names), and every locked-state arm is measurably cancelled in 1–6 ms. Consequence: zero futile arms per wake; logcat clean (§6.5 becomes a regression test). Risk accepted: on a hypothetical device that *does* grant app readers while locked, the card would no longer engage — if that matters, fall back to the softer variant: keep one arm per lock session and let the first cancellation set a Dart-side flag (D2-1 then completes the request); the storm is already bounded by `_retriedArm` (719-723).

**D2-4 (P2) — Clocks follow the platform format.**
Use `MediaQuery.alwaysUse24HourFormat` (and the platform day-period convention) in all four clocks: `cosmic_lock_screen.dart:1228-1229`, `folded_cover_screen.dart:331`, `tabletop_cockpit_view.dart:173`, `main.dart:678-681`. Consequence: the launcher's clocks agree with the ColorOS clock on the same screen. Add the minute gate to the HUD timer (`main.dart:661-668`) while touching it (perf, matches the other three). Values stay as-is (§3.3 evidence); keep the residual-race probe in the verification notes.

**D2-5 (P3) — Copy honesty.** `USE PIN` neither opens a PIN pad nor enters a PIN: it defers to the platform bouncer (`cosmic_lock_screen.dart:357-366`, button at `fingerprint_prompt.dart:408-417`). Relabel to what it does ("UNLOCK" / "USE PIN OR PATTERN") once D2-1 makes it rarely reachable.

---

## 4. Cases matrix

| Case | Behaviour today | Behaviour that would "feel native" | Closing change |
|---|---|---|---|
| **Lock from home** (power on cover screen) | SCREEN_OFF → panel + occlusion re-asserted (`main.dart:239-247`); wake shows cosmic panel; side-sensor touch does nothing while occluded **[measured §1.1]**; unlock = swipe → platform bouncer (`cosmic_lock_screen.dart:1007-1032`) | Same panel at wake (user's chosen mode), with exactly one honest unlock ask and no fake fingerprint card | D2-1/D2-2/D2-3 (the ask); the sensor-while-occluded limit is a documented trade-off (`reports/lockscreen-fingerprint-prompt.md:158-163`), the Native toggle is the sensor-first alternative |
| **Lock from foreign app, launcher-launched** | Event dropped (`MainActivity.kt:155-162`); ColorOS keyguard owns lock; unlock returns into the app; no launcher surface anywhere | Nothing better is possible: the launcher window is invisible behind the foreign task (§1.5) and forcing it forward kills the sensor and displaces the app. Native = platform keyguard, launcher visible the instant the app closes | D1-4 (accept + keep consistent); D1-2/D1-3 make the launcher's other surfaces deterministic |
| **Lock from foreign app, other origin** (notification/recents) | Panel mounted invisibly behind the app (`main.dart:239-247`); unlock signal lost (listener registers at inflation, `cosmic_lock_screen.dart:534-535`); **spurious lock panel appears after unlock** when the app closes | Same as launcher-launched: platform keyguard, no ghost panel | **D1-1** (gate on `!launcherResumed`); fallback D1-5 |
| **Wake from lock** (cosmic panel up, locked) | Panel over keyguard; reader armed+refused 2–6× (§3.2); swipe → bouncer → panel slides away (`cosmic_lock_screen.dart:544-580, 1081-1092`) | One gesture to home. In Cosmic mode the device forbids sensor-at-wake (occlusion); native-feel = one honest ask, no dead affordance | D2-1/D2-2/D2-3; optionally make the panel's hint text state the real gesture ("swipe to unlock") |
| **Launch app from lock — reader-refused path** (locked device: the only reader state while locked here) | Tap → dead modal card → USE PIN → bouncer → app (3 steps, 1 fake ask; §3.1) | Tap → the platform's one bouncer → app | **D2-1** (P0), then D2-2 (no card at all), D2-3 (no futile arms) |
| **Launch app from lock — reader-allowed path** (keyguard already dismissed: dock/HUD privacy lock) | Tap → `isKeyguardLocked()==false` short-circuits → straight launch, no card (`cosmic_lock_screen.dart:1123-1129`); the armed reader answers a bare touch to clear the panel (672-693) | Same — instant launch on an unlocked device, bare-touch unlock on the privacy panel | None: this path is already native; it is the only production state where the silent reader can work (`reports/lockscreen-fingerprint-prompt.md:53-54`) |
| **Return from launched app** | Launcher resumes; frame finally unmounts the handed-off panel; `_handedOff` blocks re-arm and re-launch (`cosmic_lock_screen.dart:211-226, 775-776`); cover screen appears; no prompt | Same | Closed by the `_handedOff` latch — no change needed (cited as evidence the latch works) |
| **Screen-on while app in front** | SCREEN_ON dropped (`MainActivity.kt:173`); nothing arms, nothing draws | Same — a backgrounded launcher must do nothing | None; the native guard already enforces it even if Dart asked (`MainActivity.kt:1004-1019`) |
| **Home screen only** (no lock) | No panel; reader never armed (arming lives only in the panel, `cosmic_lock_screen.dart:536`); HUD/cover clocks tick | Same | None — except the lock *buttons* on home mount the panel without the overlay (Path C) → **D1-2** |

---

## 5. Other genuine defects found (not named by the user)

1. **Cold start behind a locked keyguard exposes home** (Path D, §2.1): `main.dart:299-303` pushes `setLockScreenOverlayEnabled(true)` with no locked-state check and no panel mount — the disclosure class of hole the swipe-up fix closed (`cosmic_lock_screen.dart:991-1006`). Fix: D1-3. [probe §6.4]
2. **`initialAuthenticated` is dead in production** — declared (`cosmic_lock_screen.dart:49, 96`), read nowhere in `lib/` (only `test/lockscreen_physics_test.dart:215` sets it). Remove or wire it.
3. **Fake battery on the lock surface** — hardcoded `Text('92%')` with a charging glyph (`cosmic_lock_screen.dart:1447-1455`); already flagged in `reports/launcher-critique.md:32`.
4. **`listening` is emitted optimistically** before the platform has accepted the session (`MainActivity.kt:1072`), so Dart's `_sensorArmed` flickers true for 1–6 ms; D2-3 makes arming honest, D2-2 makes the card independent of the flicker.
5. **The `isDeviceSecure` gate from the verified Green state is gone**: `reports/repro-fingerprint-unlock.md:88-90` says `_lockForScreenOff` consulted `isDeviceSecure()`; no such bridge method exists today (`grep isDeviceSecure lib/` — only `MainActivity.kt:1096` uses it, inside `authenticateUser`). On a device with no secure lock, screen-off now mounts the cosmic panel + occlusion regardless. Re-add the capability or confirm the product choice.
6. **Ungated 1 s HUD clock timer** (`main.dart:661-668`) — full subtree rebuild every second, also while paused; the other three clocks gate on the minute (fold into D2-4).

---

## 6. Verification probes

### 6.1 Occlusion still kills the sensor on this build (re-baseline §1.1)
```bash
adb shell input keyevent KEYCODE_SLEEP; sleep 2; adb shell input keyevent KEYCODE_WAKEUP
adb shell dumpsys window | grep mKeyguardOccluded     # expect true in Cosmic mode
# touch the side sensor on the cosmic panel → expect NO unlock (repro Red 2)
adb logcat -d | grep -E "flutter : (Fingerprint reader armed|Fingerprint sensor stopped)"
```

### 6.2 New markers to add (exact strings)
- `_lockForScreenOff`, after the re-assert (D1-2): `CF_LOCK: overlay re-asserted for screen-off lock`
- `_lockForScreenOff`, on the already-locked early-out: `CF_LOCK: screen-off with panel already up`
- Manual lock buttons (D1-2): `CF_LOCK: panel mounted by user action`
- Native SCREEN_OFF, new branch (D1-1, alongside the existing tag at `MainActivity.kt:156`): `ChronoFold: Screen off while the launcher is not the foreground surface; leaving the lock to the platform keyguard`
- Refusal fast path (D2-1/D2-3): `CF_FP: reader refused while keyguard locked; deferring to platform prompt`
- Startup reconciliation (D1-3): `CF_LOCK: cold start with keyguard locked; mounting lock surface`

### 6.3 D1-1 premise test (do this first — instrument, then three states)
When implementing D1-1, add to the SCREEN_OFF receiver (next to the existing tag at `MainActivity.kt:156`) a temporary line:
`android.util.Log.d("ChronoFold", "SCREEN_OFF launcherResumed=" + launcherResumed + " foreign=" + foreignTaskOwnsScreen);`
Then:
```bash
# State 1 — top + occluding (Cosmic default, overlay asserted at startup, main.dart:303):
adb shell input keyevent KEYCODE_SLEEP && sleep 1 && adb shell input keyevent KEYCODE_WAKEUP
# State 2 — top + NOT occluding (launch an app from home, close it — the handoff cleared the overlay,
# MainActivity.kt:741 — then press power on the cover screen)
# State 3 — behind a foreign task (open an app from a notification, press power inside it)
adb logcat -d -s ChronoFold | grep SCREEN_OFF
```
D1-1 holds if State 1 and State 2 both print `launcherResumed=true` and State 3 prints `false` (plus `foreign=false` — that is the bug). Any of 1/2 printing `false` means `onPause` beats the broadcast in that window state → use the race-free fallback (reconcile at panel inflation) for that state instead of the native gate. State 2 also proves out Path C's inconsistency on today's build: the wake shows the ColorOS keyguard, not the panel.

### 6.4 Path D probe (cold start behind a locked keyguard)
```bash
adb reboot && sleep 40   # do not unlock
adb shell dumpsys window | grep -E "mKeyguardOccluded|mCurrentFocus"
adb shell dumpsys activity activities | grep -E "topResumedActivity|mResumedActivity"
```
Today, once Dart loads: expect `mKeyguardOccluded=true` and the ChronoFold task resumed with the *home* surface visible without any unlock. After D1-3: the lock panel is what occludes (or the keyguard stays in front).

### 6.5 The futile arm cycle, before/after D2-3
```bash
adb logcat -c; adb shell input keyevent KEYCODE_SLEEP; sleep 2
adb shell input keyevent KEYCODE_WAKEUP; sleep 2
adb logcat -d | grep -cE "flutter : Fingerprint reader armed"
```
Today: 2–6 per wake while locked. After D2-3: 0 while locked; the dock-locked (device unlocked) panel still shows exactly 1.

### 6.6 Clock value residual race [probe]
Lock the panel (screen on), `adb shell input keyevent KEYCODE_SLEEP`, wait 10+ minutes, wake, and photograph the first frame: the clock must already show the current minute. If a stale frame is ever caught, add a `didChangeAppLifecycleState(resumed)` refresh of `_currentTime`/`_now` in all four clock states (one line each; the minute-gated timer stays).

### 6.7 Clock format [probe]
Settings → Date & time → switch 12/24-hour, then compare the cover-screen clock (`folded_cover_screen.dart:331`) and the ColorOS status bar. Today the launcher ignores the switch on all four surfaces (`cosmic_lock_screen.dart:1228-1229`, `folded_cover_screen.dart:331`, `tabletop_cockpit_view.dart:173`, `main.dart:678-681`). After D2-4 it follows it. If the device is already 24-hour, the user's "wrong time" report cannot be the format — then re-interview with §3.1's dead-card repro in hand (the wrong moment was the ask, not the clock).

### 6.8 Test impact of the proposed changes
- D2-1: no test changes (injected-hook tests keep the hook-first path, `cosmic_lock_screen.dart:352-355`).
- D2-2: revises two expectations in `test/lockscreen_auth_prompt_test.dart` (319-364, 366-413) whose comment (327-331) documents the immediate-card decision being reverted.
- D1-1..D1-3, D2-3..D2-5: no Dart test pins the affected behaviour; `native_launcher_mode_test.dart:63-71` only asserts the bridge calls execute, so all 13 suites stay green.
---

## Implementation log

Implemented on `fix_lock_screen` as the code pass for this report's ranked fixes. Baseline at start: `flutter analyze` clean, 117 tests green (13 suites), debug build compiling. The sandbox on this machine cannot execute any `flutter`/`dart`/`gradle` command (read-only SDK caches), so all verification below is static: every touched region was re-read after editing, a comment/string/interpolation-aware brace-balance check was run over every edited Dart and Kotlin file (all balanced, checker validated against untouched files), and each changed test expectation was traced by hand against the new control flow. The orchestrator's `analyze`/`test`/`build` run is the authoritative gate.

### Done

- **D1-1** — `MainActivity.kt` `ACTION_SCREEN_OFF` now also drops the event when `!launcherResumed`, with the required exact log line, in addition to the unchanged `foreignTaskOwnsScreen` drop. The report's §2.5 panel-inflation fallback was deliberately NOT implemented (per instruction); if `launcherResumed` ever shows a false negative, that is the documented remedy.
- **D1-2** — `_lockForScreenOff()` re-asserts `setLockScreenOverlayEnabled(true)` before the `_isLocked` early-out (with both required `CF_LOCK:` markers), and all four lock buttons (cover screen, cockpit view, HUD, cockpit bar) route through the new `_mountLockPanel()`, which pushes the flag first in Cosmic mode and is a no-op re: the overlay in Native mode.
- **D1-3** — `_loadApplications()` checks `isKeyguardLocked()` before the overlay push; locked + Cosmic mounts the lock panel instead of exposing home (with the `CF_LOCK:` marker), locked + Native keeps today's `setLockScreenOverlayEnabled(false)`, unlocked + Cosmic keeps the unconditional `true` push.
- **D2-1** — the refused-reader path resolves via `_useCredentialFallback()` unconditionally now, in `_authenticateWithSensor()` and in the `error` and `unavailable` branches of `_onFingerprintEvent`. Production (no hook) resolves as `deferToPlatform` → platform `requestDismissKeyguard` bouncer, one ask. Injected-hook path stays first.
- **D2-2** — the unconditional card raise is gone. `_authWanted` is set and only `listening` promotes it to `_authTarget`; the one exception is a tap while `_sensorArmed` (live reader, keyguard already dismissed — the dock privacy lock), which raises the card immediately so a granted reader still answers with the card. A refused reader therefore never sees a card; a granted reader sees it exactly as before.
- **D2-3** — native `startFingerprintScan()` refuses before touching the sensor when `KeyguardManager.isKeyguardLocked` (order: capability → screenOff → keyguardLocked → background), emitting `{"type": "keyguardLocked"}`; Dart's `_onFingerprintEvent` gains the matching case, which marks the reader unusable, logs the `CF_FP:` marker and resolves a pending request via `_useCredentialFallback()`. Consequence, by trace: while locked, every arm now ends at the native refusal before `FingerprintManager.authenticate` is ever called — 0 sensor sessions per wake (the Dart-side arm *request* is a cheap no-op round trip); the unlocked dock lock arms once and the card works there.
- **D2-4** — new `lib/ui/format/clock_format.dart` (`formatClockTime`) renders `HH:MM` in 24h and `h:MM AM/PM` in 12h per `MediaQuery.alwaysUse24HourFormatOf(context)`; used by all four clocks (lock panel, cover header, tabletop HUD, header HUD). Clock *value* logic untouched everywhere. The header HUD's 1-second timer now has the same minute-rollover gate as the other three, so it no longer rebuilds its subtree every second.
- **D2-5** — `USE PIN` → `UNLOCK` with the semantics label "Unlock using the device credential instead of the fingerprint"; the three test references updated.

### Test changes (`test/lockscreen_auth_prompt_test.dart`, plus new file)

- "a refused reader keeps the card up while the platform asks" → renamed "a refused reader asks the injected credential hook first": the hook is still asked first and drives the outcome (unchanged), but the card expectations flipped to `findsNothing` — no `listening` ever arrives in that flow, so no card is honestly drawable. Comment documents the production/test split.
- "a refused reader is not re-armed by the next tap": only the second-tap card expectation flipped to `findsNothing`; `asks == 2` (no re-arm) unchanged.
- NEW "a refused reader with no injected hook resolves through the platform bridge": production truth — no card, request resolves `deferToPlatform`, app launches via the platform bridge.
- NEW "a keyguard-locked refusal resolves the request immediately": pins the new D2-3 event end-to-end.
- `test/clock_format_test.dart` (new): pins both formats by setting `alwaysUse24HourFormat` explicitly. Verified against this machine's Flutter 3.47.5 sources that the test host defaults to **12-hour** (`_PlatformConfiguration.alwaysUse24HourFormat = false`), not 24h as this brief guessed — so the test pins both formats rather than trusting the ambient value. No existing test asserts clock text (grepped), so the format change is fallout-free by inspection; `test/folded_screen_test.dart`/`widget_test.dart` pump the full app and now start with the lock panel mounted (host simulates locked keyguard per `LauncherBridge.isKeyguardLocked`), but their `find.byType` assertions are unaffected — the panel overlays the home content without removing it from the tree.

### Deviations from the brief

- **D2-2 marker scope**: the brief asks for the `CF_FP: reader refused while keyguard locked; deferring to platform prompt` marker "on that path". It is emitted on the refused-tap fast path, the `keyguardLocked` event case, and the `error`-branch resolution — but not the `unavailable` branch, where the reader is absent rather than refused by the keyguard (the existing "Fingerprint reader unavailable" log covers it; the marker text would be a lie there).
- **Brief's test-host assumption corrected**: test hosts default to 12-hour, not 24h (source-verified); handled as described above.
- Nothing outside the allowed file set was touched. `lib/core/launcher_bridge.dart`'s `fingerprintEvents` doc still lists only the old event names (`screenOff`/`background`/`keyguardLocked` are undocumented there); that file was out of bounds for this pass.

### Residual uncertainty (for the orchestrator's feedback round)

- `flutter analyze`/`test`/`build` were NOT run (sandbox cannot); all checks above are static. Highest-risk areas if anything trips: the two rewritten refused-reader tests (timing traced but not executed) and the two new tests.
- D1-3 residual UX (a direct consequence of the brief's chosen design, worth a device pass): on cold start behind a locked keyguard with no intervening screen-off, `keyguardWasLocked` is false, so the first `USER_PRESENT` is dropped and the cosmic lock panel remains mounted over an unlocked device — cleared by one swipe (`_enterLauncher` sees the keyguard open and unlocks without any prompt). If a power cycle happens before the unlock, `keyguardWasLocked` records the locked state and `userPresent` clears the panel automatically.
- The lock panel mounted by D1-3 occludes nothing while the keyguard is in front (overlay flag deliberately not pushed), so nothing is drawn over a locked keyguard; the panel becomes visible only after the platform keyguard is gone.
- Out-of-scope leftovers recorded earlier are untouched on purpose: `initialAuthenticated` (dead), the `92%` battery string, the optimistic `listening` emission, D1-4/D1-5.

### Fix round 1 — clock-width layout fallout

- **What overflowed** (from the orchestrator's `flutter test` run; 4 failures, one cause): the folded cover header Row (`folded_cover_screen.dart:344`, 38px over its 328px content width) and the CosmicHeaderHud Row (`main.dart:739`, 44px over), both because the clock Column was inflexible.
- **Cause**: D2-4 made the clock width follow the platform's 12/24-hour setting, and a 12-hour reading ("7:05 PM") has more glyphs than "19:05" at the same font size — under the test host's uniform-advance font that is ~100px wider at fontSize 52, and the test host defaults to 12-hour, so the tests exercised exactly the real-world 12-hour case. The helper's output format was NOT changed.
- **Fix (layout only, no test expectations touched)**: both clock Columns are wrapped in `Flexible` and the time `Text` in `FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft)`, so the column yields — the cover posture chip keeps its fixed size, the utility shelf keeps its existing `Flexible`+scroll — and a wide reading scales down to the share it is given instead of overflowing. On real fonts at normal widths nothing scales (readings fit the shares), so the 24-hour look is unchanged. Verified by trace at both failing viewports (shares ~200px cover / 153px HUD at 360 wide): no RenderFlex can overflow, since flex children always get bounded shares and `scaleDown` clamps the text inside them.
- **Dispositions of the other two clock sites** — left alone deliberately, no Row can clip either:
  - `cosmic_lock_screen.dart`'s large clock (fontSize 64 narrow / 76 unfolded / 52 tabletop) is a direct child of a centered `Column` (loose bounded width, no Row): on the 360px cover the reading is ~220-270px against ~312px available, so it cannot overflow; a hypothetical worse case soft-wraps (the string contains a space) rather than throwing a RenderFlex exception, and no lock-screen test sets a viewport narrower than the 800px default (all 13 lock suites stayed green this round).
  - `tabletop_cockpit_view.dart`'s HUD clock (fontSize 52) is likewise a direct Column child, and the cockpit renders only on the physically-unfolded display (≥ ~700px of width; its one test pumps 1200px), leaving ~5× headroom.
  - Known residual from that choice: at 1.5× accessibility text scale on a 360px cover the lock clock reading can exceed its column and soft-wrap to two lines ("7:05" / "PM") — cosmetic, no exception, and consistent with how that screen already handles oversized text elsewhere; flagged for a later pass if it reads badly on device.

### Fix round 2 — posture test vs. the D1-3 cold-start panel

- **Root cause** (two sentences): the test host's bridge reports the keyguard locked by design, so D1-3 correctly mounts the lock panel at every `ChronoFoldApp` cold start on the host — and a mounted panel is exactly what `main.dart`'s `TickerMode(enabled: false)` is for, so the `AnimatedSwitcher` fade never advances and the outgoing `GalaxyInteractiveCanvas` is retained forever. On a device this resolves the moment the user unlocks (the mute lifts and the switcher completes), so the app behaviour is right and stays; what was missing was a way for the app-level test to say "unlocked device".
- **Change 1 — injectable seam** (`lib/main.dart`, matching the repo's `CosmicLockScreen.isKeyguardLocked` pattern one level up): `ChronoFoldApp` and `ChronoFoldHomeScreen` gained an optional `isKeyguardLocked` parameter (default null), and the D1-3 branch now calls `await (widget.isKeyguardLocked ?? LauncherBridge.isKeyguardLocked)()`. `const ChronoFoldApp()` stays valid everywhere; null means production, i.e. the bridge.
- **Change 2 — posture test** (`test/folded_screen_test.dart`): both pumps of 'Switches between FoldedCoverScreen and GalaxyInteractiveCanvas on fold/unfold' now inject `isKeyguardLocked: () async => false` (an unlocked device), with a comment saying why, so the switcher is free to retire its outgoing child and the two original intent assertions hold unchanged.
- **Change 3 — new pin**: 'A locked device mounts the lock surface at cold start' pumps `ChronoFoldApp(isKeyguardLocked: () async => true)` at 360x800 and asserts `find.byType(CosmicLockScreen)` is mounted at cold start — the D1-3 security behaviour now has its own regression test instead of being an accident of the host's default.

### Fix round 3 — D1-1's premise failed on device; §2.5's fallback ships instead

- **Failed premise (measured on CPH2765, ColorOS 16, Cosmic mode)**: report §1.4 assumed the occluding launcher stays resumed through doze, so `launcherResumed == false` would mean "screen off behind a foreign task". On this build `onPause` runs *before* the SCREEN_OFF broadcast is delivered even when the launcher is the visible top activity — so D1-1's new gate fired for lock-from-home itself. Device evidence, power-press on the launcher's own cover home:
  ```
  09-29 20:11:27.632 21819 21819 D ChronoFold: Screen off while the launcher is not the foreground surface; leaving the lock to the platform keyguard
  ```
  After wake, the launcher was the focused window and the home surface was fully visible (screenshot-confirmed app grid, search pill, sectors, dock) **while the device was genuinely locked**:
  ```
  mCurrentFocus=Window{... com.launcher.chronofold.mylauncher/com.launcher.chronofold.mylauncher.MainActivity}
  mKeyguardOccluded=true mKeyguardOccludedPending=true
  Trust manager state: ... trustState=UNTRUSTED, deviceLocked=1
  ```
  That is the disclosure class D1-3 closed, reintroduced by D1-1 — a device regression in the primary case.
- **The revert (native)**: the `if (!launcherResumed) return` block and its comment are removed from ACTION_SCREEN_OFF in `MainActivity.kt`, and nothing replaces it. The original `foreignTaskOwnsScreen` drop (apps the launcher itself launched) is untouched — that latch is set only by our own handoff and is unaffected by the lifecycle race. `launcherResumed` keeps its remaining job as the `startFingerprintScan` guard.
- **The reconcile (Dart, the race-free Path B fix)**: the ghost-panel case D1-1 was aimed at (screen-off inside an app opened from a notification/recents — never marked foreign) is now closed at the other end. `main.dart` tracks `_lockMountedByUserAction` (true only via `_mountLockPanel`, false for screen-off and cold-start mounts) and passes `reconcileOnMount: !_lockMountedByUserAction` to `CosmicLockScreen`. When true, the panel — from a post-frame callback in `initState`, i.e. once frames are definitely pumping — asks the keyguard through the existing injectable seam; an unlocked answer clears the panel via `onUnlock` with `CF_LOCK: panel reconciled away; keyguard already unlocked`, guarded by `mounted && !_disposed && !_handedOff`. No dependence on lifecycle timing:
  - screen-off on the launcher → panel mounts, keyguard IS locked → stays (**lock-from-home restored**);
  - screen-off behind a foreign app → panel mounts invisibly (the launcher cannot draw there), user unlocks, launcher finally pumps a frame → keyguard answered unlocked → panel clears itself (**no ghost**);
  - cold start raced by an unlock before the first frame → same reconciliation;
  - the dock/HUD privacy lock passes `reconcileOnMount: false` and stays up on an unlocked device, exactly as before.
- **Net**: report §2.5 D1-1's own belt-and-braces fallback is the shipped behaviour; D1-1 as originally implemented is not. `reconcileOnMount` defaults to false, so every existing panel test and call site behaves as it did before this round.

## Phase 3 — the leftovers the merged PR deliberately deferred (F1–F5)

Implemented on `fix/lockscreen-followups`, resuming a run that a rate limit killed mid-edit. Baseline for honesty: **the branch did not compile at the start of this resume.** The killed run had already landed the `"getBatteryState"` channel case calling a function it never wrote — `flutter analyze` (Dart only) looked green while Kotlin could not build, which is exactly the blind spot the arm64 debug build covers. The first change of this resume was writing `MainActivity.getBatteryState()`; nothing else on the branch was reverted, and every landed native edit (F1 `onCreate`, F4 return-value + `listening` move, F5 `isDeviceSecure` case, F3 channel case) was re-read and kept as it stood.

### F1 — cold boot: the panel sat over an unlocked device

- **Root cause.** `keyguardWasLocked` was set only in the `ACTION_SCREEN_OFF` branch, so a cold boot — locked at process start, no SCREEN_OFF ever arriving inside that process — left the flag false and the first `USER_PRESENT` was dropped at `MainActivity.kt:179`. The panel mounted by the D1-3 cold-start check then never heard the platform authenticate, and sat over an unlocked device until a swipe cleared it.
- **Change, native** (landed by the killed run, kept): `onCreate` records `keyguardWasLocked = true` when the keyguard is already locked at process start. The write is deliberately one-way (true only) so a rotation/unfold recreation cannot clobber a pending lock an intervening SCREEN_OFF recorded, and a start that begins unlocked leaves the flag false. `onResume` was considered and rejected in the code comment: it fires in exactly the window `USER_PRESENT` arrives in.
- **Change, Dart (the belt-and-braces)**: `_reconcileAgainstKeyguard()` now also runs when the panel's lifecycle returns to `resumed` (`didChangeAppLifecycleState`), gated by the same `reconcileOnMount` condition and the same `mounted && !_disposed && !_handedOff` guards. A single dropped broadcast can no longer strand the panel: the launcher regains the screen exactly on that transition, and a panel that stands for a keyguard asks the keyguard again and clears itself if the lock is gone. A panel mounted by the LOCK buttons (`reconcileOnMount: false`) still stands for the user's wish and does not reconcile.
- **Trace end to end.** Cold boot locked → D1-3 mounts the panel → post-frame reconcile sees locked → stays. Platform unlock → native `USER_PRESENT` now un-dropped (`keyguardWasLocked` was recorded at start) → panel clears. If that broadcast is dropped anyway → Flutter resumes with the screen → `resumed` → `_reconcileAgainstKeyguard` → keyguard answers unlocked → panel clears. Two independent nets, neither depending on the other.
- **Test**: `test/lockscreen_reconcile_test.dart` (new) — the positive drives a `reconcileOnMount` panel whose seam reports locked first then unlocked through a real inactive→resumed transition and asserts `onUnlock` fired; the negative asserts the same transition does NOT clear a `reconcileOnMount: false` panel.
- **Residual**: the resumed pass runs one extra keyguard probe per resume on reconcile-eligible panels (cheap; the alternative — trusting the broadcast — is the bug). Verified statically only; the orchestrator's device pass owns the cold-boot proof.

### F2 — `initialAuthenticated` was dead code

- **Root cause.** Declared, defaulted, read nowhere in `lib/`; only `test/lockscreen_physics_test.dart:215` passed it.
- **Change.** Field, constructor parameter and the test argument deleted. The test's real gate — `isKeyguardLocked: () async => false` and its comment explaining why the swipe must not be the subject — is untouched, and its comment still reads correctly without the dead argument (it was attached to the keyguard seam, not to `initialAuthenticated`). Test intent (render + shake + swipe) unchanged.
- **Residual**: none. `const CosmicLockScreen(...)` stays valid everywhere (`main.dart` never passed the parameter).

### F3 — the lock surface lied about the battery

- **Root cause.** `Text('92%')` hardcoded under an always-lit `battery_charging_full_rounded` glyph (`cosmic_lock_screen.dart:1517-1537` at branch start), flagged in `reports/launcher-critique.md:32`.
- **Change, native**: `MainActivity.getBatteryState()` (the function the killed run forgot — see the honesty note above) reads `BatteryManager.BATTERY_PROPERTY_CAPACITY` and `isCharging`, returns `mapOf("level" to Int, "charging" to Boolean)`, and returns **null** when the level is genuinely unavailable (`Integer.MIN_VALUE`, no battery manager, or a throwing OEM build) — never a made-up number.
- **Change, bridge**: `LauncherBridge.batteryState()` follows the neighbour convention; unknown travels as null so the panel can hide the percentage instead of inventing one. New `BatteryState` model next to `FingerprintCapability`, with the pure presentation decision on it: `percentage` (`'92%'` or null) and `icon` (charging vs plain glyph).
- **Change, panel**: optional `battery` seam defaulting to the bridge. Sampled on mount, refreshed on the existing `screenOn` signal and on the clock's minute rollover — **no new timer**. The row renders the state's glyph; unknown level hides the percentage inside a fixed-width `FittedBox(scaleDown)` box, so the telemetry row keeps its shape and cannot overflow under accessibility text scale.
- **Tests**: `test/lockscreen_battery_test.dart` (new) — the pure unit tests pin `'92%'`, the unknown→null rule and the glyph decision; widget tests through the seam pin both rendered states (known → the seam's percentage and charging glyph; unknown → no percentage, plain glyph, row still up).
- **Residual**: the percentage can be up to a minute stale (deliberate — no new timer); verified statically only.

### F4 — native claimed `listening` before the platform accepted the session

- **Root cause.** `fingerprintEvents?.success(listening)` was emitted immediately after `manager.authenticate(...)` returned, before any callback; this build cancels the session in ~1–6 ms, so Dart's `_sensorArmed` flickered true for a session that never existed.
- **Change, native** (landed by the killed run, kept): `startFingerprintScan()` returns `Boolean` — every refusal returns `false` alongside its event, the channel carries that value — and the optimistic emit is gone. `listening` now fires once per session from the first `onAuthenticationHelp` (real sensor activity), silenced for superseded sessions by the existing identity check.
- **Change, bridge**: `LauncherBridge.startFingerprintScan()` is `Future<bool>` — whether a session genuinely started; false on a refusal, on a missing platform, and on error.
- **Change, panel**: armed state is now exactly "a scan was started and no terminal event has arrived", set from that return value in the new `_startScan()` (used by both the arm and the `error` retry), cleared by the terminal/refusal events as before — **never set by the arrival of `listening`**. The comment the brief asked for is in the code: a bare touch needs no prompt, so a missing `listening` costs nothing.
- **Consumer check** (every consumer of the event stream, `launcher_bridge.dart:303` onwards):
  - The card promotion was the one consumer that depended on `listening` arriving promptly. Fixed at the source: a session the platform accepts now promotes `_authWanted` to `_authTarget` directly in `_armFingerprintSensor` (the start answer is the promotion), so the card appears the moment a finger could genuinely answer it. The `listening` case keeps the same promotion as a safety net for a request that raced the arm — and as the only promotion path on a test host, where no scan can genuinely start.
  - `_authenticateWithSensor`'s already-armed branch raised the card immediately before; its comment now cites the start answer rather than a `listening` that "will not fire again".
  - No other consumer regressed: `succeeded`/`failed`/`error`/refusal cases never depended on `listening`, and the refusals still resolve pending requests through the credential fallback.
  - One test genuinely depended on the old lie: "a live reader is reused rather than re-armed on a tap" built its live-reader state from a `listening` emit, which no longer sets armed state. Fixed the consumer, not the marker: the panel gained an optional `startFingerprintScan` seam (the same repo pattern as `fingerprintEvents`), and the test now injects "the platform accepted the session" through it and pins the reuse with a call counter — a stronger pin than the old one, which could not observe the re-arm at all.
- **Probe note (§6.5)**: the `Fingerprint reader armed` marker now fires when a session genuinely started (so its count is the true arm count — the 1–6 ms phantoms no longer inflate it); `listening` logs `Fingerprint sensor activity: session live`. A clean first touch now logs no activity event at all, by design.
- **Residual**: on device, armed truth is the native return value plus terminal events; if some OEM build were to start a session without ever reporting a terminal event, armed state would stay true until the next arm guard — the pre-existing failure mode is unchanged in that hypothetical. Verified statically only.

### F5 — `isDeviceSecure` restored under the settled product decision

- **The product question is settled: full lock ownership.** The launcher mounts its own lock surface on a device with no secure lock too — the old "skip the panel when not secure" behaviour is NOT reinstated, anywhere. `reports/repro-fingerprint-unlock.md:88-90` described the old gate; this work restores the *capability* so the panel can behave honestly on such a device, not the gate.
- **Change, bridge**: `LauncherBridge.isDeviceSecure()` mirrors `isKeyguardLocked` (native `KeyguardManager.isDeviceSecure`, landed by the killed run and kept). A missing/failed answer is treated as **secure** — answering "not secure" to a failed probe would silently take the reader away from a device that has one, and the capability gate still refuses a scan when nothing is enrolled. Test hosts answer secure (they simulate a locked keyguard, which implies a credential).
- **Change, panel**: optional `isDeviceSecure` seam. The answer is taken once at mount, and the mount-time arm waits for it, so a credential-less device never spends even the capability probe on a fingerprint that cannot exist there. `_armFingerprintSensor` also guards on it for the arms that do not come from mount (screen-on, resume, a tap). On a not-secure device the panel: arms no reader, draws no `LOCKED` badge (a cover is not a lock — badging it would be the same pretend as asking for a fingerprint), and resolves an app tap through the credential fallback, which there means the platform's silent `requestDismissKeyguard` — no ask anywhere. On a secure device nothing changes (same arm, same badge).
- **Interpretation note**: "render the unlock affordance as a plain dismiss" is implemented as the badge removal plus the no-ask tap path; the swipe-up affordance itself (`_enterLauncher`) was deliberately left alone, because on a credential-less keyguard `requestDismissKeyguard` already *is* a silent programmatic dismiss — short-circuiting it would leave a swipe-style keyguard revealed underneath and cost the user a second swipe. The hint text stays `TAP APP TO LAUNCH • SWIPE UP TO ENTER`, which on such a device is exactly the truth.
- **Test**: `test/lockscreen_device_secure_test.dart` (new) — non-secure: panel mounts, no capability probe, no scan start, no LOCKED badge, plain-dismiss hint, and an app tap resolves through the platform with no card and no scan; secure (production default): the mount arm still happens and the badge still draws.
- **Residual**: the badge draws from the first frame until the secure answer lands (null is drawn as secure), so a credential-less device shows it for the one probe round trip; reversing that default would flash the badge *in* on every secure-device mount instead. Verified statically only.

### The open question — foreign app owning the screen at lock time (deliberately unresolved)

The delegation on SCREEN_OFF (`foreignTaskOwnsScreen`, `MainActivity.kt`) is untouched. Mechanism: the latch is set only by the launcher's own launch handoff; when a launcher-launched app owns the screen, SCREEN_OFF is dropped so ColorOS's keyguard owns the lock, and returning from the app lands on the platform keyguard rather than on a launcher surface that would re-assert `showWhenLocked` over a paused activity and ask for a fingerprint (the recorded regression). The orchestrator is measuring the current device behaviour before deciding; nothing in Phase 3 prejudges it.

### Verification status (read as: what was NOT run here)

The sandbox cannot execute `flutter`/`dart`/`gradle` (read-only SDK caches — known). Everything above was verified statically: every edited region re-read after editing; a state-machine brace/paren scanner (string-, raw-string-, interpolation- and comment-aware, validated against untouched `lib/main.dart` and other control files) run over every touched Dart and Kotlin file — all balanced; every changed test expectation traced by hand against the new control flow, including all thirteen pre-existing suites' panel pumps (the host's bridge answers make the secure/not-secure and armed/refusal defaults preserve each suite's behaviour). The orchestrator's `analyze`/`test`/arm64 build/on-device pass is the authoritative gate; the highest-risk static claims are the rewritten live-reader test's microtask timing and the three new suites' first run.
