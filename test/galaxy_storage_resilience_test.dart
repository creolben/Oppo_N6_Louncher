import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_storage_service.dart';

Map<String, dynamic> _constellation(String id) => <String, dynamic>{
  'id': id,
  'name': 'Group $id',
  'primaryColorValue': 0xFF00E5FF,
  'emblemIconCodePoint': Icons.star_rounded.codePoint,
  'packageNames': ['com.$id'],
};

void main() {
  late Directory dir;
  late File settings;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('galaxy_storage_');
    settings = File('${dir.path}/galaxy_settings.json');
    GalaxyStorageService.debugStorageDirectory = dir;
  });

  tearDown(() {
    GalaxyStorageService.debugStorageDirectory = null;
    dir.deleteSync(recursive: true);
  });

  List<String> siblings() => dir
      .listSync()
      .map((e) => e.uri.pathSegments.last)
      .toList()
    ..sort();

  group('atomic save', () {
    test('writes the merged config and leaves no temp file behind', () async {
      await GalaxyStorageService.saveConfig(
        coreAppPackageNames: ['com.core'],
        nativeLauncherMode: true,
      );

      final stored = jsonDecode(settings.readAsStringSync()) as Map;
      expect(stored['coreAppPackageNames'], ['com.core']);
      expect(stored['nativeLauncherMode'], isTrue);
      expect(siblings(), ['galaxy_settings.json']);
    });
  });

  group('corrupt settings file', () {
    test('load backs the damaged file up instead of discarding it', () async {
      const truncated = '{"customConstellations": [{"id": "custom_1", "na';
      settings.writeAsStringSync(truncated);

      final config = await GalaxyStorageService.loadConfig();

      expect(config, isEmpty);
      final backups =
          siblings().where((n) => n.startsWith('galaxy_settings.json.corrupt.'));
      expect(backups, hasLength(1));
      expect(
        File('${dir.path}/${backups.single}').readAsStringSync(),
        truncated,
      );
    });

    test('a save over a damaged file preserves it as a backup', () async {
      settings.writeAsStringSync('[1, 2'); // not even an object
      await GalaxyStorageService.saveConfig(coreAppPackageNames: ['com.new']);

      final stored = jsonDecode(settings.readAsStringSync()) as Map;
      expect(stored['coreAppPackageNames'], ['com.new']);
      expect(
        siblings().where((n) => n.contains('.corrupt.')),
        hasLength(1),
      );
    });

    test('valid JSON that is not an object is also backed up', () async {
      settings.writeAsStringSync('[]');
      expect(await GalaxyStorageService.loadConfig(), isEmpty);
      expect(siblings().where((n) => n.contains('.corrupt.')), hasLength(1));
    });
  });

  group('constellation parsing', () {
    test('skips malformed entries and keeps the rest', () {
      final parsed = CustomConstellationConfig.parseList([
        _constellation('a'),
        {'name': 'no id'},
        {'id': 42, 'name': 'numeric id'},
        'not a map',
        {
          ..._constellation('b'),
          'packageNames': ['com.ok', 7, null],
          'primaryColorValue': 'red',
        },
      ]);

      expect(parsed.map((c) => c.id), ['a', 'b']);
      expect(parsed.last.packageNames, ['com.ok']);
      expect(
        parsed.last.primaryColorValue,
        isA<int>(),
        reason: 'a mistyped colour falls back to the default',
      );
    });

    test('a non-list value yields no constellations', () {
      expect(CustomConstellationConfig.parseList(null), isEmpty);
      expect(CustomConstellationConfig.parseList({'id': 'x'}), isEmpty);
    });
  });

  group('serialised saves', () {
    test('concurrent unawaited saves do not undo one another', () async {
      final saves = <Future<void>>[
        GalaxyStorageService.saveConfig(
          coreAppPackageNames: ['com.core'],
          doubleTapToSleep: true,
        ),
        GalaxyStorageService.saveConfig(
          coreAppPackageNames: ['com.core'],
          swipeDownAction: 'notifications',
        ),
        GalaxyStorageService.saveConfig(
          coreAppPackageNames: ['com.core'],
          hiddenPackageNames: ['com.hidden'],
        ),
        GalaxyStorageService.saveConfig(
          coreAppPackageNames: ['com.core'],
          customConstellations: [
            CustomConstellationConfig.fromJson(_constellation('kept')),
          ],
        ),
      ];
      await Future.wait(saves);

      final stored = jsonDecode(settings.readAsStringSync()) as Map;
      expect(stored['doubleTapToSleep'], isTrue);
      expect(stored['swipeDownAction'], 'notifications');
      expect(stored['hiddenPackageNames'], ['com.hidden']);
      expect((stored['customConstellations'] as List).single['id'], 'kept');
    });
  });
}
