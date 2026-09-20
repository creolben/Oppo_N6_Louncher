# ChronoFold ↔ ColorOS 16 — clash analysis

- **Device under test:** OPPO Find N6 `CPH2765`, ColorOS 16 / Android 16, build
  `CPH2765_16.0.10.500(EX01)`, `targetSdk 36`, cover display 1140x2616, inner display 2248x2480, 520dpi
- **Method:** live `adb`/`dumpsys` probing of the running device, the installed merged manifest, the
  installed package's resolver tables, and a read of the native + Dart integration code
- **Status of the app on this device:** it **does** hold the HOME role and **is** the resolved default
  launcher — this is not a "can't get the role" problem

Every finding below is labelled by how it was established:

- **[M]** measured on the device / in the installed artifacts in this session
- **[D]** read directly out of this repo's source
- **[?]** inference or inference-grade, with the reasoning stated

> Note on the existing reports: `reports/repro-fingerprint-unlock.md` §Green and
> `docs/coloros16-launcher-research.md` §Local observation both describe a state of the tree that
> **no longer exists**. They are treated below as stale, and the discrepancies are called out
> explicitly rather than relied on.

> **Revision note (post-review).** A follow-up research pass verified several mechanisms against
> developer.android.com and AOSP source, and **corrected two findings in this report**: §5 is now
> *verified* rather than an inference (the portrait lock is genuinely ignored on the inner display),
> and the framing of §2 was sharpened — `showWhenLocked` does **not** itself break ColorOS biometrics;
> the platform policy is what blocks an app-owned reader. One new clash was added (§11, predictive
> back). Corrections are marked inline.

---

## Ranked summary

| # | Clash | Severity | Evidence |
|---|---|---|---|
| 12 | **ColorOS still wakes its own launcher on HOME** even when another holds the role — the ~1s bare-wallpaper flash | **Critical (not app-fixable)** | [V][M] |
| 1 | Android does not register the launcher as the **home process**, so AOSP's own home protection never applies | **High** | [M] |
| 3 | Gesture navigation / recents / home animations are owned by OPPO's launcher, not the HOME app | **High** | [V][M] |
| 2 | `showWhenLocked` occlusion vs. the keyguard-owned sensor: app-owned biometrics are platform-impossible while locked | **High** | [V][M] |
| 4 | The tree is internally contradictory about the keyguard; an earlier "fixed" report is invalidated | **High** | [M][D] |
| 5 | `screenOrientation="portrait"` is **ignored** on the `sw692dp` inner display under Android 16 | **High** | [V][M] |
| 11 | Predictive back forced on for targetSdk 36; back is intercepted with no exit branch | **Medium-High** | [V][D] |
| 6 | ColorOS applies Material You dynamic colour; the launcher hard-codes its palette | **Medium** | [M][D] |
| 7 | The launcher is a 1.8GB debug build and is treated as a heavyweight process | **Medium** | [M] |
| 8 | `INTERNET` is missing from the main manifest — release builds have no network | **Medium** | [D][M] |
| 9 | Missing launcher-feature surface (widgets, badges, adaptive icon, backup) | **Medium** | [V][D] |
| 10 | Self-lock on backgrounding is friction without security | **Low-Medium** | [D] |
| 13 | 16KB page size — clean, no action beyond re-checking release | **Info** | [M] |

**The single most important line in this report is #12.** It is the one clash that no amount of app-side
work can remove, and it is the most likely thing a user actually notices.

---

## 1. The launcher is not registered as the *home process* — ColorOS does not protect it

**Measured.** The app holds the role, is the resolved default, and yet Android's own home-process
slot is empty:

```
$ adb shell cmd role get-role-holders android.app.role.HOME
com.launcher.chronofold.mylauncher                        # [M] role held

$ adb shell dumpsys activity processes | grep mHomeProcess
  mHomeProcess: null                                      # [M] ...but no home process registered
```

With the launcher deliberately brought to the foreground it becomes an ordinary top app rather than
a home app:

```
$ adb shell am start -n com.launcher.chronofold.mylauncher/.MainActivity
$ adb shell dumpsys activity oom | grep -A3 chronofold
  Proc # 0: fg  T/A/TOP  ... :com.launcher.chronofold.mylauncher/u0a69 (top-activity)
      oom: curRaw=0 setRaw=0   lastRss=414MB              # [M] top-activity, not HOME
```

The consequence is visible in the OOM ladder itself. Android reserves adj **600 `HOME_APP_ADJ`** for
the home process and keeps it resident; ChronoFold instead appeared at the *previous-app* rung:

