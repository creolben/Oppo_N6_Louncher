import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/app_entry.dart';
import '../models/constellation.dart';
import 'foldable_controller.dart';
import 'galaxy_storage_service.dart';

class GalaxyLayoutEngine {
  static const int maxCoreApps = 6;
  static const int maxConstellationApps = 8;

  final List<Constellation> constellations = [];
  final List<AppEntry> allApps = [];

  GalaxyLayoutEngine() {
    _initConstellations();
  }

  void _initConstellations() {
    constellations.clear();
    constellations.addAll([
      Constellation(
        id: 'core',
        name: 'Essentials',
        category: AppCategory.core,
        primaryColor: const Color(0xFFFFD54F), // Radiant Gold
        secondaryColor: const Color(0xFFFF9800),
        glowColor: const Color(0x66FFD54F),
        emblemIcon: Icons.star_rounded,
        center: Offset.zero,
        radius: 110,
        isExpanded: true,
      ),
      Constellation(
        id: 'social',
        name: 'Connect',
        category: AppCategory.social,
        primaryColor: const Color(0xFFFF4081), // Vivid Rose
        secondaryColor: const Color(0xFFE040FB),
        glowColor: const Color(0x55FF4081),
        emblemIcon: Icons.forum_rounded,
        center: const Offset(-270, -180),
        radius: 140,
        isExpanded: false,
      ),
      Constellation(
        id: 'productivity',
        name: 'Workspace',
        category: AppCategory.productivity,
        primaryColor: const Color(0xFF00E5FF), // Cyber Cyan
        secondaryColor: const Color(0xFF2979FF),
        glowColor: const Color(0x5500E5FF),
        emblemIcon: Icons.workspaces_rounded,
        center: const Offset(270, -180),
        radius: 140,
        isExpanded: false,
      ),
      Constellation(
        id: 'media',
        name: 'Studio',
        category: AppCategory.entertainment,
        primaryColor: const Color(0xFF00E676), // Emerald Mint
        secondaryColor: const Color(0xFF1DE9B6),
        glowColor: const Color(0x5500E676),
        emblemIcon: Icons.play_circle_filled_rounded,
        center: const Offset(-270, 190),
        radius: 140,
        isExpanded: false,
      ),
      Constellation(
        id: 'tools',
        name: 'Utilities',
        category: AppCategory.tools,
        primaryColor: const Color(0xFFFFAB00), // Amber Gold
        secondaryColor: const Color(0xFFFF6D00),
        glowColor: const Color(0x55FFAB00),
        emblemIcon: Icons.tune_rounded,
        center: const Offset(270, 190),
        radius: 140,
        isExpanded: false,
      ),
    ]);
  }

  List<String> corePackageNames = [];
  List<String> get coreAppPackageNames => corePackageNames;

  List<CustomConstellationConfig> get customConstellations => constellations
      .where((c) => c.isCustom)
      .map((c) => CustomConstellationConfig(
            id: c.id,
            name: c.name,
            primaryColorValue: c.primaryColor.toARGB32(),
            emblemIconCodePoint: c.emblemIcon.codePoint,
            packageNames: c.apps.map((a) => a.packageName).toList(),
          ))
      .toList();

  final Map<String, List<String>> constellationAppOverrides = {};
  final List<String> hiddenPackageNames = [];

  bool isAppHidden(String packageName) => hiddenPackageNames.contains(packageName);

  void hideApp(String packageName) {
    if (!hiddenPackageNames.contains(packageName)) {
      hiddenPackageNames.add(packageName);
      assignApps(List.from(allApps));
    }
  }

  void unhideApp(String packageName) {
    if (hiddenPackageNames.remove(packageName)) {
      assignApps(List.from(allApps));
    }
  }

  void setHiddenPackageNames(List<String> packageNames) {
    hiddenPackageNames.clear();
    hiddenPackageNames.addAll(packageNames);
    if (allApps.isNotEmpty) {
      assignApps(List.from(allApps));
    }
  }

  void toggleConstellation(String id) {
    if (id == 'core') {
      toggleCore();
      return;
    }
    for (final c in constellations) {
      if (c.id == id) {
        c.isExpanded = !c.isExpanded;
      }
    }
  }

