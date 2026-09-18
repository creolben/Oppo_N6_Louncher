import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mylauncher/core/galaxy_layout_engine.dart';
import 'package:mylauncher/core/foldable_controller.dart';
import 'package:mylauncher/canvas/camera_controller.dart';
import 'package:mylauncher/models/app_entry.dart';

void main() {
  group('GalaxyLayoutEngine Tests', () {
    test('Initializes constellations and assigns apps', () {
      final engine = GalaxyLayoutEngine();
      expect(engine.constellations.length, 5);

      final testApps = [
        AppEntry(packageName: 'com.test.phone', label: 'Phone', category: AppCategory.core),
        AppEntry(packageName: 'com.test.chat', label: 'Chat', category: AppCategory.social),
        AppEntry(packageName: 'com.test.mail', label: 'Mail', category: AppCategory.productivity),
        AppEntry(packageName: 'com.test.music', label: 'Music', category: AppCategory.entertainment),
        AppEntry(packageName: 'com.test.tool', label: 'Tools', category: AppCategory.tools),
      ];

      engine.assignApps(testApps);
      expect(engine.allApps.length, 5);

      final core = engine.constellations.firstWhere((c) => c.id == 'core');
      expect(core.apps.length, 1);
      expect(core.apps.first.label, 'Phone');
    });

    test('Morphs galaxy layout on posture change', () {
      final engine = GalaxyLayoutEngine();
      engine.assignApps([
        AppEntry(packageName: 'com.test.phone', label: 'Phone', category: AppCategory.core),
      ]);

      // Unfolded Flat
      engine.updateGalaxyMorph(
        posture: DevicePosture.flat,
        hingeAngle: 180.0,
        dt: 0.1,
      );

      // Folded
      engine.updateGalaxyMorph(
        posture: DevicePosture.folded,
        hingeAngle: 0.0,
        dt: 0.5,
      );

      final social = engine.constellations.firstWhere((c) => c.id == 'social');
      // In folded posture, social constellation aligns vertically
      expect(social.center.dx.abs(), lessThan(300));
    });
  });

  group('CameraController Coordinate Transformations', () {
    test('worldToScreen and screenToWorld invert accurately', () {
      final camera = CameraController();
      camera.updateViewportSize(const Size(800, 1200));

      const worldPoint = Offset(150, -220);
      final screenPoint = camera.worldToScreen(worldPoint);
      final backToWorld = camera.screenToWorld(screenPoint);

      expect((backToWorld.dx - worldPoint.dx).abs(), lessThan(0.001));
      expect((backToWorld.dy - worldPoint.dy).abs(), lessThan(0.001));
    });

    test('Applies pan and respects zoom bounds', () {
      final camera = CameraController();
      camera.updateViewportSize(const Size(800, 800));

      final initialTranslation = camera.translation;
      camera.applyPan(const Offset(50, -30));
      expect(camera.translation, initialTranslation + const Offset(50, -30));

      // Test zoom clamping
      camera.applyScale(10.0, const Offset(400, 400));
      expect(camera.zoom, lessThanOrEqualTo(CameraController.maxZoom * 1.35));
    });
  });

  group('FoldableController Posture Determination', () {
    test('Identifies folded, tabletop, and flat correctly', () {
      final controller = FoldableController();

      controller.setHingeAngle(180.0);
      expect(controller.posture, DevicePosture.flat);
      expect(controller.isFlat, true);

      controller.setHingeAngle(90.0);
      expect(controller.posture, DevicePosture.tabletop);
      expect(controller.isTabletop, true);

      controller.setHingeAngle(15.0);
      expect(controller.posture, DevicePosture.folded);
      expect(controller.isFolded, true);
    });
  });
}
