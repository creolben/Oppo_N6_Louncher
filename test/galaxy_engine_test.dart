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

    test('Center Constellation respects maximum 6 apps and distributes angles symmetrically', () {
      final engine = GalaxyLayoutEngine();
      final apps = List.generate(
        8,
        (i) => AppEntry(packageName: 'com.test.app$i', label: 'App $i', category: AppCategory.tools),
      );

      // Set 6 apps
      engine.setCorePackageNames(apps.sublist(0, 6).map((a) => a.packageName).toList());
      engine.assignApps(apps);

      final core = engine.constellations.firstWhere((c) => c.id == 'core');
      expect(core.apps.length, 6);

      // Verify orbital layout properties
      // Dynamic core radius for 6 apps should be 96.0
      for (final app in core.apps) {
        expect((app.worldPosition.distance - 96.0).abs(), lessThan(0.01));
      }

      // Try adding a 7th app via addAppToCore -> should fail / return false
      final added = engine.addAppToCore(apps[6]);
      expect(added, false);
      expect(core.apps.length, 6);

      // Remove an app from core
      engine.removeAppFromCore(apps[0].packageName);
      expect(core.apps.length, 5);
      // For 5 apps, radius is also 96.0
      expect((core.apps.first.worldPosition.distance - 96.0).abs(), lessThan(0.01));

      // Test with 3 apps -> radius should be 74.0
      engine.setCorePackageNames(apps.sublist(0, 3).map((a) => a.packageName).toList());
      engine.assignApps(apps);
      expect(core.apps.length, 3);
      expect((core.apps.first.worldPosition.distance - 74.0).abs(), lessThan(0.01));

      // Test with 4 apps -> radius should be 84.0
      engine.setCorePackageNames(apps.sublist(0, 4).map((a) => a.packageName).toList());
      engine.assignApps(apps);
      expect(core.apps.length, 4);
      expect((core.apps.first.worldPosition.distance - 84.0).abs(), lessThan(0.01));
    });

    test('Creates and deletes custom constellations dynamically', () {
      final engine = GalaxyLayoutEngine();
      final apps = [
        AppEntry(packageName: 'com.test.crypto1', label: 'Bitcoin', category: AppCategory.tools),
        AppEntry(packageName: 'com.test.crypto2', label: 'Ethereum', category: AppCategory.tools),
        AppEntry(packageName: 'com.test.calc', label: 'Calc', category: AppCategory.tools),
      ];
      engine.assignApps(apps);

      final initialCount = engine.constellations.length;

      // Create custom constellation
      final custom = engine.createCustomConstellation(
        name: 'FinTech',
        primaryColor: const Color(0xFF00E5FF),
        emblemIcon: Icons.attach_money_rounded,
        packageNames: ['com.test.crypto1', 'com.test.crypto2'],
      );

      expect(engine.constellations.length, initialCount + 1);
      expect(custom.name, 'FinTech');
      expect(custom.apps.length, 2);
      expect(custom.apps.map((a) => a.packageName), containsAll(['com.test.crypto1', 'com.test.crypto2']));

      // Tools should only have remaining apps
      final tools = engine.constellations.firstWhere((c) => c.id == 'tools');
      expect(tools.apps.any((a) => a.packageName == 'com.test.crypto1'), false);

      // Delete custom constellation
      engine.deleteConstellation(custom.id);
      expect(engine.constellations.length, initialCount);
      // Tools should have crypto apps back
      final toolsAfter = engine.constellations.firstWhere((c) => c.id == 'tools');
      expect(toolsAfter.apps.any((a) => a.packageName == 'com.test.crypto1'), true);
    });

    test('Allows adding and removing apps to any constellation with overrides', () {
      final engine = GalaxyLayoutEngine();
      final apps = [
        AppEntry(packageName: 'com.social.chat', label: 'Chat', category: AppCategory.social),
        AppEntry(packageName: 'com.social.photo', label: 'Photo', category: AppCategory.social),
        AppEntry(packageName: 'com.work.docs', label: 'Docs', category: AppCategory.productivity),
      ];
      engine.assignApps(apps);

      final social = engine.constellations.firstWhere((c) => c.id == 'social');
      expect(social.apps.length, 2);

      // Add a work app to social constellation
      final docsApp = apps.firstWhere((a) => a.packageName == 'com.work.docs');
      engine.addAppToConstellation('social', docsApp);
      expect(social.apps.any((a) => a.packageName == 'com.work.docs'), true);
      expect(engine.constellationAppOverrides['social'], contains('com.work.docs'));

      // Remove chat from social
      engine.removeAppFromConstellation('social', 'com.social.chat');
      expect(social.apps.any((a) => a.packageName == 'com.social.chat'), false);
      expect(engine.constellationAppOverrides['social'], isNot(contains('com.social.chat')));
    });

    test('Strictly enforces 8-app maximum capacity on outer constellations', () {
      final engine = GalaxyLayoutEngine();
      final tenApps = List.generate(
        10,
        (i) => AppEntry(packageName: 'com.test.tool$i', label: 'Tool $i', category: AppCategory.tools),
      );
      engine.assignApps(tenApps);

      final tools = engine.constellations.firstWhere((c) => c.id == 'tools');
      // Should cap automatically to max 8 apps
      expect(tools.apps.length, lessThanOrEqualTo(8));

      // Attempting to set 10 apps via setConstellationAppPackages caps to 8
      engine.setConstellationAppPackages('tools', tenApps.map((a) => a.packageName).toList());
      expect(tools.apps.length, 8);

      // Attempting to add a 9th app returns false
      final extraApp = AppEntry(packageName: 'com.test.extra', label: 'Extra', category: AppCategory.tools);
      final added = engine.addAppToConstellation('tools', extraApp);
      expect(added, false);
      expect(tools.apps.length, 8);

      // Custom constellation created with 10 apps also caps to 8
      final custom = engine.createCustomConstellation(
        name: 'BigSector',
        primaryColor: const Color(0xFF00E5FF),
        emblemIcon: Icons.auto_awesome,
        packageNames: tenApps.map((a) => a.packageName).toList(),
      );
      expect(custom.apps.length, 8);
    });

    test('Center Constellation can open, close, and morph smoothly', () {
      final engine = GalaxyLayoutEngine();
      final core = engine.constellations.firstWhere((c) => c.id == 'core');
      expect(core.isExpanded, true);

      // Toggle core to close
      engine.toggleCore();
      expect(core.isExpanded, false);

      // Update morph to collapse
      engine.updateGalaxyMorph(
        posture: DevicePosture.flat,
        hingeAngle: 180.0,
        dt: 0.5,
      );
      expect(core.expansionProgress, lessThan(0.5));

      // Expand core
      engine.expandCore();
      expect(core.isExpanded, true);

      engine.updateGalaxyMorph(
        posture: DevicePosture.flat,
        hingeAngle: 180.0,
        dt: 0.5,
      );
      expect(core.expansionProgress, greaterThan(0.5));

      // expandOnly with an outer constellation closes core
      engine.expandOnly('social');
      expect(core.isExpanded, false);

      // expandOnly with core re-opens core and closes others
      engine.expandOnly('core');
      expect(core.isExpanded, true);
      final social = engine.constellations.firstWhere((c) => c.id == 'social');
      expect(social.isExpanded, false);
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
