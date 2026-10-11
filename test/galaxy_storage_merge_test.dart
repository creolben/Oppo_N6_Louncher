import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_storage_service.dart';

void main() {
  group('GalaxyStorageService.mergeConfig', () {
    late Map<String, dynamic> existing;

    setUp(() {
      existing = <String, dynamic>{
        'coreAppPackageNames': ['com.old'],
        'customConstellations': [
          {
            'id': 'custom_1',
            'name': 'One',
            'primaryColorValue': 0xFF00E5FF,
            'emblemIconCodePoint': Icons.star_rounded.codePoint,
            'packageNames': ['com.kept'],
          },
        ],
        'customGalaxies': [
          {
            'id': 'custom_1',
            'name': 'One',
            'primaryColorValue': 0xFF00E5FF,
            'emblemIconCodePoint': Icons.star_rounded.codePoint,
            'packageNames': ['com.kept'],
          },
        ],
        'constellationAppOverrides': {
          'social': ['com.social'],
        },
        'hiddenPackageNames': ['com.hidden'],
        'nativeLauncherMode': true,
        'doubleTapToSleep': true,
        'swipeDownAction': 'notifications',
      };
    });

    test('omitting nativeLauncherMode preserves the stored value', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
      );

      expect(merged['nativeLauncherMode'], isTrue);
      expect(merged['coreAppPackageNames'], ['com.new']);
    });

    test('omitting hiddenPackageNames preserves the stored list', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
      );

      expect(merged['hiddenPackageNames'], ['com.hidden']);
    });

    test('omitting constellationAppOverrides preserves the stored map', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
      );

      expect(merged['constellationAppOverrides'], {
        'social': ['com.social'],
      });
    });

    test('non-null arguments overwrite their stored values', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
        hiddenPackageNames: ['com.other'],
        constellationAppOverrides: {
          'tools': ['com.tools'],
        },
        nativeLauncherMode: false,
      );

      expect(merged['hiddenPackageNames'], ['com.other']);
      expect(merged['constellationAppOverrides'], {
        'tools': ['com.tools'],
      });
      expect(merged['nativeLauncherMode'], isFalse);
    });

    test('custom constellations and legacy galaxies stay in sync', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
        customConstellations: [
          CustomConstellationConfig(
            id: 'custom_2',
            name: 'Two',
            primaryColorValue: 0xFFFF0000,
            emblemIconCodePoint: Icons.rocket_launch_rounded.codePoint,
            packageNames: ['com.two'],
          ),
        ],
      );

      final written =
          (merged['customConstellations'] as List).single as Map<String, dynamic>;
      expect(written['id'], 'custom_2');
      expect(merged['customGalaxies'], merged['customConstellations']);
    });

    test('omitting the gesture preferences preserves the stored values', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
      );

      expect(merged['doubleTapToSleep'], isTrue);
      expect(merged['swipeDownAction'], 'notifications');
    });

    test('gesture preferences overwrite their stored values', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.new'],
        doubleTapToSleep: false,
        swipeDownAction: 'search',
      );

      expect(merged['doubleTapToSleep'], isFalse);
      expect(merged['swipeDownAction'], 'search');
    });

    test('writing a gesture preference preserves every other key', () {
      final merged = GalaxyStorageService.mergeConfig(
        existing,
        coreAppPackageNames: ['com.old'],
        doubleTapToSleep: false,
      );

      // Every key the gesture save did not name must survive untouched: a
      // gesture must never reset the layout or the lock mode.
      expect(merged['coreAppPackageNames'], ['com.old']);
      expect(merged['customConstellations'], existing['customConstellations']);
      expect(merged['customGalaxies'], existing['customGalaxies']);
      expect(
        merged['constellationAppOverrides'],
        existing['constellationAppOverrides'],
      );
      expect(merged['hiddenPackageNames'], existing['hiddenPackageNames']);
      expect(merged['nativeLauncherMode'], isTrue);
      expect(merged['swipeDownAction'], 'notifications');
      expect(merged['doubleTapToSleep'], isFalse);
    });

    test('an empty existing config starts from the new arguments only', () {
      final merged = GalaxyStorageService.mergeConfig(
        const {},
        coreAppPackageNames: ['com.new'],
      );

      expect(merged['coreAppPackageNames'], ['com.new']);
      expect(merged.containsKey('nativeLauncherMode'), isFalse);
      expect(merged.containsKey('hiddenPackageNames'), isFalse);
      expect(merged.containsKey('constellationAppOverrides'), isFalse);
    });
  });
}
