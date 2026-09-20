# Lock screen fingerprint prompt — app-styled card, with the platform's own prompt as the read

- Repro / verification: `flutter test test/lockscreen_auth_prompt_test.dart` (cwd: `/Users/benjerome/Documents/Dev/mylauncher`)
- Device: OPPO CPH2765, ColorOS 16 / Android 16, folded on the cover display
- Screenshots: `.agent-shots/fingerprint-prompt/`

## What was asked

1. Every app icon in the lock screen grouping must open its app once the
   fingerprint is validated. (Confirmed by the user: this already worked, via
   the platform prompt.)
2. The element that asks for the fingerprint must look like the rest of the
   launcher instead of a stock system dialog.

## What the device allows, measured

`BiometricPrompt` always draws its own system dialog, so the only way for the
panel to own the affordance is to read the sensor itself — which it already did,
silently, through the legacy `FingerprintManager`. On the CPH2765 while the
device is locked, **every** arm of that reader is refused:

```
$ adb shell am force-stop com.launcher.chronofold.mylauncher && adb logcat -c
$ adb shell am start -n com.launcher.chronofold.mylauncher/.MainActivity
I/flutter: Fingerprint reader armed
I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
I/flutter: Fingerprint reader armed
I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
...                                    (six arms in 200 ms, fresh process)
```

Arm, `listening`, cancelled within ~2 ms, with no competing session. The rule:
**while the device is locked, only the keyguard may use the sensor.** The
launcher draws over the keyguard (`showWhenLocked`) — which is exactly what
makes its lock screen visible at all — and that same occlusion is why the
keyguard refuses an app-owned reader session. An earlier attempt to blame the
re-arm on tap was wrong: a session armed at mount is refused just as fast.

The shape of the session is not the problem either. A session bound to a
keystore key — a real crypto operation rather than a bare check — is armed and
cancelled in ~1 ms, identically:

```
I/flutter: Fingerprint reader armed
I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
```

(An unbound key cannot even get that far: the platform rejects an uninitialized
cipher with "Crypto primitive not initialized", and a per-use key refuses to
initialize before the user has authenticated. The experiment is not in the tree;
the finding is recorded next to `startFingerprintScan` so nobody repeats it.)

Once the keyguard has actually been dismissed, the panel's reader *is* allowed,
and the card reads the finger with no system dialog at all.

The platform prompt, by contrast, always works, because it goes through
`BiometricService` as a keyguard dialog:

```
E/OplusCustomizeRestrictionManagerService: isBiometricDisabled start
W/BiometricUtils: callingUid: 10069 ...
I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
D/AuthController: showAuthenticationDialog ... requestId: 194
mCurrentFocus=Window{... BiometricPrompt}
```

## What the panel does with that

```
tap app → arm the reader
        → handed over?  cosmic card alone → print → app opens   (no system dialog)
        → refused?      no card; platform prompt reads → app opens
```

The card is dropped on the refused path on purpose. That prompt is a
full-screen secure `KEYGUARD_DIALOG`: it covers whatever the launcher draws, so
a card underneath it can neither be read nor touched, and two panels asking for
the same finger reads as two lock screens fighting.

The card is drawn by the launcher, in its own language: glass surface, cyan and
violet hairline and halo, breathing reader rings around a fingerprint disc, the
app's icon and name, a live status line, and themed `CANCEL` / `USE PIN`
buttons. It is a live region whose buttons are real nodes with declared tap
actions, and it honours reduce-motion. `USE PIN` appears once the finger itself
is the problem — a run of non-matches — never while the reader is simply waiting
for a touch. A refusal is remembered for the rest of the lock session, so a tap
costs one frame rather than six sensor arms.

## Defects the tests caught on the way

- The card's entrance was driven from the repeating pulse controller, so the
  card faded back in at the start of every 1.9 s cycle — a flash, and, because a
  fully transparent `FadeTransition` drops its subtree from the semantics tree,
  a card that periodically vanished for a screen reader.
- The reduce-motion guard compared against a field initialised to `false`, so
  the first `didChangeDependencies` returned early and the entrance never
  started: the card sat at opacity 0 and was never visible at all.
- The card's spoken label was the whole card concatenated; the visible title,
  status and app name are now excluded, so a reader hears the curated label and
  value once.
- The buttons declared `excludeSemantics` with no action of their own, so a
  reader could hear `CANCEL` but not press it.
- `_armFingerprintSensor` cancelled and re-subscribed on every arm; the reader
  is a broadcast stream, so a match reported in that window was dropped. It now
  subscribes once for the panel's lifetime.
- A stale Dart-side copy of the panel-on state left the reader permanently
  unarmed after a pause/resume. The native side already refuses an arm while the
  panel is off without touching the sensor, so its answer decides now.

## Verification

```
$ flutter analyze lib test
No issues found!

$ flutter test
00:06 +109: All tests passed!
```

`test/lockscreen_auth_prompt_test.dart` (new, 9 tests) drives the silent reader
directly and holds the new behaviour:

- tapping a bubble raises the panel's own prompt, naming the app;
- a live reader is reused rather than re-armed on a tap;
- a sensor match opens the app the user tapped, and leaves the panel up so
  closing it returns to the lock screen;
- cancel launches nothing and says so;
- a non-match keeps the prompt and stays armed, and a later good read still
  opens the app;
- a refused reader hands straight to the platform prompt with no second panel,
  and opens the app when that answers;
- a refused reader is not re-armed by the next tap;
- a device with no enrolled finger never raises the panel prompt;
- the prompt is announced as a live region whose buttons carry a tap action.

Device checks: tapping the phone shortcut on the locked panel logs the resolved
target and then raises `AuthController: showAuthenticationDialog` with
`mCurrentFocus=Window{... BiometricPrompt}` and no launcher card on screen. On
the unlocked path the card is the only prompt. Screen capture of the locked case
returns an all-black frame, because the platform prompt is a secure
`KEYGUARD_DIALOG`; the card's own appearance is captured in
`.agent-shots/fingerprint-prompt/00-cosmic-fingerprint-prompt.png` (taken while
the panel was still waiting on the reader, before the hand-off existed).

## Files changed

- `lib/features/lockscreen/fingerprint_prompt.dart` — new. The cosmic card.
- `lib/features/lockscreen/cosmic_lock_screen.dart` — auth state machine, the
  `listening` gate, the single reader subscription, `_sensorUnusable`, the
  automatic credential handoff, and the modal card overlay.
- `android/.../MainActivity.kt` — `startWhenUnlocked` releases the reader before
  asking the keyguard to go; `authenticateUser` does the same before raising the
  system prompt.
- `test/lockscreen_auth_prompt_test.dart` — new. 9 tests.

## Residual uncertainty

- **The read cannot be app-styled while the device is locked.** The keyguard owns
  the sensor there, and the only authentication it accepts is its own prompt.
  A fully custom fingerprint UI on a locked device would mean giving up
  `showWhenLocked`, and with it the cosmic lock screen's presence while locked.
  That trade-off was put to the user, who chose to keep the lock screen and let
  the platform prompt own the fingerprint UI on that path.
- The card is therefore only reachable once the keyguard has been dismissed —
  the device unlocked and the launcher locked as a privacy screen. That path is
  covered by tests only; it needs an unlocked device to reproduce on the panel.
- The platform prompt is a secure window, so `screencap` returns an all-black
  frame and its exact appearance could not be reviewed here.
