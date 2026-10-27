import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_storage_service.dart';

// Kept apart from the widget tests: a save queued inside a widget test's fake
// zone never completes, and the static save queue would then stall real I/O.
void main() {
  group('firstRunHintDismissed persistence', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('first_run_hint_');
      GalaxyStorageService.debugStorageDirectory = dir;
    });

    tearDown(() {
      GalaxyStorageService.debugStorageDirectory = null;
      dir.deleteSync(recursive: true);
    });

    test('a dismissal is stored and survives later unrelated saves', () async {
      await GalaxyStorageService.saveConfig(
        coreAppPackageNames: ['com.core'],
        nativeLauncherMode: true,
      );
      expect(
        (await GalaxyStorageService.loadConfig())['firstRunHintDismissed'],
        isNull,
        reason: 'older files have no key, which reads as not dismissed',
      );

      await GalaxyStorageService.saveConfig(
        coreAppPackageNames: ['com.core'],
        firstRunHintDismissed: true,
      );
      // A later save from an editor or the gestures sheet omits the key.
      await GalaxyStorageService.saveConfig(
        coreAppPackageNames: ['com.core'],
        doubleTapToSleep: true,
      );

      final stored = jsonDecode(
        File('${dir.path}/galaxy_settings.json').readAsStringSync(),
      ) as Map;
      expect(stored['firstRunHintDismissed'], isTrue);
      expect(stored['nativeLauncherMode'], isTrue);
      expect(stored['doubleTapToSleep'], isTrue);
    });

    test('mergeConfig leaves the key alone when it is not passed', () {
      final merged = GalaxyStorageService.mergeConfig(
        {'firstRunHintDismissed': true},
        coreAppPackageNames: const [],
      );
      expect(merged['firstRunHintDismissed'], isTrue);
    });
  });
}