```
$ adb shell dumpsys activity oom | grep -A6 "Proc # 2"
  Proc # 2: hvy  +50  /LAST  31152:com.launcher.chronofold.mylauncher/u0a69 (oplus-previous)
      state: cur=LAST set=LAST  lastRss=415MB             # [M] PREVIOUS_APP_ADJ (700), not 600
```

```
OOM levels:
    600: HOME_APP_ADJ (663,552K)
    700: PREVIOUS_APP_ADJ (663,552K)                      # [M] where ChronoFold actually sat
```

So the launcher is retained with *previous-app* priority and, with a ~415MB RSS against a 648MB
threshold, sits among the most attractive eviction candidates on the device. This is the mechanism
behind the classic third-party-launcher complaint on ColorOS — the launcher gets torn down while the
user is in another app, so returning "home" costs a full cold start.

A stronger form of the same check also passes: with a HOME app set and in the foreground, **nothing
on the device occupies the home rung at all**, and OPPO's own launcher does not occupy it either:

```
$ adb shell dumpsys activity oom | grep -B1 "cur=600 "     # [M] no process at HOME_APP_ADJ
  (no output)
$ adb shell dumpsys activity processes | grep mHomeProcess
  mHomeProcess: null                                       # [M] still null, any launcher
```

**Caveat [M]:** `mPreviousProcess` was also observed as `null` in the same dump while the launcher was
foreground, so these AMS bookkeeping fields are evidently set conditionally rather than always
mirroring reality. The *stronger* signal is the combination — null home process **and** no process at
`HOME_APP_ADJ` **and** the launcher measured at `previous-app` — not the null alone. The controlled
rebuild described below is what would settle it.

**Probable cause [D][?].** The activity declares `android:taskAffinity=""`:

```xml
android:name=".MainActivity"
android:launchMode="singleTask"
android:taskAffinity=""          <!-- empty affinity: no home task affinity -->
android:clearTaskOnLaunch="true"
android:stateNotNeeded="true"
```

An empty affinity is not the normal shape for a HOME activity, and it is the one declared attribute
that is unusual here relative to an ordinary launcher. The intent filter itself is correct and
complete — verified against the *installed* package, not the source:

```
$ adb shell dumpsys package com.launcher.chronofold.mylauncher | grep -A5 "Activity Resolver Table"
      android.intent.action.MAIN:
        com.launcher.chronofold.mylauncher/.MainActivity filter 245316e
          Category: "android.intent.category.LAUNCHER"
          Category: "android.intent.category.HOME"
          Category: "android.intent.category.DEFAULT"      # [M] filter is correct
```

so the filter is not the problem. **[?]** I could not isolate `taskAffinity=""` as *the* cause with a
controlled experiment (that would require rebuilding and reinstalling), so it is stated as the prime
suspect, not a proven root cause.

**Fix / next step.** Remove `android:taskAffinity=""` (or set a real affinity such as the package
name), rebuild, reinstall, and assert `dumpsys activity processes | grep mHomeProcess` reports
ChronoFold. That single check is the red/green for this clash.

**Also relevant [M]:** OPPO's own launcher is still installed, enabled, and running with
`com.android.quickstep.TouchInteractionService` — see §3.

---

## 2. `showWhenLocked` vs. the ColorOS keyguard: two mutually exclusive designs