  void toggleCore() {
    final core = constellations.firstWhere((c) => c.id == 'core');
    core.isExpanded = !core.isExpanded;
  }

  void expandCore() {
    final core = constellations.firstWhere((c) => c.id == 'core');
    core.isExpanded = true;
  }

  void collapseCore() {
    final core = constellations.firstWhere((c) => c.id == 'core');
    core.isExpanded = false;
  }

  void expandOnly(String id) {
    if (id == 'core') {
      for (final c in constellations) {
        c.isExpanded = (c.id == 'core');
      }
      return;
    }
    for (final c in constellations) {
      if (c.id == 'core') {
        c.isExpanded = false;
      } else {
        c.isExpanded = (c.id == id);
      }
    }
  }

  void collapseAllExceptCore({bool expandCore = true}) {
    for (final c in constellations) {
      if (c.id != 'core') {
        c.isExpanded = false;
      } else if (expandCore) {
        c.isExpanded = true;
      }
    }
  }

  /// Sets custom core package names (strictly max 6 apps)
  void setCorePackageNames(List<String> packageNames) {
    corePackageNames = packageNames.take(maxCoreApps).toList();
    if (allApps.isNotEmpty) {
      assignApps(List.from(allApps));
    }
  }

  /// Sets package names for any constellation (standard or custom, strictly max 8 apps)
  void setConstellationAppPackages(String constellationId, List<String> packageNames) {
    if (constellationId == 'core') {
      setCorePackageNames(packageNames);
      return;
    }
    final c = constellations.where((item) => item.id == constellationId).firstOrNull;
    if (c != null) {
      final capped = packageNames.take(maxConstellationApps).toList();
      if (c.isCustom) {
        c.customPackageNames.clear();
        c.customPackageNames.addAll(capped);
      } else {
        constellationAppOverrides[constellationId] = List.from(capped);
      }
      if (allApps.isNotEmpty) {
        assignApps(List.from(allApps));
      }
    }
  }

  /// Adds an app to a constellation (enforces max capacity: 6 for core, 8 for outer)
  bool addAppToConstellation(String constellationId, AppEntry app) {
    if (constellationId == 'core') {
      return addAppToCore(app);
    }
    final c = constellations.where((item) => item.id == constellationId).firstOrNull;
    if (c == null) return false;
    if (c.apps.length >= maxConstellationApps) return false;

    if (c.isCustom) {
      if (!c.customPackageNames.contains(app.packageName)) {
        c.customPackageNames.add(app.packageName);
      }
    } else {
      final currentList = constellationAppOverrides[constellationId] ??
          c.apps.map((a) => a.packageName).toList();
      if (!currentList.contains(app.packageName)) {
        currentList.add(app.packageName);
      }
      constellationAppOverrides[constellationId] = currentList;
    }
    assignApps(List.from(allApps));
    return true;
  }

  /// Removes an app from a constellation
  void removeAppFromConstellation(String constellationId, String packageName) {
    if (constellationId == 'core') {
      removeAppFromCore(packageName);
      return;
    }
    final c = constellations.where((item) => item.id == constellationId).firstOrNull;
    if (c == null) return;

    if (c.isCustom) {
      c.customPackageNames.remove(packageName);
    } else {
      final currentList = constellationAppOverrides[constellationId] ??
          c.apps.map((a) => a.packageName).toList();
      currentList.remove(packageName);
      constellationAppOverrides[constellationId] = currentList;
    }
    assignApps(List.from(allApps));
  }

  /// Adds an app to the Center Constellation (max 6)
  bool addAppToCore(AppEntry app) {
    final core = constellations.firstWhere((c) => c.id == 'core');
    if (core.apps.any((a) => a.packageName == app.packageName)) {
      return true; // Already in core
    }
    if (core.apps.length >= maxCoreApps) {
      return false; // Max reached
    }
    if (!corePackageNames.contains(app.packageName)) {
      corePackageNames.add(app.packageName);
    }
    assignApps(List.from(allApps));
    return true;
  }

  /// Removes an app from the Center Constellation
  void removeAppFromCore(String packageName) {
    corePackageNames.remove(packageName);
    assignApps(List.from(allApps));
  }

