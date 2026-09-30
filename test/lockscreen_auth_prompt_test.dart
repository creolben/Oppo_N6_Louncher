import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/lockscreen/fingerprint_prompt.dart';
import 'package:mylauncher/models/app_entry.dart';

/// The lock screen's own fingerprint prompt.
///
/// The platform's `BiometricPrompt` is a system dialog that cannot be styled,
/// so the panel draws its own and reads the silent `FingerprintManager` session
/// instead. These tests drive that session directly, because the point of the
/// change is that the panel — not the platform — owns the moment between a tap
/// and a launch.

/// Records what [LauncherBridge.launchApp] was asked to open.
///
/// On a non-Android host the bridge short-circuits to a debugPrint, so the
/// printed line is the observable record of the launch target.
class _LaunchSpy {
  final List<String> lines = [];
  late void Function(String? message, {int? wrapWidth}) _original;

  Future<void> capture(Future<void> Function() body) async {
    _original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) lines.add(message);
    };
    try {
      await body();
    } finally {
      debugPrint = _original;
    }
  }

  List<String> get launchedPackages => [
    for (final line in lines)
      if (line.startsWith('Simulating launching app:'))
        RegExp(r'\(([^()]*)\)$').firstMatch(line)?.group(1) ?? '',
  ];
}

List<AppEntry> _apps() => [
  AppEntry(
    packageName: 'com.test.camera',
    activityName: 'com.test.camera.Camera',
    label: 'Camera',
    category: AppCategory.core,
    accentColor: Colors.amber,
    fallbackIcon: Icons.camera_alt_rounded,
  ),
  AppEntry(
    packageName: 'com.test.notes',
    label: 'Notes',
    category: AppCategory.tools,
    accentColor: Colors.teal,
    fallbackIcon: Icons.edit_note_rounded,
  ),
  AppEntry(
    packageName: 'com.test.chat',
    label: 'Chat',
    category: AppCategory.social,
    accentColor: Colors.pink,
    fallbackIcon: Icons.chat_bubble_rounded,
  ),
];

/// A fingerprint reader that can be driven from a test.
class _FakeReader {
  _FakeReader({this.ready = true});

  /// False models a device with no reader, or one with nothing enrolled.
  final bool ready;

  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  Future<FingerprintCapability> capability() async =>
      FingerprintCapability(hardware: ready, enrolled: ready);

  Stream<Map<String, dynamic>> events() => _events.stream;

