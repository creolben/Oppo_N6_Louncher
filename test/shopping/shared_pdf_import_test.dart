import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/launcher_bridge.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/features/shopping/ui/import_review_sheet.dart';
import 'package:mylauncher/features/shopping/ui/shopping_surface.dart';
import 'package:mylauncher/main.dart';

void main() {
  tearDown(() {
    // The listener is static; replace the closure that still points at a
    // disposed State so a later test cannot call into it.
    LauncherBridge.setSharedPdfListener((_) {});
  });

  /// Pumps the launcher with the PDF seams stubbed and the keyguard answer
  /// forced. The three pumps let the app scan, stored-config read and
  /// cold-start keyguard check settle.
  Future<void> pumpLauncher(
    WidgetTester tester, {
    required bool locked,
    String text = 'Milk\nEggs\nBread',
  }) async {
    await tester.pumpWidget(
      ChronoFoldApp(
        isKeyguardLocked: () async => locked,
        takePendingSharedPdf: () async => null,
        extractPdfText: (String path) async =>
            PdfTextResult(text: text, pageCount: 1),
        pickPdf: () async => null,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets(
    'a shared PDF while unlocked opens the shopping surface with the review sheet',
    (WidgetTester tester) async {
      await pumpLauncher(tester, locked: false);
      expect(find.byType(ShoppingSurface), findsNothing);
      expect(find.byType(ImportReviewSheet), findsNothing);

      LauncherBridge.dispatchSharedPdfForTesting(
        '/data/cache/imports/shared.pdf',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShoppingSurface), findsOneWidget);
      expect(find.byType(ImportReviewSheet), findsOneWidget);
      expect(find.text('Milk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a shared PDF while locked stays pending and never opens the surface',
    (WidgetTester tester) async {
      await pumpLauncher(tester, locked: true);
      expect(find.byType(CosmicLockScreen), findsOneWidget);

      LauncherBridge.dispatchSharedPdfForTesting(
        '/data/cache/imports/shared.pdf',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShoppingSurface), findsNothing);
      expect(find.byType(ImportReviewSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a pending path pulled at startup opens the surface when unlocked',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ChronoFoldApp(
          isKeyguardLocked: () async => false,
          takePendingSharedPdf: () async =>
              '/data/cache/imports/startup.pdf',
          extractPdfText: (String path) async =>
              const PdfTextResult(text: 'Bread'),
          pickPdf: () async => null,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ShoppingSurface), findsOneWidget);
      expect(find.byType(ImportReviewSheet), findsOneWidget);
      expect(find.text('Bread'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
