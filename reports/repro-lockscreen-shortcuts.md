# repro — lock-screen Phone and Camera buttons open the wrong app

- Layer: unit + widget (Flutter), root cause confirmed against the real device
- Repro command: `flutter test test/lockscreen_shortcuts_test.dart` (cwd: `/Users/benjerome/Documents/Dev/mylauncher`)
- Device under test: OPPO Find N6 `CPH2765`, ColorOS 16 / Android 16

## Summary

The two shortcut circles at the bottom of `CosmicLockScreen` passed a
hard-coded package name to `_launchQuickApp`, which fell back to
`widget.apps.first` whenever the name did not match:

```dart
// lib/features/lockscreen/cosmic_lock_screen.dart (before)
onTap: () => _launchQuickApp('com.android.phone'),
onTap: () => _launchQuickApp('com.android.camera'),

Future<void> _launchQuickApp(String packageName) async {
  if (widget.apps.isEmpty) return;
  final app = widget.apps.firstWhere(
    (a) => a.packageName == packageName,
    orElse: () => widget.apps.first,   // <- launches an arbitrary app
  );
  await _unlockAndLaunchApp(app);
}
```

Neither constant matches anything launchable on the tested device, so **both**
buttons resolved to the same arbitrary app — the first entry in the list.

## Device ground truth

`getInstalledApps` queries `Intent.CATEGORY_LAUNCHER`, so the list holds
launchable activities only.

```
$ adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.android.phone
No activity found

$ adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.android.camera
No activity found

$ adb shell cmd package resolve-activity --brief -c android.intent.category.LAUNCHER com.oplus.camera
priority=0 preferredOrder=0 match=0x108000 specificIndex=-1 isDefault=true
com.oplus.camera/.Camera

$ adb shell monkey -p com.android.phone -c android.intent.category.LAUNCHER 1
** No activities found to run, monkey aborted.
```

- `com.android.phone` is **installed but not launchable** (it is the telephony
  service package). `getLaunchIntentForPackage` returns null for it, so even a
  correct name match would have launched nothing.
- `com.android.camera` is **not installed at all**.

The real components:

```
$ adb shell cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER
    com.android.contacts/.DialtactsActivityAlias      (label "Phone")
    com.android.contacts/.PeopleActivityAlias         (label "Contacts")
    com.oplus.camera/.Camera                          (label "Camera")
```

`com.android.contacts` publishes **two** launcher aliases, so the package name
alone cannot identify the dialer; only the activity name can. The manifest
confirms `.DialtactsActivityAlias` is the component registered for
`ACTION_DIAL`.

## RED (before the fix)

Test fixture is the device's real app list, with `com.android.chrome` first to
stand in for an arbitrary `apps.first`:

```
$ flutter test test/lockscreen_shortcuts_test.dart
00:00 +0: Lock screen quick shortcuts Phone shortcut opens the dialer on a real device app list
Expected: 'com.android.contacts'
  Actual: 'com.android.chrome'
   Which: is different.
          Expected: ... .android.contacts
            Actual: ... .android.chrome
                                  ^
           Differ at offset 13

00:00 +0: Lock screen quick shortcuts Camera shortcut opens the camera on a real device app list
Expected: 'com.oplus.camera'
  Actual: 'com.android.chrome'
   Which: is different.
          Expected: com.oplus.came ...
            Actual: com.android.ch ...
                        ^

00:00 +0: Lock screen quick shortcuts A shortcut never falls back to an unrelated app
Expected: not 'Chrome'
  Actual: 'Chrome'

00:00 +0 -3: Some tests failed.
```

Both buttons opened Chrome. Note the pre-existing test
`lockscreen_physics_test.dart › Tapping quick phone shortcut invokes unlock and
launches app` passed throughout: its fixture contains exactly one app, named
`com.android.phone`, so `firstWhere` always matched the constant the test was
built around and the `orElse` branch was never reached.

## GREEN (after the fix)

```
$ flutter test test/lockscreen_shortcuts_test.dart
00:00 +10: All tests passed!

$ flutter test
00:02 +71: All tests passed!

$ flutter analyze lib test
No issues found! (ran in 2.8s)
```

## On-device verification (CPH2765, ColorOS 16)

`flutter build apk --debug` → `adb install -r`, then the lock screen was raised
by cycling the panel and each shortcut tapped on the real panel. `_openQuickShortcut`
logs the role it resolved, which is the observable that was broken:

```
$ adb logcat -d | grep "Quick shortcut"
I flutter : Quick shortcut phone: Phone (com.android.contacts/com.android.contacts.DialtactsActivityAlias)
I flutter : Quick shortcut camera: Camera (com.oplus.camera/com.oplus.camera.Camera)
```

Both buttons now resolve to the real apps. Before the fix the same tap resolved
to `widget.apps.first` — Chrome — for both.

The two resolved components were then started directly (the same explicit
`setClassName` call `LauncherBridge.launchApp` makes) and each became the
resumed activity:

```
$ adb shell am start -n com.android.contacts/com.android.contacts.DialtactsActivityAlias
  ResumedActivity: ActivityRecord{... com.android.contacts/.DialtactsActivityAlias t1117}

$ adb shell am start -n com.oplus.camera/com.oplus.camera.Camera
  ResumedActivity: ActivityRecord{... com.oplus.camera/.Camera t1452}
```

Screenshots: `.agent-shots/shortcuts/`.

## Follow-up: two defects the device exposed after the buttons worked

Once the shortcuts opened the right apps, two further faults showed up on the
real panel. Both were in the same unlock path.

### 1. The ColorOS keyguard flashed during the handoff

