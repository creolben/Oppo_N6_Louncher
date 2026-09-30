# ChronoFold lockscreen — session handoff / continuation spec

**Read this first if you are picking up the ChronoFold lockscreen work in a new session.**

Repo: `/home/creolben/Projects/Flutter Apps/Oppo_N6_Louncher`
Worktree: `.worktrees/fix-lock-screen` — branch **`fix/lockscreen-followups`**
Device: OPPO Find N6 `CPH2765`, adb serial `3B164U00HXG00000`

_State captured at the end of the 2026-09-29 session. Verify before trusting — see step 0._

---

## 0. First: find out what state you actually inherited

The previous session's agent runs are **not durable**. A run may have been killed mid-edit (this has
already happened once), leaving the tree in a state that looks plausible but does not compile.
Never assume the working tree is coherent — check:

```bash
cd "/home/creolben/Projects/Flutter Apps/Oppo_N6_Louncher/.worktrees/fix-lock-screen"
git branch --show-current          # expect fix/lockscreen-followups
git status --short                 # expect ~6 modified + 3 new test files
git --no-pager log --oneline -3    # expect e988e0f (PR #2 merge) at the merge base
```

Then the two checks that actually matter:

```bash
# 1. Does the Dart side analyze?
flutter analyze

# 2. Does the ANDROID side compile?  <-- flutter analyze CANNOT see Kotlin errors.
#    This is the check that was missed once already; a missing Kotlin function left
#    the branch unbuildable while `flutter analyze` stayed green.
flutter build apk --debug --target-platform android-arm64
```

If the build fails, read it rather than reverting: the previous interruption left
`getBatteryState()` *called but undefined* in `MainActivity.kt`. The current run has since
defined it, but the class of failure is "half-applied edit", so grep for the obvious:

```bash
grep -n "getBatteryState" android/app/src/main/kotlin/com/launcher/chronofold/mylauncher/MainActivity.kt
grep -rn "fun getBatteryState" android/    # a call with no definition = will not compile
```

---

## 1. What is already done and merged — do not redo

**PR #2** (`fix_lock_screen` → `main`, merge commit `e988e0f`) shipped and was verified on hardware:

- Lock-surface ownership single-sourced: `panel mounted ⟺ overlay enabled`, all four lock buttons
  route through `_mountLockPanel`.
- Cold start behind a locked keyguard no longer draws the home surface over it (security fix).
- Fingerprint: refuses to arm while the keyguard is locked; one platform prompt per intention
  instead of card → USE PIN → prompt. Measured 0 futile arms per wake, down from 2–6.
- Clocks follow the platform's 12/24-hour setting on all four surfaces.

Full analysis: `reports/lockscreen-native-handling-analysis.md` (in-repo, merged).
Device/signing/verification recipes: skill **`chronofold-device-build-install`** — load it.

## 2. What this branch adds — status

Branch `fix/lockscreen-followups`. Planned as F1–F5; the harness briefs are
`~/.dsh/runs/phase3-brief.md` (original) and `~/.dsh/runs/phase3-resume.md` (resume after a kill).

| # | Item | Status at handoff |
|---|---|---|
| F1 | Cold boot: panel must not linger over an unlocked device | native half in (onCreate records `keyguardWasLocked`); Dart self-heal (reconcile on lifecycle `resumed`) — **verify it landed** |
| F2 | Delete dead `initialAuthenticated` field | expected done |
| F3 | Real battery instead of hardcoded `92%` | native `getBatteryState()` + Dart wiring + `test/lockscreen_battery_test.dart` — **verify it built** |
| F4 | `listening` only after the platform really reads the sensor | native in (`startFingerprintScan` returns Boolean); Dart armed-state must come from that return value |
| F5 | `isDeviceSecure` capability; no fingerprint pretence on a non-secure device | native in; Dart seam + `test/lockscreen_device_secure_test.dart` |

New test files expected: `test/lockscreen_battery_test.dart`,
`test/lockscreen_device_secure_test.dart`, `test/lockscreen_reconcile_test.dart`.
Baseline before this branch: **122 tests pass**, `flutter analyze` clean.

### F5 product decision (settled — do not "fix" it back)

The old behaviour *skipped* mounting the lock panel on a device with no secure lock. That is
**not** to be reinstated. Full ownership is the settled decision: **the panel always mounts**;
`isDeviceSecure` is only used to stop the panel pretending there is a fingerprint to read
(skip arming, render the affordance as a plain dismiss).

## 3. Open question — measure before changing anything

The user's complaint included "when I have an app running on the lock screen, the launcher is not
handling". Screen-off **while an app the launcher itself launched owns the screen** deliberately
delegates to the platform: see the `foreignTaskOwnsScreen` branch in `MainActivity.kt`'s
`ACTION_SCREEN_OFF` handler.

**Why it is deliberate** (measured, do not remove without reading):
`ChronoFold: Screen off while a launched app owns the screen; leaving the lock to the platform keyguard`