**Measured and read.** The app draws over the keyguard, in two independent places:

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
android:showWhenLocked="true"
android:showOnLockScreen="true"
android:turnScreenOn="true"
```

```kotlin
// MainActivity.kt, onCreate() — the code re-asserts it at runtime
setShowWhenLocked(true)
setTurnScreenOn(true)
```

This is the design stated in the code's own comment — *"The cover screen is its own lock surface, so
it is drawn over the keyguard."* That is a legitimate choice, and it is why the launcher's own lock
screen is visible at all.

The clash is a **policy** one, not a `showWhenLocked` one — and the earlier framing of this report
was too strong. Per AOSP, `showWhenLocked` only *occludes* the keyguard (the device stays locked and
no permission is involved); what actually gates the sensor is the platform rule that **while the
device is locked, only the keyguard may use the sensor**. That rule would hold even with no occlusion
at all. The project measured it correctly in `reports/lockscreen-fingerprint-prompt.md`:

> **while the device is locked, only the keyguard may use the sensor.** The launcher draws over the
> keyguard (`showWhenLocked`) — which is exactly what makes its lock screen visible at all — and that
> same occlusion is why the keyguard refuses an app-owned reader session.

with the device log showing every arm cancelled:

```
I/flutter: Fingerprint reader armed
I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
```

and the platform's own prompt succeeding precisely because it is a keyguard dialog:

```
E/OplusCustomizeRestrictionManagerService: isBiometricDisabled start
D/AuthController: showAuthenticationDialog ... requestId: 194
mCurrentFocus=Window{... BiometricPrompt}
```

**[M]** The ColorOS biometric gate is real and observable in logcat on this device:
`OplusCustomizeRestrictionManagerService: isBiometricDisabled` is consulted around biometric use, and
`E/OplusCustomizeRestrictionManagerService` is OPPO's own restriction manager. So the fallback to
`BiometricPrompt` is not an accident of this device; it is the only path ColorOS permits while the
keyguard is up.

**The real defect is not the occlusion — it is that the tree believes both things at once.** A
non-occluding window could arm an app-owned silent reader; an occluding window cannot, and must use
`BiometricPrompt`. The code currently occludes *and* contains a silent reader plus a custom prompt
(`lib/features/lockscreen/fingerprint_prompt.dart`) built on it. **The silent-reader path is
unreachable while locked on this platform — by design, not by ColorOS defect — so that code is dead
weight until the keyguard is dismissed.**

**Residual [D] UI defect in the fallback path:** `authenticateUser()` requests
`BIOMETRIC_STRONG or DEVICE_CREDENTIAL`. Over a secure keyguard the system prompt draws *on top of*
the occluding window, so this is functional rather than broken — but it means the user is handed a
stock system dialog on a surface the whole design exists to keep in the launcher's own visual
language. That is the deliberate trade to make, not a bug to fix.

---

## 3. Gesture navigation and recents belong to OPPO's launcher, not to the HOME app

**Measured.** ColorOS does not let the default HOME app own the gesture layer. OPPO's stock launcher
(`com.android.launcher`, a `system_ext/priv-app` build of Launcher3) is running and is the component
SystemUI binds to for navigation and keyguard interaction:

```
*APP* ProcessRecord{... 32142:com.android.launcher/u0a187}
  - ServiceRecord{... com.android.launcher/com.android.quickstep.TouchInteractionService  c:com.android.systemui}
  - ServiceRecord{... com.android.launcher/com.android.keyguardservice.KeyGuardDismissedService c:com.android.systemui}
  - ConnectionRecord{... com.android.launcher/com.android.quickstep.TouchInteractionService:@55bad1d ...}
  - ConnectionRecord{... com.android.launcher/com.android.keyguardservice.KeyGuardDismissedService:@d5ada88 flags=0x1}
  - com.android.launcher.breeno.LauncherBreenoProvider
```

Two consequences, both structural rather than cosmetic:

1. **Recents/swipe-up is served by the stock launcher's QuickStep**, not by ChronoFold. A third-party
   HOME app on ColorOS cannot supply the overview/gesture surface; SystemUI keeps OPPO's. **[M]**
2. **The keyguard-dismissal path is also bound to the stock launcher**
   (`KeyGuardDismissedService`, held by `com.android.systemui`). Any launcher-owned keyguard strategy
   is therefore cooperating with — not replacing — an OPPO component that is always present.

**Also [M]:** the stock launcher is not disabled, and it is not just inert — besides the two bound
services it exposes a Breeno content provider. A third-party default HOME app should expect OPPO's
launcher to remain live alongside it.

**Compounding [M]:** a fold-specific resource overlay is enabled *only for the stock launcher*:

```
com.oplus.android.launcher.overlay.foldscreen:
  mTargetPackageName: com.android.launcher
  mState: STATE_ENABLED
  overlay path: /product/overlay/LauncherResourceOverlay/LauncherResourceOverlay.apk
```

The IDMAP log (`failed to find resource 'dimen/icon_style_size_standard'`, `'dimen/badge_num_background_height'`, …) shows OPPO ships fold-aware dimension and badge resources specifically for its own launcher. A third-party launcher gets no equivalent and must reproduce that behaviour itself.

---

## 4. An earlier "fixed" report is invalidated by the current tree

This is the most actionable *process* finding: the repository contains two mutually exclusive
accounts of the same behaviour, and the docs describe a state that is not in the tree.

`reports/repro-fingerprint-unlock.md` §Green asserts:

```
- android/app/src/main/AndroidManifest.xml — dropped showWhenLocked/showOnLockScreen
- The keyguard is no longer occluded ...
    mKeyguardOccluded=false