  /// Creates a brand new custom constellation (strictly max 8 apps)
  Constellation createCustomConstellation({
    String? id,
    required String name,
    required Color primaryColor,
    required IconData emblemIcon,
    required List<String> packageNames,
  }) {
    final String constellationId = id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final outerCount = constellations.where((c) => c.id != 'core').length + 1;
    final double angle = ((outerCount - 1) * 2 * math.pi / outerCount) - (math.pi / 2);
    final initialCenter = Offset(math.cos(angle) * 240.0, math.sin(angle) * 195.0);

    final customC = Constellation(
      id: constellationId,
      name: name,
      category: AppCategory.tools, // internal fallback category
      primaryColor: primaryColor,
      secondaryColor: primaryColor.withValues(alpha: 0.7),
      glowColor: primaryColor.withValues(alpha: 0.35),
      emblemIcon: emblemIcon,
      center: initialCenter,
      radius: 140,
      isExpanded: false,
      isCustom: true,
      customPackageNames: List.from(packageNames.take(maxConstellationApps)),
    );

    constellations.add(customC);
    assignApps(List.from(allApps));
    return customC;
  }

  /// Deletes a custom constellation and returns its apps to other sectors
  void deleteConstellation(String id) {
    final index = constellations.indexWhere((c) => c.id == id && c.isCustom);
    if (index != -1) {
      constellations.removeAt(index);
      constellationAppOverrides.remove(id);
      assignApps(List.from(allApps));
    }
  }

  void assignApps(List<AppEntry> apps) {
    allApps.clear();
    allApps.addAll(apps);

    final visibleApps = apps.where((a) => !hiddenPackageNames.contains(a.packageName)).toList();

    for (final c in constellations) {
      c.apps.clear();
    }

    final coreConstellation = constellations.firstWhere((c) => c.id == 'core');

    // 1. Assign Center Constellation apps (strictly max 6 apps)
    if (corePackageNames.isNotEmpty) {
      for (final pkg in corePackageNames) {
        if (hiddenPackageNames.contains(pkg)) continue;
        if (coreConstellation.apps.length >= maxCoreApps) break;
        final match = visibleApps.where((a) => a.packageName == pkg).firstOrNull;
        if (match != null && !coreConstellation.apps.contains(match)) {
          coreConstellation.apps.add(match);
        }
      }
    } else {
      // Default: Top 4 daily essentials
      for (final app in visibleApps) {
        if (coreConstellation.apps.length >= 4) break;
        if (app.category == AppCategory.core && !coreConstellation.apps.contains(app)) {
          coreConstellation.apps.add(app);
        }
      }
    }

    // 2. Assign apps to custom constellations (strictly max 8 apps each)
    final customConstellations = constellations.where((c) => c.isCustom).toList();
    for (final customC in customConstellations) {
      for (final pkg in customC.customPackageNames) {
        if (hiddenPackageNames.contains(pkg)) continue;
        if (customC.apps.length >= maxConstellationApps) break;
        final match = visibleApps.where((a) => a.packageName == pkg).firstOrNull;
        if (match != null && !coreConstellation.apps.contains(match) && !customC.apps.contains(match)) {
          customC.apps.add(match);
        }
      }
    }

    // 3. Assign apps to standard constellations that have overrides (strictly max 8 apps each)
    final standardConstellations = constellations.where((c) => !c.isCustom && c.id != 'core').toList();
    for (final stdC in standardConstellations) {
      if (constellationAppOverrides.containsKey(stdC.id)) {
        final pkgs = constellationAppOverrides[stdC.id]!;
        for (final pkg in pkgs) {
          if (hiddenPackageNames.contains(pkg)) continue;
          if (stdC.apps.length >= maxConstellationApps) break;
          final match = visibleApps.where((a) => a.packageName == pkg).firstOrNull;
          if (match != null &&
              !coreConstellation.apps.contains(match) &&
              !stdC.apps.contains(match) &&
              !customConstellations.any((c) => c.apps.contains(match))) {
            stdC.apps.add(match);
          }
        }
      }
    }

    // 4. Assign remaining apps into category constellations (strictly max 8 apps per constellation)
    for (final app in visibleApps) {
      if (coreConstellation.apps.contains(app)) {
        continue;
      }

      // Check if already assigned to any custom constellation
      bool assigned = false;
      for (final c in customConstellations) {
        if (c.apps.contains(app)) {
          assigned = true;
          break;
        }
      }
      if (assigned) continue;

      // Check if already assigned to any overridden standard constellation
      for (final c in standardConstellations) {
        if (c.apps.contains(app)) {
          assigned = true;
          break;
        }
      }
      if (assigned) continue;

      // For standard constellations without overrides, assign based on app.category if space permits
      Constellation? target = constellations.where(
        (c) =>
            !c.isCustom &&
            c.id != 'core' &&
            c.category == app.category &&
            !constellationAppOverrides.containsKey(c.id) &&
            c.apps.length < maxConstellationApps,
      ).firstOrNull;

      target ??= constellations.where(
        (c) =>
            !c.isCustom &&
            c.id != 'core' &&
            !constellationAppOverrides.containsKey(c.id) &&
            c.apps.length < maxConstellationApps,
      ).firstOrNull;

      if (target != null) {
        target.apps.add(app);
      }
    }

    _layoutAppsInitial();
  }