Historically, reporting that screen-off mounted the panel and re-asserted `showWhenLocked` on a
paused activity, so returning from the app landed on a keyguard-occluding launcher that asked for a
fingerprint.

**Measured behaviour on the CPH2765:** lock-from-the-launcher's-own-surface correctly shows the
cosmic panel (fixed in PR #2). The foreign-app case was **not** successfully driven end-to-end — the
launcher's `foreignTaskOwnsScreen` latch is only set by the launcher's own *handoff*, so the app
must be opened by tapping its icon in the launcher UI; `adb shell am start` does NOT reproduce it.
A scripted tap also needs the accessibility tree for coordinates, and the device must be **unlocked**
first (its panel occludes the app grid, so the tree lists both surfaces at once).

Reproduce properly: unlock the phone, `uiautomator dump` to find the icon's bounds, tap it, confirm
`topResumedActivity` is the app (not the launcher), then `KEYCODE_SLEEP` → `KEYCODE_WAKEUP`.

## 4. Verification recipes

```bash
# Full gate
flutter analyze && flutter test && flutter build apk --debug --target-platform android-arm64

# Install without losing the user's layout (the Mac debug keystore must be at ~/.android/debug.keystore;
# signer must be 9357b2…  — see the chronofold-device-build-install skill)
adb -s 3B164U00HXG00000 install -r build/app/outputs/flutter-apk/app-debug.apk

# On-device probes
adb -s 3B164U00HXG00000 shell "dumpsys window | grep -m1 mKeyguardOccluded"   # true => launcher over keyguard
adb -s 3B164U00HXG00000 shell "dumpsys trust | grep -m1 trustState"           # deviceLocked=1 => really locked
adb -s 3B164U00HXG00000 logcat -d | grep -E "CF_LOCK|CF_FP"
```

Logcat markers to watch: `CF_LOCK: cold start with keyguard locked; mounting lock surface`,
`CF_LOCK: panel reconciled away; keyguard already unlocked`, `CF_FP: reader refused while keyguard
locked`, `ChronoFold: Screen off while a launched app owns the screen`.

## 5. Working method (the user's standing instruction)

All coding in this repo goes through **DeepSeek Harness**, not direct edits:

```bash
cd "/home/creolben/Projects/Flutter Apps/Oppo_N6_Louncher/.worktrees/fix-lock-screen"
cat <brief>.md | dsh --profile headless --patch ~/.dsh/runs/glm53.yml --json - > out.ndjson 2> out.err
```

**Known constraint:** the harness sandbox cannot run Flutter or the Android toolchain
(read-only SDK caches) — it edits files only. **The orchestrator (you) must run
`flutter analyze` / `flutter test` / `flutter build apk`.** Treat the harness's claims as
unverified until you have.

**Known failure mode:** the route dies with `RATE_LIMIT: 429 … session usage limit`
(the ollama-cloud account). A killed run leaves a half-applied edit — always re-run the gates.
A working alternative now exists: a **Kiro** provider (see below) exposing Claude models.

## 6. Unrelated but already set up in that session: Kiro models in Hermes

Complete and verified — nothing to do, recorded here so it is not re-derived.

- `kiro-cli` installed (`~/.local/bin`), logged in with Google. Credentials:
  `~/.local/share/kiro-cli/data.sqlite3`.
- Gateway container `kiro-gateway` (`~/kiro-gateway`, `compose.hermes.yml`), loopback-only,
  `restart: unless-stopped`. Health: `curl -s http://127.0.0.1:8000/health`.
- Hermes: provider row **`custom:kiro`** (17 verified models) + aliases
  `kiro`, `kiro-opus` (claude-opus-5.5), `kiro-sonnet` (claude-sonnet-5), `kiro-glm`, `kiro-auto`.
- **`claude-sonnet-5.5` is refused by the Kiro account** ("Invalid model ID or insufficient
  subscription level"). opus 5.5 works. The gateway's advertised `/v1/models` list is unreliable in
  both directions — probe a model before listing it.
- The custom-provider entry needs **`discover_models: false`**, or the picker probe silently
  rewrites the curated model list (it will re-add the dead `auto-kiro` id).

Detail and the full set of traps: skill **`hermes-kiro-provider`**.

## 7. Gotchas worth not rediscovering

- **`flutter analyze` does not compile Kotlin.** Dart-clean can still mean an unbuildable app.
- **`launcherResumed` is false at SCREEN_OFF even when the launcher is the visible top activity** —
  `onPause` precedes the broadcast. Any gate built on it silently drops lock-from-home and exposes
  the home screen over a locked device. (This exact mistake shipped and had to be reverted.)
- **A locked keyguard refuses app-owned fingerprint sessions** (cancelled in 1–6 ms) and occluding
  the keyguard disables the system biometric path. Only the platform's own prompt can read the
  sensor while locked.
- **The platform's auth dialog is a secure `KEYGUARD_DIALOG`** — screenshots of it come back
  all-black.
- Configuration is changed with `hermes config set` — never by hand-editing `config.yaml`.
