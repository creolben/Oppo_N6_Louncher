import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/models/app_shortcut.dart';

/// The native side sends a map per shortcut; these tests pin the tolerant
/// parsing so a partial or differently-typed map cannot crash the dialog.
void main() {
  group('AppShortcut parsing', () {
    test('reads every field from a full map', () {
      final shortcut = AppShortcut.fromMap({
        'id': 'com.example/com.example.Send',
        'packageName': 'com.example',
        'shortLabel': 'Send',
        'longLabel': 'Send a message',
        'rank': 2,
        'isPinned': true,
        'iconPng': Uint8List.fromList([1, 2, 3]),
      });

      expect(shortcut.id, 'com.example/com.example.Send');
      expect(shortcut.packageName, 'com.example');
      expect(shortcut.shortLabel, 'Send');
      expect(shortcut.longLabel, 'Send a message');
      expect(shortcut.rank, 2);
      expect(shortcut.isPinned, isTrue);
      expect(shortcut.iconPng, Uint8List.fromList([1, 2, 3]));
    });

    test('falls back from short to long label and then to the id', () {
      AppShortcut map({String short = '', String long = ''}) =>
          AppShortcut.fromMap({
            'id': 'id-only',
            'packageName': 'com.example',
            'shortLabel': short,
            'longLabel': long,
          });

      expect(map(short: 'Short').label, 'Short');
      expect(map(long: 'Longer').label, 'Longer');
      expect(map().label, 'id-only');
    });

    test('tolerates missing fields and a non-integer rank', () {
      final shortcut = AppShortcut.fromMap(<String, dynamic>{});

      expect(shortcut.id, '');
      expect(shortcut.packageName, '');
      expect(shortcut.shortLabel, '');
      expect(shortcut.longLabel, '');
      expect(shortcut.rank, 0);
      expect(shortcut.isPinned, isFalse);
      expect(shortcut.iconPng, isNull);
    });
  });
}