  void _layoutAppsInitial() {
    for (final c in constellations) {
      final count = c.apps.length;
      if (count == 0) continue;

      if (c.id == 'core') {
        // Dynamic celestial orbital radius based on app count (1 to 6 apps)
        final double coreRadius = count <= 3
            ? 74.0
            : (count == 4 ? 84.0 : 96.0);

        for (int i = 0; i < count; i++) {
          final angle = (i * 2 * math.pi / count) - (math.pi / 2);
          final pos = c.center + Offset(math.cos(angle) * coreRadius, math.sin(angle) * coreRadius);
          c.apps[i].orbitalAngle = angle;
          c.apps[i].orbitalRadius = coreRadius;
          c.apps[i].orbitalSpeed = 0.00015; // Calm, readable orbital cadence
          c.apps[i].basePosition = pos;
          c.apps[i].worldPosition = pos;
        }
      } else {
        // Equidistant ring for outer constellations
        const double ringRadius = 105.0;
        for (int i = 0; i < count; i++) {
          final angle = (i * (2 * math.pi / count)) - (math.pi / 2);
          final pos = c.center + Offset(math.cos(angle) * ringRadius, math.sin(angle) * ringRadius);
          c.apps[i].orbitalAngle = angle;
          c.apps[i].orbitalRadius = ringRadius;
          c.apps[i].orbitalSpeed = 0.0002;
          c.apps[i].basePosition = pos;
          c.apps[i].worldPosition = pos;
        }
      }
    }
  }

