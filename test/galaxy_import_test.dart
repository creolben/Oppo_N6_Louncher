import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_storage_service.dart';

void main() {
  late Directory tmp;
  late File source;
  late File target;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('galaxy_import_');
    Directory('${tmp.path}/import').createSync();
    source = File('${tmp.path}/import/galaxy_settings.json');
    target = File('${tmp.path}/galaxy_settings.json');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('no pending file is a no-op', () async {
    expect(await GalaxyStorageService.applyPendingImport(source, target), isFalse);
    expect(target.existsSync(), isFalse);
  });

  test('valid import replaces settings, keeps a backup, consumes the file', () async {
    target.writeAsStringSync('{"coreAppPackageNames":["old"]}');
    final imported = jsonEncode({
      'coreAppPackageNames': ['a', 'b'],
      'constellationAppOverrides': {'x': ['c']},
    });
    source.writeAsStringSync(imported);

    expect(await GalaxyStorageService.applyPendingImport(source, target), isTrue);
    expect(target.readAsStringSync(), imported);
    expect(File('${target.path}.pre-import').readAsStringSync(),
        '{"coreAppPackageNames":["old"]}');
    expect(source.existsSync(), isFalse);
  });

  test('non-object JSON is rejected and settings are untouched', () async {
    target.writeAsStringSync('{"coreAppPackageNames":["keep"]}');
    source.writeAsStringSync('[1,2,3]');

    expect(await GalaxyStorageService.applyPendingImport(source, target), isFalse);
    expect(target.readAsStringSync(), '{"coreAppPackageNames":["keep"]}');
    expect(source.existsSync(), isFalse);
    expect(File('${source.path}.rejected').existsSync(), isTrue);
  });

  test('malformed JSON is rejected', () async {
    source.writeAsStringSync('{not json');
    expect(await GalaxyStorageService.applyPendingImport(source, target), isFalse);
    expect(target.existsSync(), isFalse);
    expect(File('${source.path}.rejected').existsSync(), isTrue);
  });
}