  void emit(Map<String, dynamic> event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> close() => _events.close();
}

Future<void> _pumpLockScreen(
  WidgetTester tester, {
  required _FakeReader reader,
  Future<bool> Function()? startFingerprintScan,
  Future<bool> Function({String? appName})? authenticate,
  Future<bool> Function({String? appName})? authenticateWithCredential,
  VoidCallback? onUnlock,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CosmicLockScreen(
          foldable: FoldableController(),
          apps: _apps(),
          onUnlock: onUnlock ?? () {},
          authenticate: authenticate,
          fingerprintCapability: reader.capability,
          fingerprintEvents: reader.events,
          startFingerprintScan: startFingerprintScan,
          authenticateWithCredential: authenticateWithCredential,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 16));
}

/// Advances the panel far enough for the reader's awaits to land.
Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Activates an app bubble the way a finger on the canvas would, through the
/// semantics node the panel publishes for it.
Future<void> _tapBubble(WidgetTester tester, String label) async {
  final node = tester.getSemantics(find.bySemanticsLabel(label));
  tester.binding.pipelineOwner.semanticsOwner!.performAction(
    node.id,
    SemanticsAction.tap,
  );
  await _settle(tester);
}

/// Sensor activity on a live session — the honest `listening`, a partial read.
/// The card promotion it carries is the safety net for requests that raced the
/// arm; armed state itself comes from the scan-start answer now.
Future<void> _handOverReader(WidgetTester tester, _FakeReader reader) async {
  reader.emit({'type': 'listening'});
  await _settle(tester);
}

/// Advances past the prompt's verified beat and the queued launch.
Future<void> _settleLaunch(WidgetTester tester) async {
  for (int i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

/// Finds the node a screen reader would actually land on, by walking the
/// semantics tree rather than the widget tree.
SemanticsNode? _nodeLabelled(WidgetTester tester, String label) {
  SemanticsNode? found;
  void visit(SemanticsNode node) {
    if (found != null) return;
    if (node.getSemanticsData().label == label) {
      found = node;
      return;
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  if (root != null) visit(root);
  return found;
}

void main() {
  late _FakeReader reader;
  late _LaunchSpy spy;

  setUp(() {
    reader = _FakeReader();
    spy = _LaunchSpy();
  });

  tearDown(() async {
    await reader.close();
  });

  group('Lock screen fingerprint prompt', () {
    testWidgets("tapping an app bubble raises the panel's own prompt", (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester, reader: reader);

      await _tapBubble(tester, 'Camera');
      await _handOverReader(tester, reader);

      // The element asking for the fingerprint is drawn by the launcher, not
      // raised by the platform: no system dialog can appear here.
      expect(find.byType(FingerprintAuthPrompt), findsOneWidget);
      expect(find.byIcon(Icons.fingerprint_rounded), findsOneWidget);
      expect(find.text('FINGERPRINT REQUIRED'), findsOneWidget);
      // It names the app, so the prompt says what the finger is unlocking.
      expect(
        find.descendant(
          of: find.byType(FingerprintAuthPrompt),
          matching: find.text('Camera'),
        ),
        findsOneWidget,
      );

      semantics.dispose();
      await _settle(tester);
    });

    testWidgets('a sensor match opens the app the user tapped', (tester) async {
      final semantics = tester.ensureSemantics();
      var unlocked = false;
      await _pumpLockScreen(
        tester,
        reader: reader,
        onUnlock: () => unlocked = true,
      );

      await spy.capture(() async {
        await _tapBubble(tester, 'Notes');
        await _handOverReader(tester, reader);
        reader.emit({'type': 'succeeded'});
        await _settleLaunch(tester);
      });

      expect(spy.launchedPackages, equals(['com.test.notes']));
      // A successful launch dismisses the custom overlay so closing the app
      // returns to the cover or home content rather than recreating the
      // fingerprint surface.
      expect(unlocked, isTrue);
      expect(find.byType(FingerprintAuthPrompt), findsNothing);

      semantics.dispose();
    });

    testWidgets('a live reader is reused rather than re-armed on a tap', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // Armed state is now "a scan was started and no terminal event has
      // arrived": the scan-start answer sets it, not the arrival of
      // `listening` — which on device means "sensor activity seen" and may
      // never arrive at all, since a clean first touch answers `succeeded`
      // with no help event. The scan seam is how a test says "the platform
      // accepted the session", and its call count is what proves a tap
      // reuses the live session instead of re-arming it.
      var starts = 0;
      await _pumpLockScreen(
        tester,
        reader: reader,
        startFingerprintScan: () async {
          starts++;
          return true;
        },
      );

      // The reader arms as the panel appears, exactly as it does on device
      // (through the device-secure answer, which a secure host answers
      // immediately).
      await _settle(tester);
      expect(starts, equals(1));
      // Sensor activity on the live session — the honest `listening`. Armed
      // state does not depend on it; the emit exercises the event path.
      reader.emit({'type': 'listening'});
      await _settle(tester);

      // No second start: the tap has to use the session that is already
      // live. Re-arming it is what lost the reader on the tested device — the
      // framework tears the running session down, and ColorOS refuses the
      // replacement instead of taking it over.
      await _tapBubble(tester, 'Camera');
      expect(starts, equals(1));
      expect(find.byType(FingerprintAuthPrompt), findsOneWidget);

      await spy.capture(() async {
        reader.emit({'type': 'succeeded'});
        await _settleLaunch(tester);
      });
      expect(spy.launchedPackages, equals(['com.test.camera']));

      semantics.dispose();
    });

    testWidgets('cancelling launches nothing and leaves the panel locked', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var unlocked = false;
      await _pumpLockScreen(
        tester,
        reader: reader,
        onUnlock: () => unlocked = true,
      );

      await spy.capture(() async {
        await _tapBubble(tester, 'Camera');
        await _handOverReader(tester, reader);
        await tester.tap(find.text('CANCEL'));
        await _settleLaunch(tester);
      });

      expect(spy.launchedPackages, isEmpty);
      expect(unlocked, isFalse);
      expect(find.byType(FingerprintAuthPrompt), findsNothing);
      expect(find.text('AUTH REQUIRED TO LAUNCH CAMERA'), findsOneWidget);

      semantics.dispose();
      await _settle(tester);
    });

    testWidgets('a non-matching finger keeps the prompt and stays armed', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester, reader: reader);

      await _tapBubble(tester, 'Camera');
      await _handOverReader(tester, reader);
      reader.emit({'type': 'failed'});
      await _settle(tester);

      expect(find.byType(FingerprintAuthPrompt), findsOneWidget);
      expect(find.text('NOT RECOGNISED • TOUCH AGAIN'), findsOneWidget);
      // The finger itself is the problem now, so the credential route is
      // offered. (Relabelled UNLOCK — it defers to the platform bouncer.)
      expect(find.text('UNLOCK'), findsOneWidget);

      // A later good read still opens the app: the prompt never went dead.
      await spy.capture(() async {
        reader.emit({'type': 'succeeded'});
        await _settleLaunch(tester);
      });
      expect(spy.launchedPackages, equals(['com.test.camera']));

      semantics.dispose();
    });

    testWidgets('a refused reader asks the injected credential hook first', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // The tested ColorOS build cancels an app's reader session outright while
      // the device is locked, so this is the real device's behaviour. The
      // platform prompt is then the only reader that can authenticate.
      //
      // Production/test split: production has NO credential hook — that flow
      // is pinned by the "no injected hook" test below. Here the hook is
      // injected because the platform's own bouncer cannot be raised on the
      // test host, and it must be asked FIRST: the injected flow keeps
      // driving the outcome, so a test can still hold the "platform is
      // asking" window open and observe the panel from inside it.
      //
      // The card is deliberately NOT raised anywhere in this flow: no
      // `listening` event ever arrives, and only `listening` may put the card
      // on screen — a card for a reader this device has already refused would
      // be an ask a finger can never answer.
      final platformPrompt = Completer<bool>();
      await _pumpLockScreen(
        tester,
        reader: reader,
        authenticateWithCredential: ({String? appName}) =>
            platformPrompt.future,
      );

      await spy.capture(() async {
        await _tapBubble(tester, 'Camera');
        // No card answers the tap before the reader is consulted: the reader
        // has not been handed over, so nothing honest can be drawn yet.
        expect(find.byType(FingerprintAuthPrompt), findsNothing);

        // Two cancellations: the panel's single retry, then the reader is done.
        reader.emit({'type': 'error', 'code': 5, 'message': 'canceled'});
        await _settle(tester);
        reader.emit({'type': 'error', 'code': 5, 'message': 'canceled'});
        await _settle(tester);

        // The injected hook now holds the request — the platform is asking —
        // and still no card has been drawn by the launcher.
        expect(find.byType(FingerprintAuthPrompt), findsNothing);

        platformPrompt.complete(true);
        await _settleLaunch(tester);
      });

      // Answered: the app is opening, with no launcher-drawn ask in between.
      expect(spy.launchedPackages, equals(['com.test.camera']));

      semantics.dispose();
    });

    testWidgets('a refused reader is not re-armed by the next tap', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // Re-arming a reader the platform has already refused spends the sensor
      // and can only fail the same way: on the tested device it produced six
      // arms and six cancellations inside 200 ms.
      final first = Completer<bool>();
      final second = Completer<bool>();
      var asks = 0;
      await _pumpLockScreen(
        tester,
        reader: reader,
        authenticateWithCredential: ({String? appName}) {
          asks++;
          return asks == 1 ? first.future : second.future;
        },
      );

      await spy.capture(() async {
        await _tapBubble(tester, 'Camera');
        reader.emit({'type': 'error', 'code': 5, 'message': 'canceled'});
        await _settle(tester);
        reader.emit({'type': 'error', 'code': 5, 'message': 'canceled'});
        await _settle(tester);
        // The user backs out of the platform prompt, so the panel is still
        // locked and still owes them an answer.
        first.complete(false);
        await _settle(tester);
        expect(spy.launchedPackages, isEmpty);
        expect(find.text('AUTH REQUIRED TO LAUNCH CAMERA'), findsOneWidget);

        // Second tap in the same lock session: the reader is known to be
        // refused, so the request goes straight to the credential hook — no
        // further arm. No card appears for it either: it would be an ask for
        // a finger the platform has already refused twice.
        await _tapBubble(tester, 'Camera');
        expect(find.byType(FingerprintAuthPrompt), findsNothing);
        expect(asks, equals(2));

        second.complete(true);
        await _settleLaunch(tester);
      });

      expect(spy.launchedPackages, equals(['com.test.camera']));

      semantics.dispose();
    });