The panel is the only cover over the ColorOS keyguard, and the old order was:

```
authenticate → slide the panel away → dismiss keyguard → start the app
               ^ cover gone here, keyguard still up
```

Reproduced at OS level: with the keyguard up, starting the dialer made it the
resumed activity while the keyguard kept focus, so the screen still showed the
lock screen.

```
$ adb shell am start -n com.android.contacts/com.android.contacts.DialtactsActivityAlias
  ResumedActivity: ActivityRecord{... com.android.contacts/.DialtactsActivityAlias t1454}
  mFocusedWindow=Window{... NotificationShade}     <- keyguard on top
```

`wm dismiss-keyguard` is refused on a secure device, so only the app can ask.
`launchApplication` is now callback-based and `startWhenUnlocked()` reports
success from inside `onDismissSucceeded`, so Dart learns the app started only
after the keyguard is genuinely gone, and the panel stays up for the handoff.

### 2. Closing the launched app did not return to the lock screen

`_unlock()` cleared the panel on the way to launching, so closing the dialer or
camera dropped the user *behind* the panel — onto the launcher or onto whatever
the system had been covering — instead of back onto the lock screen.

Fixed by leaving the panel up for an app launch: the app opens, and closing it
returns here, which is what a lock-screen shortcut should do. `onUnlock` is now
only reached by the plain unlock paths (swipe up, sensor, platform
`userPresent`). Because the panel survives the trip, `didChangeAppLifecycleState`
resets the lock session on resume so the returned panel is live again and the
reader is re-armed.

Observed behaviour change, asserted by test:

```
Opening an app from the lock screen keeps the panel up, so closing the app
returns to the lock screen
  Expected: false
    Actual: <true>          <- the panel had been cleared
```

The pre-existing test `lockscreen_physics_test.dart › Tapping quick phone
shortcut invokes unlock and launches app` asserted `onUnlock` *was* called and
so encoded defect 2. It now asserts the app launched and the panel stayed up.

`flutter test`: 76 passed. `flutter analyze lib test`: no issues.

## Files changed
- `lib/features/lockscreen/quick_shortcut_resolver.dart` — new. Resolves the
  phone/camera role from the installed app list by scoring activity name,
  package name and label; scores decoys (`phonemanager`, `paybyphone`,
  `cameraextensions`) as disqualifying; returns `null` rather than a wrong app.
- `lib/models/quick_shortcut.dart` — new. The `QuickShortcut` role enum, in
  `models/` so `lib/core` need not depend on `lib/features`.
- `lib/features/lockscreen/cosmic_lock_screen.dart` — buttons call
  `_openQuickShortcut`, which resolves by role, falls back to the platform
  handler, and reports honestly instead of going dead.
- `lib/core/launcher_bridge.dart` — `openQuickShortcut`, false when no
  unambiguous platform handler exists.
- `android/.../MainActivity.kt` — `openQuickShortcut`: `ACTION_DIAL` for the
  dialer (resolves to a single activity), `INTENT_ACTION_STILL_IMAGE_CAMERA_SECURE`
  for the camera, refused when it resolves only to a chooser.
- `android/app/src/main/AndroidManifest.xml` — `<queries>` for `DIAL` and
  `STILL_IMAGE_CAMERA_SECURE`; without them `resolveActivity` returns null
  under Android 11+ package-visibility filtering.
- `test/lockscreen_shortcuts_test.dart` — new. 7 resolver unit tests plus 5
  widget tests driving the real buttons, the auth race, and the return path.
- `android/.../MainActivity.kt` — `startWhenUnlocked`/`startActivityQuietly`;
  `launchApplication` is callback-based and only reports success once the
  keyguard has gone and the activity has started.
- `test/lockscreen_physics_test.dart` — the quick-shortcut test now asserts the
  panel stays up rather than being cleared on launch.

## Residual uncertainty

- **Biometric auth is unchanged.** Tapping either shortcut still runs
  `LauncherBridge.authenticate` before unlocking and launching, so the shortcut
  is not usable without authenticating. That is pre-existing behaviour, not part
  of this fix; a stock Android lock screen opens the dialer and camera without
  unlocking. Whether these two shortcuts should bypass auth is a product
  decision that was left alone.
- The widget tests observe the launch target through the bridge's non-Android
  `debugPrint` path; they do not exercise the real `MethodChannel`.
- The camera fallback is deliberately refused when the platform resolves it to
  a chooser. On `CPH2765` `STILL_IMAGE_CAMERA_SECURE` is claimed by both
  `com.oplus.camera` and `com.snapchat.android`, so the fallback returns false
  there and the app-list resolution is what answers the button.
- The camera shortcut cannot be opened over the system keyguard by a plain
  activity launch; only `INTENT_ACTION_STILL_IMAGE_CAMERA_SECURE` is exempt, and
  it is ambiguous on this device. The shortcut therefore unlocks first (after
  auth) rather than shooting from the lock screen the way a stock lock screen
  does.
- **The keyguard-flash fix and the return-to-lock-screen fix are verified by
  tests, not yet on the panel.** `screenrecord` is refused on this ColorOS build
  (both file and h264-stream output), and completing the biometric prompt needs
  a real finger, so the on-device step is still outstanding for those two.
- `developers.oppomobile.com` holds no launcher/keyguard documentation. Its
  entire doc set was enumerated through its JSON endpoint
  (`/wiki/index/detail?id=N`): 32 documents, all account, publishing and review
  paperwork, plus one generic Android P adaptation note. There is no OPPO API to
  make the ColorOS keyguard behave, so the standard Android route
  (`requestDismissKeyguard`) is the only supported one.
