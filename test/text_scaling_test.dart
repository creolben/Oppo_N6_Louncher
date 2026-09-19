import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/canvas/galaxy_custom_painter.dart';
import 'package:mylauncher/canvas/galaxy_interactive_canvas.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/features/lockscreen/bouncing_apps_painter.dart';
import 'package:mylauncher/features/lockscreen/cosmic_lock_screen.dart';
import 'package:mylauncher/models/app_entry.dart';
import 'package:mylauncher/models/constellation.dart';

/// App names and constellation titles are painted into canvases rather than laid
/// out as widgets, so they used to stay at 1.0x while every real `Text` on the
/// same screen grew with the system font setting. These hold the scale in place.

const TextScaler _large = TextScaler.linear(1.5);

AppEntry _app() => AppEntry(
      packageName: 'com.test.phone',
      label: 'Phone',
      category: AppCategory.core,
      accentColor: Colors.green,
    );

void main() {
  group('Painted app labels follow the system text scale', () {
    test('a scaled label is laid out wider than an unscaled one', () {
      final plain = _app()..ensurePainters(32);
      final scaled = _app()..ensurePainters(32, textScaler: _large);

      expect(scaled.labelPainter!.width, greaterThan(plain.labelPainter!.width));
    });

    test('changing the scale relayouts instead of reusing the cache', () {
      final app = _app()..ensurePainters(32);
      final TextPainter before = app.labelPainter!;

      app.ensurePainters(32, textScaler: _large);

      expect(identical(app.labelPainter, before), isFalse,
          reason: 'the cached label survived a text-scale change');
    });

    test('the fallback glyph stays sized to its node, not the font setting', () {
      // The glyph stands in for an icon and has to fit the bubble it sits in,
      // so growing it with the system font would push it out of the sphere.
      final plain = _app()..ensurePainters(32);
      final scaled = _app()..ensurePainters(32, textScaler: _large);

      expect(scaled.iconPainter!.height, equals(plain.iconPainter!.height));
    });
  });

  group('Constellation titles follow the system text scale', () {
    Constellation constellation() => Constellation(
          id: 'core',
          name: 'Essentials',
          category: AppCategory.core,
          primaryColor: Colors.amber,
          secondaryColor: Colors.orange,
          glowColor: Colors.amberAccent,
          emblemIcon: Icons.star,
          center: Offset.zero,
          isExpanded: true,
        );

    test('title and count badge scale', () {
      final plain = constellation()..ensurePainters();
      final scaled = constellation()..ensurePainters(textScaler: _large);

      expect(scaled.titlePainter!.width,
          greaterThan(plain.titlePainter!.width));
      expect(scaled.countBadgePainter!.width,
          greaterThan(plain.countBadgePainter!.width));
    });

    test('the emblem glyph does not scale', () {
      final plain = constellation()..ensurePainters();
      final scaled = constellation()..ensurePainters(textScaler: _large);

      expect(scaled.iconPainter!.height, equals(plain.iconPainter!.height));
    });
  });

  group('The canvases take the ambient scale from the tree', () {
    testWidgets('lock screen passes it to the bubble painter', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: _large),
              child: Scaffold(
                body: CosmicLockScreen(
                  foldable: FoldableController(),
                  apps: [_app()],
                  onUnlock: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<BouncingAppsPainter>()
          .single;

      expect(painter.textScaler, _large);
    });

    testWidgets('galaxy canvas passes it to the galaxy painter',
        (tester) async {
      final apps = [_app()];
      final engine = GalaxyLayoutEngine()..assignApps(apps);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: _large),
              child: Scaffold(
                body: GalaxyInteractiveCanvas(
                  apps: apps,
                  foldable: FoldableController(),
                  camera: CameraController(),
                  layoutEngine: engine,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<GalaxyCustomPainter>()
          .single;

      expect(painter.textScaler, _large);
    });
  });
}