    testWidgets(
      'a refused reader with no injected hook resolves through the platform bridge',
      (tester) async {
        final semantics = tester.ensureSemantics();
        // Production truth: no authenticateWithCredential hook exists outside
        // tests. The refusal must still resolve the request — the old code
        // gated the fallback on that hook, so on a real locked device the
        // completer hung behind a modal card forever and the only exits were
        // CANCEL or the mislabelled PIN button (report §3.1). Now the
        // fallback completes as AuthOutcome.deferToPlatform and the launch
        // runs through the platform's single requestDismissKeyguard bouncer:
        // one ask, raised by the platform, no card from us at any point.
        await _pumpLockScreen(tester, reader: reader);

        await spy.capture(() async {
          await _tapBubble(tester, 'Camera');
          expect(find.byType(FingerprintAuthPrompt), findsNothing);

          reader.emit({'type': 'error', 'code': 5, 'message': 'canceled'});
          await _settle(tester);
          reader.emit({'type': 'error', 'code': 5, 'message': 'canceled'});
          await _settle(tester);

          // Refused twice: the request resolved without any launcher-drawn
          // ask, and the deferred launch went through the platform bridge.
          expect(find.byType(FingerprintAuthPrompt), findsNothing);
          await _settleLaunch(tester);
        });

        expect(spy.launchedPackages, equals(['com.test.camera']));

        semantics.dispose();
      },
    );