```

But `showWhenLocked` was **never removed**. Git records it only ever being *added*:

```
$ git log --oneline -S'showWhenLocked' -- android/app/src/main/AndroidManifest.xml
4814695 feat: implement tabletop flex cockpit mode, cosmic lockscreen physics, ...
```

`4814695` is when it was introduced; no later commit removes it. The manifest still declares it, the
activity still calls `setShowWhenLocked(true)`, and the comment in `onCreate` now documents drawing
over the keyguard as intended. The measured `mKeyguardOccluded=false` in that report was therefore
either captured in a non-locked state or has since been re-broken — it does not describe the current
build.

This matters because **`reports/lockscreen-fingerprint-prompt.md` was written later and reaches the
opposite, correct conclusion** (the occlusion is why app-owned biometrics fail). The two reports
cannot both be current. Anyone reading `repro-fingerprint-unlock.md` would conclude a solved problem
has regressed; the truth is the fix was never in the manifest.

**Also [M]:** `MainActivity.kt` and `cosmic_lock_screen.dart` have **uncommitted** changes, and the
installed APK (`lastUpdateTime=2026-09-19 21:12:41`) postdates the last commit (`28ee970`). The
device is running code that exists only in the working tree, so "what is on the device" and "what is
in git" are currently different things.

---

## 5. `screenOrientation="portrait"` against a `sw692dp` inner display on Android 16

**Measured.** ColorOS reports the inner display as a *large* screen:

```
Display: mDisplayId=2 (organized)
  overrideConfig={... sw692dp w692dp h763dp 520dpi lrg widecg port ... mBounds=Rect(0,0-2248,2480)}
Display: mDisplayId=0 (organized)
  overrideConfig={... sw351dp w351dp h805dp 520dpi nrml long ... mBounds=Rect(0,0-1140,2616)}
```

Note `lrg` and `sw692dp` on the inner panel — above the 600dp large-screen threshold — against
`nrml`/`sw351dp` on the cover. The launcher pins itself to one orientation in two places:

```xml
android:screenOrientation="portrait"
```

```dart
// lib/main.dart
SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
```

**Why this is an Android 16 concern — now VERIFIED, not inferred.** Android 16's behavior-change
documentation for apps targeting API 36 states that orientation, resizability and aspect-ratio
restrictions **no longer apply on displays with smallest width ≥ 600dp**, and explicitly lists
`portrait` / `reversePortrait` / `sensorPortrait` / `userPortrait` among the values that are ignored.
The only opt-out is the temporary `PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY`, which is dead at
API 37. ([Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16))

Because the inner display is `sw692dp`, that threshold is crossed, so the manifest's
`android:screenOrientation="portrait"` **is being ignored on the inner display right now**. The cover
display (`sw351dp`) is below 600dp, so the portrait lock still holds there — which is why the bug is
easy to miss: the cover screen behaves as declared and only the inner screen ignores it. The
app-level `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` in `lib/main.dart`
is a second, redundant lock that also does not survive the threshold.

In other words, **this manifest relies on a forced portrait inner display and Android 16 has stopped
honouring that**. Any layout that assumes a tall narrow viewport on the inner screen is at risk.

**Correction to an earlier version of this section:** this was flagged as an unverified conformance
risk. It is confirmed behavior, and the density arithmetic is checkable directly — `dumpsys` reports
`sw692dp` for the 2248px inner panel, so the 600dp threshold is exceeded regardless of how the
effective density is derived. (`wm density` reports 520 for both panels while the reported `sw` values
imply a lower effective density; ColorOS is applying its own large-screen density handling.)

**[M]** ColorOS's own `FoldController` does not currently supply a usable posture either:

```
FoldController
  halfFoldSavedRotation=-1 mInHalfFoldTransition=false mFoldState=UNKNOWN
