import '../../../core/launcher_bridge.dart';
import 'document_parser.dart';

/// Why a PDF import could not produce a [ParsedDocument].
enum PdfImportErrorKind {
  /// The PDF has no text layer at all — almost always a scan.
  emptyTextLayer,

  /// The PDF is password protected.
  encrypted,

  /// The PDF could not be parsed for any other reason.
  unreadable,

  /// The user dismissed the picker.
  cancelled,
}

/// The outcome of a PDF import: a [ParsedDocument] or a typed failure.
///
/// A failure never carries a document, and a success never carries an error, so
/// callers branch on [isSuccess] once rather than checking a sentinel.
class PdfImportResult {
  final ParsedDocument? document;
  final PdfImportErrorKind? error;
  final String? message;

  const PdfImportResult.success(ParsedDocument this.document)
      : error = null,
        message = null;

  const PdfImportResult.failure(this.error, this.message) : document = null;

  bool get isSuccess => document != null;
}

/// Turns a PDF into a [ParsedDocument] through the platform's text extractor.
///
/// Both the extraction and the picker are injected so the service is testable
/// without a device. [importFromPicker] is the in-app route; [importPath] is the
/// share/open route, where the native side has already produced the path.
class PdfImportService {
  final Future<PdfTextResult> Function(String path) extract;
  final Future<String?> Function() pick;
  final DocumentParser parser;

  const PdfImportService({
    required this.extract,
    required this.pick,
    this.parser = const DocumentParser(),
  });

  /// The message shown for a PDF whose text layer is empty. Exact copy: it
  /// tells the user why a scanned recipe did not import and what is not
  /// supported, rather than blaming the file.
  static const String emptyTextLayerMessage =
      'This PDF has no selectable text. Scanned PDFs are not supported yet.';

  static const String encryptedMessage =
      'This PDF is password protected and cannot be imported.';

  static const String unreadableMessage = 'This PDF could not be read.';

  /// Picks a PDF and imports it. A dismissed picker resolves to a
  /// [PdfImportErrorKind.cancelled] failure so the caller can stay silent.
  Future<PdfImportResult> importFromPicker() async {
    final String? path = await pick();
    if (path == null) {
      return const PdfImportResult.failure(
        PdfImportErrorKind.cancelled,
        null,
      );
    }
    return importPath(path);
  }

  /// Extracts and parses the PDF at [path].
  Future<PdfImportResult> importPath(String path) async {
    final PdfTextResult extracted;
    try {
      extracted = await extract(path);
    } catch (_) {
      return const PdfImportResult.failure(
        PdfImportErrorKind.unreadable,
        unreadableMessage,
      );
    }

    switch (extracted.errorCode) {
      case 'PDF_ENCRYPTED':
        return const PdfImportResult.failure(
          PdfImportErrorKind.encrypted,
          encryptedMessage,
        );
      case null:
        break;
      default:
        return const PdfImportResult.failure(
          PdfImportErrorKind.unreadable,
          unreadableMessage,
        );
    }

    if (extracted.text.trim().isEmpty) {
      return const PdfImportResult.failure(
        PdfImportErrorKind.emptyTextLayer,
        emptyTextLayerMessage,
      );
    }

    return PdfImportResult.success(parser.parseDocument(extracted.text));
  }
}