    testWidgets('a keyguard-locked refusal resolves the request immediately', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // While the keyguard is locked the native side now refuses the arm
      // before touching the sensor, with a distinct event (D2-3): on the
      // tested build every locked-state arm was cancelled in ~2 ms anyway, so
      // the refusal is reported without spending the sensor. Dart treats it
      // like any other refusal — the reader is unusable for the rest of the
      // lock session and a pending request resolves through the credential
      // fallback, which in production means the platform's own bouncer.
      await _pumpLockScreen(tester, reader: reader);

      await spy.capture(() async {
        await _tapBubble(tester, 'Camera');
        reader.emit({'type': 'keyguardLocked'});
        await _settleLaunch(tester);
      });

      // No card, no retry: the refusal resolved the request straight away.
      expect(find.byType(FingerprintAuthPrompt), findsNothing);
      expect(spy.launchedPackages, equals(['com.test.camera']));

      semantics.dispose();
    });

    testWidgets('the credential route is offered when the finger will not read', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester, reader: reader);

      await _tapBubble(tester, 'Camera');
      await _handOverReader(tester, reader);
      expect(find.text('UNLOCK'), findsNothing);

      reader.emit({'type': 'failed'});
      await _settle(tester);

      await spy.capture(() async {
        await tester.tap(find.text('UNLOCK'));
        await _settleLaunch(tester);
      });

      expect(spy.launchedPackages, equals(['com.test.camera']));
      expect(find.byType(FingerprintAuthPrompt), findsNothing);

      semantics.dispose();
    });

    testWidgets(
      'a device with no enrolled finger never raises the panel prompt',
      (tester) async {
        final semantics = tester.ensureSemantics();
        // There is no finger that could ever answer a prompt, so the panel must
        // not pretend to wait for one; the platform credential prompt answers.
        await _pumpLockScreen(
          tester,
          reader: _FakeReader(ready: false),
          authenticate: ({String? appName}) async => true,
        );

        await spy.capture(() async {
          await _tapBubble(tester, 'Camera');
          await _settleLaunch(tester);
        });

        expect(find.byType(FingerprintAuthPrompt), findsNothing);
        expect(spy.launchedPackages, equals(['com.test.camera']));

        semantics.dispose();
      },
    );

    testWidgets('the prompt is announced as a live region with real buttons', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpLockScreen(tester, reader: reader);

      await _tapBubble(tester, 'Camera');
      await _handOverReader(tester, reader);

      final prompt = tester.getSemantics(find.byType(FingerprintAuthPrompt));
      expect(prompt.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
      expect(prompt.getSemanticsData().label, 'Fingerprint required');

      final cancel = _nodeLabelled(
        tester,
        'Cancel and stay on the lock screen',
      );
      expect(cancel, isNotNull, reason: 'the prompt has no cancel node');
      expect(
        cancel!.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'a reader could hear the button but not press it',
      );

      semantics.dispose();
      await _settle(tester);
    });

    testWidgets(
      'platform userPresent while locked completes auth and launches app',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpLockScreen(tester, reader: reader);

        await _tapBubble(tester, 'Camera');
        await _handOverReader(tester, reader);
        expect(find.byType(FingerprintAuthPrompt), findsOneWidget);

        await spy.capture(() async {
          LauncherBridge.dispatchUserPresentForTesting();
          await _settleLaunch(tester);
        });

        expect(spy.launchedPackages, equals(['com.test.camera']));
        expect(find.byType(FingerprintAuthPrompt), findsNothing);

        semantics.dispose();
      },
    );
  });
}