```

**[M]** The app compensates for the unreliable system posture signal by reading
`SensorManager.getDefaultSensor(36)` (the hinge angle sensor, on its own comment "TYPE_HINGE_ANGLE is
36") and mapping angle ranges to `folded` / `halfOpened` / `tabletop` / `flat`, with an aspect-ratio
fallback (`_coverAspectThreshold = 1.65`) and a default of `180.0` when the sensor never reports.

**Correction — the hinge sensor path is legitimate here, not a private hack.** This was initially
flagged as an "unversioned OEM contract". It is actually a *supported platform sensor*, and on this
device it is present, wake-up type, permission-free, and actively delivering events:

```
$ adb shell dumpsys sensorservice | grep -i hinge
0x0000016a) hinge_detect google hinge angle Wakeup | oplus | type: android.sensor.hinge_angle(36) | perm: n/a
0x00000660) hinge_detect fold state Wakeup        | oplus | type: qti.sensor.fold_state(33171063)
... google hinge angle Wakeup (handle=0x0000016a, connections=4)
```

`TYPE_HINGE_ANGLE` is public API since API 30, requires no permission, and `values[0]` is a 0–360°
angle. So the app's fold detection **does have a working sensor on this device**. Because the
framework's own fold state reads `UNKNOWN` here, this sensor is not a fallback — it is the primary
and probably only source of truth the app has. That makes it more important, not less, to degrade
gracefully: the sensor is optional (`PackageManager.FEATURE_SENSOR_HINGE_ANGLE`) and Google
explicitly warns that hinge ranges and accuracy vary per device and that precise-angle logic must be
tuned per device.

**[M] ColorOS's device states are well-formed, which makes `mFoldState=UNKNOWN` notable:**

```
$ adb shell cmd device_state print-states
  DeviceState{identifier=0, name='CLOSED',      app_accessible=true}
  DeviceState{identifier=1, name='TENT',        app_accessible=true}
  DeviceState{identifier=2, name='HALF_OPENED', app_accessible=true}
  DeviceState{identifier=3, name='OPENED',      app_accessible=true}
  DeviceState{identifier=102, name='SUB_SCREEN_ONLY_DEFAULT', app_accessible=true}
```

The device-state machinery works and even models a cover-screen-only state; it is specifically
ColorOS's `DisplayRotation.FoldController` mapping that reports `UNKNOWN`. Practical consequence:
`DeviceStateManager` is a viable, vendor-blessed way to observe posture on this device, and
`SUB_SCREEN_ONLY_DEFAULT` is the identifier that corresponds to the cover screen.

**Fix.** Drop `android:screenOrientation="portrait"`, stop pinning `setPreferredOrientations`, and
drive layout from the reported fold state / window size instead. Keep the hinge sensor (it works
here) but treat it as optional and degrade gracefully; consider `androidx.window`'s `FoldingFeature`
and `DeviceStateManager` as additional signals rather than replacing a sensor that is demonstrably
functional.

---

## 6. ColorOS applies Material You; the launcher hard-codes its palette

**Measured.** ColorOS 16 is actively doing dynamic colour theming on this device:

```
mMaterialColor= 5   mThemeChanged= 0   mDarkModeBackgroundMaxL= 0.0   mDarkModeForegroundMinL= 100.0
mUxIconConfig= 1e152714500021   mIconPackName=   mOplusConfigType= 1
```

**Read.** The launcher ignores all of it:

```dart
// lib/main.dart — fixed dark theme, no seed, no scheme
theme: ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: const Color(0xFF020306),
  fontFamily: 'Roboto',
),
```

A grep for `dynamic_color` / `DynamicColor` / `ColorScheme.fromSeed` across `lib/` returns nothing.
[?] The visual result is a surface that stays static while the system UI around it (keyguard,
notification shade, settings) re-themes — a mismatch rather than a crash, but a very visible one when
the launcher sits directly against system surfaces.

This is consistent with `reports/launcher-critique.md` §Features item 3 ("Wallpaper is suppressed and
there is no Material You dynamic color"), now confirmed against the live theme config.

---

## 7. A 1.8GB debug build is being lived in

**Measured.**

```
build/app/outputs/flutter-apk/app-debug.apk     1,796,022,367 bytes   (~1.8 GB)
```

with debug symbols deliberately retained and release signed by the debug key:

```kotlin
release { signingConfig = signingConfigs.getByName("debug") }
packaging { jniLibs { keepDebugSymbols.add("**/*.so") } }
```

and the process measured at **414MB RSS** (`lastRss=414MB`). **[M]** The device has no
battery-optimisation exemption for the app and its standby bucket is `10` (active), so nothing is
currently throttling it — but a ~415MB launcher on a device that also runs OPPO's 140MB+ stock
launcher, against the `PREVIOUS_APP_ADJ` retention described in §1, is a poor combination.

**[M]** The app also does not request battery-optimisation exemption anywhere (no
`REQUEST_IGNORE_BATTERY_OPTIMIZATION` in the manifest, and no matching call in `lib/`), so it has no
leverage if ColorOS later decides to restrict it.

**Fix.** Ship a release build: real signing, `minifyEnabled`/`shrinkResources`, no retained debug
symbols, and `flutter build apk --release --split-per-abi`. This also removes the oddity of a launcher
declaring `DEBUGGABLE` (the installed package flags confirm `DEBUGGABLE HAS_CODE`).

---

## 8. `INTERNET` is missing from the main manifest

**Read + measured.** The main manifest declares no `INTERNET`; only the debug and profile manifests
do:

```
android/app/src/main/AndroidManifest.xml      INTERNET: 0 matches   # [D]
android/app/src/debug/AndroidManifest.xml     INTERNET: present
android/app/src/profile/AndroidManifest.xml   INTERNET: present
```

**[M]** The merged *debug* manifest does contain it (so it works today), but a release build would
have no network. Since the search surface is designed to take an HTTP provider
(`FixtureSearchProvider` is wired in with a comment that registering an HTTP provider "is the only
change needed to make inline answers live"), a release build would break web search silently. This is
already noted in `docs/coloros16-launcher-research.md` §"Local traps" — it is still unfixed.

---

## 9. Missing launcher-feature surface that ColorOS expects

**[D]** The main manifest declares no `<provider>`, no `<service>`, no `<receiver>`, no backup agent,
and no adaptive icon. Against what a launcher on ColorOS 16 is surrounded by:

| Expected of a launcher | Present? | Note |
|---|---|---|
| `AppWidgetHost` | ✗ | no `APPWIDGET` binding anywhere; `reports/launcher-critique.md` item 1 |
| Notification badges | ✗ | `notificationCount` only ever set in `_generateMockApps()` |
| Wallpaper + dynamic colour | ✗ | `windowShowWallpaper=false`; §6 above |
| Backup/restore of layout | ✗ | no backup agent; galaxy config is device-local |
| FileProvider / share surface | ✗ | no provider at all |
| Adaptive icon | ✗ | `@mipmap/ic_launcher` only |
| `QUERY_ALL_PACKAGES` | ✓ | declared — works locally, but is a Play-policy review item |

**[M]** The stock launcher, by contrast, is wired for all of this (QuickStep services, keyguard
service, Breeno provider, fold overlay with badge dimensions). The gap is not a bug in the launcher so
much as a decision about whether it intends to be a daily driver — which is exactly the open question
`reports/launcher-critique.md` already poses.

---

## 10. Self-lock on backgrounding: friction without security

**[D]** The launcher locks itself whenever it is backgrounded, and the overlay is not gated on the
device actually being secure:

```dart
// lib/main.dart
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
    _lockForScreenOff();          // fires on plain backgrounding, not just screen-off
  }
}

