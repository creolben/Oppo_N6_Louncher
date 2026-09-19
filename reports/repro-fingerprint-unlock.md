# repro — lock screen does not unlock when the fingerprint sensor is touched

- **Layer:** environment (Android platform integration; not reproducible in a host unit test)
- **Repro command:** see the scripted sequence below (cwd: `/Users/benjerome/Documents/Dev/mylauncher`)
- **Device:** OPPO CPH2765, ColorOS 16 / Android 16, folded on the cover display
- **Symptom reported:** "the lockscreen failed to unlock when I touch the print sensor"

There are two distinct defects behind the report. Both are device-layer, so the
repro is a scripted adb sequence plus logcat, not a Dart test. The reader is the
side power button and the platform owns it through SystemUI, so the failing
behaviour cannot be produced in `flutter test` (where `Platform.isAndroid` is
false and no sensor exists).

## Red 1 — the reader is armed while the panel is off, then gives up

Sequence:

```bash
DISP=4630946165954792596
adb shell input keyevent KEYCODE_WAKEUP
adb shell input swipe 570 2500 570 1400 200      # unlock to the cover view
adb logcat -c
adb shell input keyevent KEYCODE_SLEEP           # panel off: app locks and arms
sleep 6
adb logcat -d | grep -E "flutter :"
```

Captured output:

```
09-19 12:32:08.235 32169 32169 I flutter : Fingerprint sensor stopped: 5 Fingerprint operation canceled
09-19 12:32:08.664 32169 32169 I flutter : Fingerprint sensor stopped: 5 Fingerprint operation canceled
09-19 12:32:09.269 32169 32169 I flutter : Fingerprint sensor stopped: 5 Fingerprint operation canceled
```

Three cancellations in one second — the app's own retry timer — against a panel
that was off, so every attempt was cancelled by the platform. With the retry
budget spent, the affordance never recovered:

![after wake](.agent-shots/repro/red-2-after-wake.png) — reads `FINGERPRINT UNAVAILABLE`

A touch on the sensor therefore could not do anything for the rest of that lock
session. Root cause: the app armed on mount (which happens on `SCREEN_OFF`)
instead of only while the panel was interactive.

## Red 2 — the sensor is unusable while the keyguard is occluded

Measured on the same device, with the app's own instrumentation:

```
12:48:54.230 startScan interactive=true
12:48:54.234 onAuthError code=5 msg=Fingerprint operation canceled live=true
12:50:23.710 SCREEN_OFF locked=true kgLocked=true devLocked=true secure=true
12:50:27.621 SCREEN_ON  locked=true interactive=true kgLocked=true devLocked=true
12:50:27.630 onAuthError code=5 msg=Fingerprint operation canceled live=true
```

Every request was preempted **1–6 ms** after being issued, on all four runs, and
`adb shell dumpsys window` reported `mKeyguardOccluded=true`. Because the
activity used `showWhenLocked`, it covered the keyguard; while the keyguard is
occluded Android disables the system biometric path *and* refuses app requests,
so no one can read the sensor, and no unlock ever follows a touch.

## Green

1. No arm while the panel is off, and no dead affordance. Same sequence as Red 1:

```
(no output)                       # nothing armed, nothing cancelled
```

and after the wake the lock screen draws no fingerprint affordance at all — no
sensor disc, no status label — because the panel is not the reader:

![after wake](.agent-shots/fingerprint-removed/lock-screen-no-fingerprint.png)

2. The keyguard is no longer occluded, so the platform owns the sensor. The
   activity stopped using `showWhenLocked`; measured after the change:

```
$ adb shell dumpsys window | grep mKeyguardOccluded
    mKeyguardOccluded=false mKeyguardOccludedChanged=false mPendingKeyguardOccluded=false
```

Confirmed by the user on the device: touching the sensor unlocks, and the
launcher lands on the cover view.

3. The in-app overlay is no longer raised on screen-off for a secure device, so
   it cannot flash over the platform unlock. `_lockForScreenOff` consults
   `LauncherBridge.isDeviceSecure()` first.

## Files changed

- `android/app/src/main/AndroidManifest.xml` — dropped `showWhenLocked`/`showOnLockScreen`
- `android/app/src/main/kotlin/.../MainActivity.kt` — stopped setting show-when-locked; added `isDeviceSecure`; refused to arm when `!isInteractive`; screen-on broadcast; gated `USER_PRESENT`
- `lib/features/lockscreen/cosmic_lock_screen.dart` — panel-state gate, no arm
  storm, platform-unlock handler; the on-screen fingerprint affordance (sensor
  disc, pulse rings, status label) is gone, since the panel cannot be pressed to
  unlock and the reader is the side power button
- `lib/core/launcher_bridge.dart` — `isDeviceSecure`, screen-on and user-present listeners
- `lib/main.dart` — in-app lock only when the device has no secure lock

## Residual uncertainty

- The user's confirmation is verbal; the final touch-to-unlock was not
  independently observable by the author, who has no finger on the device.
- `USER_PRESENT` is gated on the keyguard having been locked when the panel went
  off, but that flag was measured `true` in both a genuine unlock and a bare
  wake, so it is a coarse filter rather than proof of biometrics. It is safe
  here only because a secure keyguard cannot be dismissed without credentials.
- The app's own silent reader session still exists for the case where the
  launcher is locked while the device is already unlocked (the dock lock
  button); it is not exercised by this repro.