  void updateGalaxyMorph({
    required DevicePosture posture,
    required double hingeAngle,
    required double dt,
    Offset? magneticTouchPoint,
  }) {
    // Collect outer constellations (excluding center core)
    final outerConstellations = constellations.where((c) => c.id != 'core').toList();
    final int outerCount = outerConstellations.length;

    for (int k = 0; k < outerConstellations.length; k++) {
      final c = outerConstellations[k];

      // Smooth expansion animation
      final double targetExpansion = c.isExpanded ? 1.0 : 0.0;
      c.expansionProgress += (targetExpansion - c.expansionProgress) * (dt * 9.0).clamp(0.0, 1.0);

      // Target center calculated dynamically based on outerCount and posture
      Offset targetCenter;

      if (posture == DevicePosture.folded) {
        // Vertical stacked elliptical orbit for narrow cover display:
        // Keeps all constellation hubs fully within the screen viewport:
        // With rx = 130.0px, the side hubs (Utilities & Workspace) are centered at ±130px.
        // On a 360-400px wide screen (half-width 180-200px), a 54px pod spans [103px, 157px],
        // comfortably within the viewport borders with >23px of margin.
        // With ry = 240.0px, top and bottom hubs (Connect & Studio) sit at ±240px.
        // Center apps orbit at radius ~58-72px, leaving a clear gap of ~72px (x) and ~180px (y).
        final double angle = (k * 2 * math.pi / outerCount) - (math.pi / 2);
        const double rx = 130.0;
        const double ry = 240.0;
        targetCenter = Offset(math.cos(angle) * rx, math.sin(angle) * ry);
      } else if (posture == DevicePosture.tabletop) {
        // Symmetrical top observation deck and bottom reach
        final double angle = (k * 2 * math.pi / outerCount) - (math.pi / 2);
        const double rx = 165.0;
        const double ry = 220.0;
        targetCenter = Offset(math.cos(angle) * rx, math.sin(angle) * ry + 30.0);
      } else {
        // Expansive equidistant planetary orbits for unfolded display
        final double angle = (k * 2 * math.pi / outerCount) - (math.pi / 2);
        const double rx = 240.0;
        const double ry = 195.0;
        targetCenter = Offset(math.cos(angle) * rx, math.sin(angle) * ry);
      }

      c.center = Offset.lerp(c.center, targetCenter, (dt * 6.0).clamp(0.0, 1.0))!;
      c.rotation += dt * 0.02;

      final double effectiveExpansion = c.expansionProgress;

      for (final app in c.apps) {
        app.orbitalAngle += app.orbitalSpeed * dt * 60;
        final double cosA = math.cos(app.orbitalAngle + c.rotation * 0.1);
        final double sinA = math.sin(app.orbitalAngle + c.rotation * 0.1);

        final double currentRadius = app.orbitalRadius * effectiveExpansion;
        final restingPos = c.center + Offset(cosA * currentRadius, sinA * currentRadius);
        app.basePosition = restingPos;

        Offset finalPos = restingPos;
        if (magneticTouchPoint != null && effectiveExpansion > 0.4) {
          final dist = (magneticTouchPoint - restingPos).distance;
          const magneticRadius = 120.0;
          if (dist < magneticRadius && dist > 1.0) {
            final pull = (1.0 - (dist / magneticRadius)) * 20.0;
            final dir = (magneticTouchPoint - restingPos) / dist;
            finalPos = restingPos + (dir * pull);
          }
        }

        app.worldPosition = Offset.lerp(
          app.worldPosition,
          finalPos,
          (dt * 14.0).clamp(0.0, 1.0),
        )!;
      }
    }

    // Update Core constellation
    final core = constellations.firstWhere((c) => c.id == 'core');
    core.center = Offset.zero;
    core.rotation += dt * 0.02;

    // Smooth expansion animation for Core
    final double targetCoreExpansion = core.isExpanded ? 1.0 : 0.0;
    core.expansionProgress += (targetCoreExpansion - core.expansionProgress) * (dt * 9.0).clamp(0.0, 1.0);

    final int coreCount = core.apps.length;
    final double targetCoreRadius = coreCount <= 3
        ? (posture == DevicePosture.folded ? 58.0 : 74.0)
        : (coreCount == 4
            ? (posture == DevicePosture.folded ? 64.0 : 84.0)
            : (posture == DevicePosture.folded ? 72.0 : 96.0));

    final double effectiveCoreExpansion = core.expansionProgress.clamp(0.0, 1.0);
    // Celestial blooming spiral curve
    final double bloomFactor = Curves.easeOutBack.transform(effectiveCoreExpansion);
    final double spiralAngle = (1.0 - effectiveCoreExpansion) * 0.6;

    for (final app in core.apps) {
      // Smoothly adjust orbitalRadius when posture changes
      app.orbitalRadius = ui.lerpDouble(app.orbitalRadius, targetCoreRadius, (dt * 6.0).clamp(0.0, 1.0)) ?? targetCoreRadius;
      app.orbitalAngle += app.orbitalSpeed * dt * 60;
      final double cosA = math.cos(app.orbitalAngle + core.rotation * 0.1 + spiralAngle);
      final double sinA = math.sin(app.orbitalAngle + core.rotation * 0.1 + spiralAngle);

      final double currentRadius = app.orbitalRadius * bloomFactor;
      final restingPos = core.center + Offset(cosA * currentRadius, sinA * currentRadius);
      app.basePosition = restingPos;

      Offset finalPos = restingPos;
      if (magneticTouchPoint != null && effectiveCoreExpansion > 0.35) {
        final dist = (magneticTouchPoint - restingPos).distance;
        const magneticRadius = 120.0;
        if (dist < magneticRadius && dist > 1.0) {
          final pull = (1.0 - (dist / magneticRadius)) * 20.0;
          final dir = (magneticTouchPoint - restingPos) / dist;
          finalPos = restingPos + (dir * pull);
        }
      }

      app.worldPosition = Offset.lerp(
        app.worldPosition,
        finalPos,
        (dt * 14.0).clamp(0.0, 1.0),
      )!;
    }
  }
}