void _lockForScreenOff() {
  if (!mounted) return;
  setState(() => _isLocked = true);   // no isDeviceSecure() check
}
```

**[M]** `LauncherBridge` still exposes `isDeviceSecure`, and
`reports/repro-fingerprint-unlock.md` §Green records that `_lockForScreenOff` was changed to consult
it ("`_lockForScreenOff` consults `LauncherBridge.isDeviceSecure()` first") — but that check is **not
in the current code**. Another case of a documented fix that the tree does not contain.

Practical effect: switching to any app from the launcher, then returning, raises the cosmic lock
screen even on an unsecured device, and on a secured one it adds a full auth step for something the
platform keyguard already covers — while (per §2) the app cannot own the sensor to make that step
silent.

---

## 11. Predictive back is force-enabled for targetSdk 36, and back is trapped

**Verified policy.** For apps targeting API 36 on Android 16, **predictive back animations are enabled
by default**, and the legacy path is gone: `onBackPressed` is not called and `KeyEvent.KEYCODE_BACK`
is no longer dispatched. ([Android 16 behavior changes](https://developer.android.com/about/versions/16/behavior-changes-16))

**Read — the app is one of the good cases, with one caveat.** Back is handled through the modern
mechanism, not the legacy one:

```dart
// lib/main.dart — modern API, so predictive back does NOT break this app
return PopScope(
  canPop: false,
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;
    if (_isSearchOpen) { setState(() => _isSearchOpen = false); }
    else { _camera.resetView(); }
  },
  ...
