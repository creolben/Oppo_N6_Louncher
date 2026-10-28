import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/shopping/parsing/document_parser.dart';
import 'package:mylauncher/features/shopping/parsing/pdf_text_import.dart';

class _ThrowingParser extends DocumentParser {
  const _ThrowingParser();

  @override
  ParsedDocument parseDocument(String fullText) => throw StateError('boom');
}

/// A [PdfImportService] wired to fakes: no device, no platform channel.
PdfImportService _service({
  required Future<PdfTextResult> Function(String path) extract,
  Future<String?> Function()? pick,
}) {
  return PdfImportService(
    extract: extract,
    pick: pick ?? () async => 'picked.pdf',
  );
}

void main() {
  group('PdfImportService', () {
    test('parses the extracted text layer into a ParsedDocument', () async {
      final PdfImportService service = _service(
        extract: (String path) async => const PdfTextResult(
          text: 'Ingredients\nMilk\nEggs',
          pageCount: 2,
        ),
      );

      final PdfImportResult result = await service.importPath('a.pdf');

      expect(result.isSuccess, isTrue);
      expect(result.document, isNotNull);
      expect(result.document!.isRecipe, isTrue);
      final names =
          result.document!.items.map((item) => item.name.toLowerCase()).toSet();
      expect(names, containsAll(<String>{'milk', 'eggs'}));
    });

    test('a parser error is a typed failure, not an unhandled exception',
        () async {
      final PdfImportService service = PdfImportService(
        extract: (String path) async => const PdfTextResult(text: 'Milk'),
        pick: () async => 'picked.pdf',
        parser: const _ThrowingParser(),
      );

      final PdfImportResult result = await service.importPath('a.pdf');

      expect(result.isSuccess, isFalse);
      expect(result.error, PdfImportErrorKind.unreadable);
      expect(result.message, PdfImportService.unreadableMessage);
    });

    test('an empty text layer is a typed failure with the exact message',
        () async {
      final PdfImportService service = _service(
        extract: (String path) async => const PdfTextResult(text: '   \n  '),
      );

      final PdfImportResult result = await service.importPath('scan.pdf');

      expect(result.isSuccess, isFalse);
      expect(result.error, PdfImportErrorKind.emptyTextLayer);
      expect(result.message, PdfImportService.emptyTextLayerMessage);
      expect(
        result.message,
        'This PDF has no selectable text. Scanned PDFs are not supported yet.',
      );
    });

    test('an encrypted PDF reports the encrypted failure', () async {
      final PdfImportService service = _service(
        extract: (String path) async =>
            const PdfTextResult(errorCode: 'PDF_ENCRYPTED'),
      );

      final PdfImportResult result = await service.importPath('locked.pdf');

      expect(result.isSuccess, isFalse);
      expect(result.error, PdfImportErrorKind.encrypted);
      expect(result.document, isNull);
    });

    test('an unreadable PDF reports the unreadable failure', () async {
      final PdfImportService service = _service(
        extract: (String path) async =>
            const PdfTextResult(errorCode: 'PDF_UNREADABLE'),
      );

      final PdfImportResult result = await service.importPath('broken.pdf');

      expect(result.isSuccess, isFalse);
      expect(result.error, PdfImportErrorKind.unreadable);
    });

    test('a thrown extractor is treated as unreadable, not a crash', () async {
      final PdfImportService service = _service(
        extract: (String path) async => throw StateError('boom'),
      );

      final PdfImportResult result = await service.importPath('broken.pdf');

      expect(result.isSuccess, isFalse);
      expect(result.error, PdfImportErrorKind.unreadable);
    });

    test('cancelling the picker never extracts and reports cancelled', () async {
      var extracted = false;
      final PdfImportService service = _service(
        pick: () async => null,
        extract: (String path) async {
          extracted = true;
          return const PdfTextResult(text: 'Milk');
        },
      );

      final PdfImportResult result = await service.importFromPicker();

      expect(result.isSuccess, isFalse);
      expect(result.error, PdfImportErrorKind.cancelled);
      expect(result.message, isNull);
      expect(extracted, isFalse);
    });

    test('a picked path is imported the same way as a shared path', () async {
      final PdfImportService service = _service(
        pick: () async => 'picked.pdf',
        extract: (String path) async => const PdfTextResult(text: 'Bread'),
      );

      final PdfImportResult result = await service.importFromPicker();

      expect(result.isSuccess, isTrue);
      expect(result.document!.items.single.name.toLowerCase(), 'bread');
    });
  });
}
