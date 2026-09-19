# Adversarial review — c48b85e

- **Target:** working tree at base `536bc80`, committed as `3091fe6` + `c48b85e`
- **Diff:** `/tmp/review/diff.patch` (packet); intent in `/tmp/review/intent.md`
- **Reviewers:** two independent subagents with no access to the build conversation
  (Reviewer A: falsification; Reviewer B: secrets/privacy, a11y, performance,
  error paths, dependencies)
- **Environment limit:** the reviewers could not run `flutter test` (sandbox denies
  Flutter's own cache writes), so their layout and leak claims are analytic.
  All gates below were re-run by the author afterwards.

## Blocking findings and disposition

### 1. False unlock via `ACTION_USER_PRESENT` — FIXED, and worse than reported
Reviewer A (BLOCKING 3) and Reviewer B (§1) independently flagged that
`_onUserPresent` cleared the overlay on any keyguard dismissal, and that
`launcher_bridge.dart` documented it as a trustworthy biometric signal.

Both were right, and the behaviour was not hypothetical. Reproduced on the
CPH2765: lock the overlay, `KEYCODE_SLEEP`, `KEYCODE_WAKEUP` — logcat:

```
12:21:33.588 I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
12:21:34.692 I/flutter: Device unlocked by the platform; clearing the lock overlay
```

A bare screen wake cleared the launcher lock with no finger on the reader.
**Fix:** the `USER_PRESENT` path is removed entirely (Dart listener, bridge
method, native broadcast action). Unlock now requires a real match event from
the app's own reader session.

Re-verified after the fix — lock, sleep, wake:
```
12:25:32 I/flutter: Fingerprint sensor stopped: 5 Fingerprint operation canceled
(no unlock; lock screen still showing)
```
and a genuine touch:
```
12:25:53.678 I/flutter: Fingerprint matched: unlocking
```
Cover view rendered. Screenshots: `.agent-shots/polish/13-lock-final.png`.

### 2. Dead reader presented as armed — FIXED
Both reviewers (A BLOCKING 1, B §4). On error the code set `listening` while
the native session was already dead, with no re-arm on that branch, so the
affordance advertised a reader the app did not hold.

**Fix:** a terminal error re-arms at most `_maxFingerprintRearms` (2) times,
then reports `unavailable`; the retry budget resets on a deliberate arm
(mount or resume) so a spent budget cannot mark a working reader unavailable —
a defect the author found while re-verifying.

### 3. Re-subscribe race cancelling the live session — FIXED
Reviewer A (BLOCKING 2), Reviewer B (§4 re-entrancy). `_armFingerprintSensor`
is async and was invoked from both `initState` and `resumed`; the native
`onCancel` of the loser calls `stopFingerprintScan()`, disarming the winner,
while Dart still showed `listening`. This is the real origin of the
`Fingerprint sensor stopped: 5` bursts: the app was cancelling itself.

**Fix:** an `_armingFingerprint` in-flight guard, and the old subscription is
detached before the new session is armed. `Fingerprint matched: unlocking`
appears repeatedly in logcat after this fix, where before every session died
within 700 ms.

### 4. Unbounded animation-listener leak — FIXED
Reviewer B (§3, blocking). `CurvedAnimation(parent: _shake, …)` was constructed
inside `build()`, and `_FingerprintIndicator` rebuilds with the physics loop at
up to 120 Hz, so status listeners accumulated for the life of the overlay.

**Fix:** the `TweenSequence`/`CurvedAnimation` pair is now a `late final` field.

### 5. Diff does not compile standalone — NOT APPLICABLE
Reviewer B (§5, blocking) correctly found that
`lib/ui/widgets/foldable_simulation_chip.dart` is imported but untracked. That
was an artifact of the review packet (only one new file was `git add -N`'d),
not of the change: the file is committed in `3091fe6`, before the commit that
imports it. `flutter analyze` on the committed tree: clean.

## Non-blocking findings and disposition

| Finding | Disposition |
|---|---|
| Indicator `Semantics` label duplicated the descendant text and never announced status | FIXED — explicit label/hint dropped, `container` + `liveRegion` added |
| Quick-shortcut circles crash on empty `widget.apps` (`orElse: () => first`) | FIXED — early return; pre-existing, reachable on the first frames |
| Lock-screen clock repainted every second for an HH:mm display | FIXED — repaints on minute rollover, matching the cover screen |
| `_SensorPulsePainter.paint` allocated a `Paint` per frame at 120 Hz | FIXED — reused static `Paint` |
| `_CoverAppTile` long-press unreachable under a screen reader | FIXED — `Semantics.onLongPress`, anchored on the tile |
| Empty-state icon contrast 2.72:1 (<3:1 graphical floor) | FIXED — white 32% → 45% |
| Lock-screen chips 38dp, 6dp apart (<48dp / 8dp guidance); cover chips 40dp | PARTLY FIXED — 44dp and 8dp spacing, consistent with `CoverStyle.touchTarget`; still under the 48dp Material target, accepted for a dense custom launcher |
| `fingerprintEvents` never nulled in `onDestroy` | FIXED |
| `USE_FINGERPRINT` deprecated / `FingerprintManager` with a null `CryptoObject` | ACCEPTED — the old API is the only one without a system dialog; no key binding means it cannot dismiss the platform keyguard, and `_unlock()` only clears an in-app overlay, so no lock is weakened |
| 2-arg `registerReceiver` is safe only because all filter actions are protected | ACCEPTED — documented; adding any non-protected action to that filter would throw on API 34+ |

## What the reviewers could not break

Reviewer A enumerated the grid arithmetic (`_columnsFor` + tile widths across
288–448dp, counts 1–200, dpr 1.0–3.5), zero/one/huge app counts, the
`_SectorCrossFade` and `FadingHorizontalScroll` post-frame convergence,
`setState`-after-dispose, the `CancellationSignal` identity guard in both
orderings, and lock-cluster layout at 320dp with font scale 1.3 — no
overflow, no divide-by-zero, no orphan row, no use-after-dispose. Reviewer B
scanned the diff for secrets (none; only `com.test.secret` fixtures), verified
`ACTION_USER_PRESENT` is a protected broadcast that third-party apps cannot
forge, and confirmed no dependency or minSdk drift.

## Gates run after all fixes

- `flutter analyze` (lib + test): No issues found
- `flutter test`: 33/33 pass
- Device: CPH2765, folded, cover display — lock survives sleep/wake;
  fingerprint match unlocks; screenshots `.agent-shots/polish/08-cover-final.png`,
  `11-lock-ready.png`, `13-lock-final.png`
- The Impeccable design detector returns `[]` on the three UI files; it has no
  Dart support, so it is not evidence about this change and is not claimed as such.

## Remaining known limitation

On this ColorOS build the app's reader session is sometimes cancelled
(`Fingerprint sensor stopped: 5`) and recovers through the bounded re-arm. If a
future build refuses third-party silent reads outright, the lock screen will
show `FINGERPRINT UNAVAILABLE` and swipe-up remains the way in. There is no
Android API that both proves a fingerprint matched and draws no UI, so this is
the honest ceiling rather than a bug to fix later.