```

There is no `onBackPressed`, no `WillPopScope`, and no `onKeyDown` anywhere in `lib/` or `android/`
(verified by grep), so the app will not silently lose back handling the way a legacy app would. The
manifest does not declare `android:enableOnBackInvokedCallback`, which is fine — Flutter registers
through the modern API and declaration is not required.

**The caveat [D].** `canPop: false` is hard-coded with no branch that ever allows a pop, and neither
of the two branches (`_isSearchOpen`, `_camera.resetView()`) escalates to "leave the launcher" or
"open recents". So back is *intercepted unconditionally*: on the home surface, a back gesture resets
the camera view rather than deferring to the system. Whether that is intentional for a home screen is
a product decision — but combined with §3 (recents is owned by OPPO's QuickStep, not by this app) it
means **the launcher cannot both trap back and delegate recents**, because it does not own the
recents surface it would be delegating to. Worth verifying on the panel that back from the home
surface still gives the user a way to reach the app switcher.

---

## 12. The two-launcher HOME handoff on ColorOS 16

**This is the most likely source of a visible "clash", and it is not fixable from a non-root app.**

ColorOS 16 keeps the stock launcher in the HOME path even when a third-party launcher holds the role.
Reported behaviour on ColorOS 16.0.1 is that the stock launcher is still started/resumed on HOME,
producing roughly a second of bare wallpaper before the desktop appears; the only public fix is root
plus an LSPosed hook that finishes `com.android.launcher`'s activity immediately.
([home_launcher_redirect](https://github.com/xieincz/home_launcher_redirect))

That lines up with what is directly observable on this device **[M]**: OPPO's launcher is running,
enabled, and bound by SystemUI for both QuickStep and keyguard handling, and it ships the fold
resource overlay — see §3. Nothing in this repo's Android config prevents ColorOS from waking that
process on HOME.

**Hard constraint [V]: do not disable or freeze `com.android.launcher` to try to stop this.** Doing so
removes recents and the swipe-up home gesture entirely — *"Due to the freezing of the system launcher,
swipes for minimizing and showing running applications will not be available"*
([XDA](https://xdaforums.com/t/new-method-to-change-default-coloros-launcher.4663711/)). Recents on
ColorOS lives *inside* that package, and re-enabling it is the documented cure.

**Why this reframes §1.** AOSP itself protects the HOME role holder — `OomAdjuster.computeOomAdjLSP`
clamps any cached home process to `HOME_APP_ADJ` (600) with adjType `"home"`, which is below the 900
freezer cutoff. So pure AOSP neither demotes nor freezes a properly-registered home app. ChronoFold was
measured at **700 (`PREVIOUS_APP_ADJ`)**, i.e. *worse than AOSP's baseline for a home app*. That
strengthens the §1 conclusion: the app is being treated as an ordinary previous app rather than as the
home app, and any hostile behaviour on top of that comes from a vendor layer, not from AOSP.

**Vendor layers that exist on this device [M].** ColorOS 16 runs a closed freeze subsystem — OPPO's
"Hans" — in `system_server`:

```
$ adb shell getprop | grep -i hans
[init.svc.hans]: [running]
[sys.hans.enable]: [true]
[persist.vendor.enable.hans]: [true]
$ adb shell dumpsys activity | grep -E "freezer_cutoff_adj|use_freezer"
  freezer_cutoff_adj=900
  use_freezer=true
```

The `freezer_cutoff_adj=900` value matches AOSP's, so there is no evidence the *documented* threshold
was lowered. But third-party reverse-engineering of the Hans state machine indicates it is entered on
"app leaves foreground" rather than on `oom_adj`, so it can in principle act on processes AOSP's
cached-app freezer would spare. **[?]** Whether ColorOS exempts the default third-party launcher
(`isLcdOnNonRestrictPkg` / `isHansWhitelistApp`) is unverified — those are closed-source hooks. I found
no report of ColorOS OOM-killing the default third-party launcher for battery reasons; the community
complaints are about return-home latency, broken animations, default reversion and recents, not kills.

**Also [M]:** the app requests no battery-optimisation exemption and declares no foreground service, so
it has no standing against any of this. OPPO's own guidance requires four separate user actions
(Startup Manager, battery optimisation, pin to recents, background activity) before a third-party app
behaves reliably ([OPPO support](https://support.oppo.com/en/answer/?aid=neu1280) ·
[dontkillmyapp/oppo](https://dontkillmyapp.com/oppo)).

**No fix exists at the app layer for the handoff itself.** The honest options are: document the
one-second wallpaper flash as a known ColorOS behaviour, ask users to apply the OPPO battery
checklist, or drive the root/LSPosed route (out of scope for a store launcher).

---

## 13. 16KB page size: clean (verified)

**Measured on the on-disk artifact.** This was flagged as a risk in the first pass and is now
resolved:

```
$ zipalign -c -P 16 -v 4 build/app/outputs/flutter-apk/app-debug.apk
  lib/x86_64/libflutter.so (OK)
  ...
  Verification successful                                # [M] 16KB-aligned
