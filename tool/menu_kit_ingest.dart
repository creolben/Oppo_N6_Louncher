// Stores weekly meal-kit PDFs in Supabase: the original PDF in the private
// "menu-kits" bucket, and the parsed week (menus, both shopping lists, every
// recipe) through the ingest_menu_kit() database function.
//
// Uses the same MenuKitParser as the app, on text extracted exactly as the
// app extracts it (tool/pdf_text, needs java and curl).
//
//   dart run tool/menu_kit_ingest.dart ~/Documents/Recipes --dry-run
//   dart run tool/menu_kit_ingest.dart ~/Documents/Recipes --out kits.json
//   SUPABASE_URL=https://<ref>.supabase.co SUPABASE_SECRET_KEY=<key> \
//     dart run tool/menu_kit_ingest.dart ~/Documents/Recipes
//
// The key must be the project's service-role or secret key: the function and
// bucket are closed to the anon key. Re-running is safe; each week is
// replaced, not duplicated.
import 'dart:convert';
import 'dart:io';

import 'package:mylauncher/features/shopping/parsing/menu_kit_parser.dart';

import 'menu_kit/payload.dart';

const String _bucket = 'menu-kits';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final outIndex = args.indexOf('--out');
  final String? outPath = outIndex >= 0 && outIndex + 1 < args.length
      ? args[outIndex + 1]
      : null;
  final inputs = <String>[
    for (var i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') && (i == 0 || args[i - 1] != '--out'))
        args[i],
  ];
  if (inputs.isEmpty || args.contains('--help')) {
    stderr.writeln(
      'usage: dart run tool/menu_kit_ingest.dart <pdf-dir|file.pdf>... '
      '[--dry-run] [--out payloads.json]',
    );
    exit(inputs.isEmpty ? 2 : 0);
  }

  final pdfs = _pdfsIn(inputs);
  if (pdfs.isEmpty) _fail('No PDFs found in ${inputs.join(', ')}');

  final url = Platform.environment['SUPABASE_URL']?.replaceFirst(
    RegExp(r'/+$'),
    '',
  );
  final key =
      Platform.environment['SUPABASE_SECRET_KEY'] ??
      Platform.environment['SUPABASE_SERVICE_ROLE_KEY'];
  final upload = !dryRun && outPath == null;
  if (upload && (url == null || key == null)) {
    _fail(
      'Set SUPABASE_URL and SUPABASE_SECRET_KEY (or SUPABASE_SERVICE_ROLE_KEY), '
      'or pass --dry-run / --out.',
    );
  }

  final texts = await _extract(pdfs);
  final payloads = <Map<String, Object?>>[];
  var failures = 0;
  for (final pdf in pdfs) {
    final name = pdf.uri.pathSegments.last;
    final kit = const MenuKitParser().tryParse(texts[pdf.path]!);
    if (kit == null) {
      stderr.writeln('skip  $name: not a meal-kit PDF');
      failures++;
      continue;
    }
    final sha = await _sha256(pdf);
    final payload = menuKitPayload(
      kit,
      sourceFile: name,
      pdfSha256: sha,
      pdfPath: '$sha.pdf',
    );
    payloads.add(payload);
    final summary =
        '${kit.listName(MenuVariant.regular)}: '
        '${(payload['items']! as List).length} items, '
        '${kit.recipes.length} recipes';

    if (!upload) {
      stdout.writeln('ok    $name  $summary');
      continue;
    }
    try {
      final client = _Supabase(url!, key!);
      await client.uploadPdf(pdf, '$sha.pdf');
      final id = await client.ingest(payload);
      stdout.writeln('ok    $name  $summary  -> $id');
    } on Exception catch (error) {
      stderr.writeln('fail  $name: $error');
      failures++;
    }
  }

  if (outPath != null) {
    File(
      outPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(payloads));
    stdout.writeln('wrote ${payloads.length} kits to $outPath');
  }
  exit(failures == 0 ? 0 : 1);
}

List<File> _pdfsIn(List<String> inputs) {
  final pdfs = <File>[];
  for (final input in inputs) {
    final path = input.replaceFirst(
      RegExp(r'^~'),
      Platform.environment['HOME'] ?? '~',
    );
    if (FileSystemEntity.isDirectorySync(path)) {
      pdfs.addAll(
        Directory(path)
            .listSync()
            .whereType<File>()
            .where((File f) => f.path.toLowerCase().endsWith('.pdf')),
      );
    } else if (File(path).existsSync()) {
      pdfs.add(File(path));
    } else {
      _fail('Not found: $input');
    }
  }
  return pdfs..sort((File a, File b) => a.path.compareTo(b.path));
}

/// Extracts every PDF through tool/pdf_text, keyed by PDF path.
Future<Map<String, String>> _extract(List<File> pdfs) async {
  final script = File.fromUri(Platform.script.resolve('pdf_text/extract.sh'))
      .path;
  final work = Directory.systemTemp.createTempSync('menu_kit_ingest');
  try {
    final texts = <String, String>{};
    for (final pdf in pdfs) {
      // One PDF per folder, so extract.sh's <name>.txt cannot collide.
      final input = Directory('${work.path}/${texts.length}/in')
        ..createSync(recursive: true);
      final output = Directory('${work.path}/${texts.length}/out');
      pdf.copySync('${input.path}/kit.pdf');
      final result = await Process.run(script, <String>[
        input.path,
        output.path,
      ]);
      if (result.exitCode != 0) {
        _fail('Extracting ${pdf.path} failed:\n${result.stderr}');
      }
      texts[pdf.path] = File('${output.path}/kit.txt').readAsStringSync();
    }
    return texts;
  } finally {
    work.deleteSync(recursive: true);
  }
}

Future<String> _sha256(File file) async {
  final result = await Process.run('sha256sum', <String>[file.path]);
  if (result.exitCode != 0) _fail('sha256sum failed: ${result.stderr}');
  return (result.stdout as String).split(' ').first.trim();
}

Never _fail(String message) {
  stderr.writeln(message);
  exit(2);
}

/// The two Supabase REST calls the ingest needs.
class _Supabase {
  final String url;
  final String key;

  _Supabase(this.url, this.key);

  /// New-style secret keys go in `apikey` only; legacy JWT keys also need
  /// the bearer header.
  Map<String, String> get _auth => <String, String>{
    'apikey': key,
    if (key.startsWith('eyJ')) 'Authorization': 'Bearer $key',
  };

  Future<void> uploadPdf(File pdf, String path) async {
    await _send(
      'POST',
      '/storage/v1/object/$_bucket/$path',
      headers: <String, String>{
        'Content-Type': 'application/pdf',
        'x-upsert': 'true',
      },
      body: pdf.readAsBytesSync(),
    );
  }

  Future<String> ingest(Map<String, Object?> payload) async {
    final response = await _send(
      'POST',
      '/rest/v1/rpc/ingest_menu_kit',
      headers: <String, String>{'Content-Type': 'application/json'},
      body: utf8.encode(jsonEncode(<String, Object?>{'kit': payload})),
    );
    return jsonDecode(response) as String;
  }

  Future<String> _send(
    String method,
    String path, {
    required Map<String, String> headers,
    required List<int> body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, Uri.parse('$url$path'));
      <String, String>{..._auth, ...headers}.forEach(request.headers.set);
      request.add(body);
      final response = await request.close();
      final text = await utf8.decodeStream(response);
      if (response.statusCode >= 300) {
        throw HttpException('$method $path: ${response.statusCode} $text');
      }
      return text;
    } finally {
      client.close();
    }
  }
}