```

The arm64/x86_64 `libflutter.so` PT_LOAD segments are aligned to 65536. The debug APK carries
`arm64-v8a`, `armeabi-v7a` and `x86_64` Flutter libraries.

Two caveats, neither urgent on this device:

- **[M]** The device's own page size is **4096** (`getconf PAGE_SIZE`), so 16KB alignment is not
  currently exercised here at all.
- **[?]** The RELRO-end criterion (`(vaddr + memsz) % 16384`) was computed as 4096 on the *debug*
  `libflutter.so` and should be re-checked on a **release** build. Flutter's standard release
  toolchain is expected to comply; Play requires 16KB support for apps targeting 15+ on 64-bit, and
  from Feb 1 2027 will reject updates that do not.

---

## Cross-cutting: what is actually causing the user-visible "clashes"

Ordered by how likely each is to be what a user notices:

1. **Returning home flashes bare wallpaper for ~1s, then the desktop loads** — §12. ColorOS wakes its
   own launcher on HOME regardless of who holds the role. Not fixable without root.
2. **Recents hard-cuts, home animations are missing, status bar can vanish** — §3. Recents is inside
   OPPO's launcher package.
3. **The launcher cold-starts when coming back from another app** — §1 (not registered as the home
   process, so AOSP's adj-600 protection never engages) and §7 (414MB, previous-app retention).
4. **Fingerprint / unlock behaves inconsistently** — §2 and §4. While locked the keyguard owns the
   sensor, so any app-owned silent reader is cancelled within ~2ms; only `BiometricPrompt` works.
5. **Back does nothing useful on the home surface** — §11; back is trapped by `PopScope(canPop: false)`
   with no exit branch.
6. **Layout/orientation oddities on the inner screen and in tabletop** — §5, with ColorOS's own
   `FoldController` reporting `UNKNOWN`.
7. **It looks like a foreign surface** — §6 (no Material You) and §9 (no adaptive icon / wallpaper).
8. **Jank and memory pressure** — §7, and `reports/perf-architecture.md`.

---

## Recommended sequence

**Cheap, high-confidence, do first**

1. Remove `android:taskAffinity=""` and confirm `mHomeProcess` becomes non-null (§1). One-line change,
   directly testable with `dumpsys`.
2. Decide the keyguard stance and delete the other one (§2/§4). Either drop `showWhenLocked` and let
   the platform own the lockscreen, or keep it and delete the silent-reader/custom-prompt path. Do not
   keep both. Then fix or delete `reports/repro-fingerprint-unlock.md` §Green.
3. Add `INTERNET` to the main manifest (§8).
4. Restore the `isDeviceSecure()` gate in `_lockForScreenOff` or stop locking on plain backgrounding
   (§10).
5. Build a signed release APK (§7).

**Structural**

6. Drop the portrait lock and `setPreferredOrientations`; adopt `androidx.window` fold APIs over raw
   sensor id 36 (§5).
7. Read ColorOS's dynamic colour and theme the launcher from it (§6).
8. Decide the daily-driver question: widgets, badges, backup, wallpaper (§9).

---

## Evidence index

| Claim | How to reproduce |
|---|---|
| role held, home process null | `adb shell cmd role get-role-holders android.app.role.HOME` · `adb shell dumpsys activity processes \| grep mHomeProcess` |
| OOM rung 700 not 600 | `adb shell dumpsys activity oom \| grep -A6 chronofold` |
| correct HOME intent filter | `adb shell dumpsys package com.launcher.chronofold.mylauncher \| grep -A5 "Activity Resolver Table"` |
| QuickStep/keyguard services | `adb shell dumpsys activity services com.android.launcher` |
| fold overlay targets stock launcher | `adb shell cmd overlay dump com.oplus.android.launcher.overlay.foldscreen` |
| inner display is `lrg`/`sw692dp`, fold state UNKNOWN | `adb shell dumpsys window displays \| grep -E "FoldController\|overrideConfig"` |
| dynamic colour active | `adb shell dumpsys window displays \| grep mMaterialColor` |
| OPPO biometric gate | `adb logcat -d \| grep -iE "OplusCustomizeRestrictionManager\|BiometricUtils"` |
| no INTERNET in main manifest | `grep -c INTERNET android/app/src/main/AndroidManifest.xml` |
| debug build size / signing | `ls -la build/app/outputs/flutter-apk/app-debug.apk` · `android/app/build.gradle.kts` |
| `showWhenLocked` never removed | `git log --oneline -S'showWhenLocked' -- android/app/src/main/AndroidManifest.xml` |
