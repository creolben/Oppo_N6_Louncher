import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/app_entry.dart';
import '../models/constellation.dart';
import 'foldable_controller.dart';
import 'galaxy_storage_service.dart';
import '../ui/theme/luminous_home_theme.dart';

class GalaxyLayoutEngine {
  static const int maxCoreApps = 8;
  static const int maxConstellationApps = 8;

  /// The Essentials ring radius for [count] apps in [posture].
  ///
  /// One source for both the initial layout and the per-frame morph, so the
  /// two cannot disagree. Up to 6 apps the values are unchanged from before.
  /// 7 and 8 apps widen the ring only when unfolded (112 / 120), which keeps
  /// node spacing without reaching the outer hubs (top hub at y = -195).
  /// Folded and tabletop keep their existing rings: tabletop side hubs sit at
  /// x = +-165, and the folded cover nodes are scaled to 0.76.
  static double coreRingRadius(int count, DevicePosture posture) {
    final bool folded = posture == DevicePosture.folded;
    if (count <= 3) return folded ? 58.0 : 74.0;
    if (count == 4) return folded ? 64.0 : 84.0;
    if (count <= 6 || folded || posture == DevicePosture.tabletop) {
      return folded ? 72.0 : 96.0;
    }
    return count == 7 ? 112.0 : 120.0;
  }

  final List<Constellation> constellations = [];
  final List<AppEntry> allApps = [];

  GalaxyLayoutEngine() {
    _initConstellations();
  }

  void _initConstellations() {
    constellations.clear();
    final core = LuminousHomeTheme.constellationPalette(AppCategory.core);
    final social = LuminousHomeTheme.constellationPalette(AppCategory.social);
    final productivity = LuminousHomeTheme.constellationPalette(
      AppCategory.productivity,
    );
    final media = LuminousHomeTheme.constellationPalette(
      AppCategory.entertainment,
    );
    final tools = LuminousHomeTheme.constellationPalette(AppCategory.tools);
    constellations.addAll([
      Constellation(
        id: 'core',
        name: 'Essentials',
        category: AppCategory.core,
        primaryColor: core.primary,
        secondaryColor: core.secondary,
        glowColor: core.glow,
        emblemIcon: Icons.star_rounded,
        center: Offset.zero,
        radius: 110,
        isExpanded: true,
      ),
      Constellation(
        id: 'social',
        name: 'Connect',
        category: AppCategory.social,
        primaryColor: social.primary,
        secondaryColor: social.secondary,
        glowColor: social.glow,
        emblemIcon: Icons.forum_rounded,
        center: const Offset(-270, -180),
        radius: 140,
        isExpanded: false,
      ),
      Constellation(
        id: 'productivity',
        name: 'Workspace',
        category: AppCategory.productivity,
        primaryColor: productivity.primary,
        secondaryColor: productivity.secondary,
        glowColor: productivity.glow,
        emblemIcon: Icons.workspaces_rounded,
        center: const Offset(270, -180),
        radius: 140,
        isExpanded: false,
      ),
      Constellation(
        id: 'media',
        name: 'Studio',
        category: AppCategory.entertainment,
        primaryColor: media.primary,
        secondaryColor: media.secondary,
        glowColor: media.glow,
        emblemIcon: Icons.play_circle_filled_rounded,
        center: const Offset(-270, 190),
        radius: 140,
        isExpanded: false,
      ),
      Constellation(
        id: 'tools',
        name: 'Utilities',
        category: AppCategory.tools,
        primaryColor: tools.primary,
        secondaryColor: tools.secondary,
        glowColor: tools.glow,
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
            // Membership is the stored package list, not the resolved apps:
            // hidden or temporarily uninstalled packages must survive a save.
            packageNames: List<String>.from(c.customPackageNames),
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

  /// Sets custom core package names (strictly max 8 apps)
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
      // The edited group takes these apps; a copy left in another group's
      // list would paint there as well, or come back later as a stale entry.
      _releaseFromOtherGroups(constellationId, capped);
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

    _releaseFromOtherGroups(constellationId, [app.packageName]);
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

  /// Adds an app to the Center Constellation (max 8)
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

  /// The constellation whose resolved apps list currently contains
  /// [packageName], or null when no sector shows it.
  ///
  /// Only painted membership counts: a package stored in a losing override
  /// list (for example an app that Essentials already owns) is not owned by it.
  Constellation? ownerOf(String packageName) {
    for (final c in constellations) {
      if (c.apps.any((a) => a.packageName == packageName)) return c;
    }
    return null;
  }

  /// Moves [app] into the constellation with id [targetId].
  ///
  /// The package is detached from its current owner and scrubbed from every
  /// other stored membership list, so an entry that no longer shows on the home
  /// screen cannot keep it hidden. Returns false without changing anything when
  /// the target already holds its maximum number of apps.
  bool moveAppToConstellation(String targetId, AppEntry app) {
    final target = constellations.where((c) => c.id == targetId).firstOrNull;
    if (target == null) return false;

    final String packageName = app.packageName;
    if (target.apps.any((a) => a.packageName == packageName)) {
      return true; // Already visible in the target.
    }

    final int limit = targetId == 'core' ? maxCoreApps : maxConstellationApps;
    if (target.apps.length >= limit) return false;

    // Detach from the current owner exactly as the removal editors do.
    final owner = ownerOf(packageName);
    if (owner != null) {
      if (owner.id == 'core') {
        removeAppFromCore(packageName);
      } else {
        removeAppFromConstellation(owner.id, packageName);
      }
    }

    // Scrub any other stored list still holding the package: a stale override
    // would otherwise be resolved back onto the home screen later.
    corePackageNames.remove(packageName);
    for (final c in constellations) {
      if (c.isCustom) {
        c.customPackageNames.remove(packageName);
      } else if (c.id != 'core') {
        final list = constellationAppOverrides[c.id];
        if (list != null) {
          list.remove(packageName);
          if (list.isEmpty) constellationAppOverrides.remove(c.id);
        }
      }
    }

    if (targetId == 'core') {
      if (!corePackageNames.contains(packageName)) {
        corePackageNames.add(packageName);
      }
    } else if (target.isCustom) {
      if (!target.customPackageNames.contains(packageName)) {
        target.customPackageNames.add(packageName);
      }
    } else {
      final currentList = constellationAppOverrides[targetId] ??
          target.apps.map((a) => a.packageName).toList();
      if (!currentList.contains(packageName)) currentList.add(packageName);
      constellationAppOverrides[targetId] = currentList;
    }

    assignApps(List.from(allApps));
    return true;
  }

  /// Creates a brand new custom constellation (strictly max 8 apps).
  ///
  /// Idempotent by [id]: if a custom constellation with that id already exists
  /// its identity (name, colour, emblem and package membership) is replaced and
  /// the same list slot is reused, so callers that apply stored config on every
  /// package-change broadcast cannot append duplicates.
  Constellation createCustomConstellation({
    String? id,
    required String name,
    required Color primaryColor,
    required IconData emblemIcon,
    required List<String> packageNames,
  }) {
    final String constellationId = id ?? 'custom_${DateTime.now().millisecondsSinceEpoch}';
    final cappedPackages = packageNames.take(maxConstellationApps).toList();
    // A group defined with these apps owns them from here on.
    _releaseFromOtherGroups(constellationId, cappedPackages);

    final existingIndex = constellations.indexWhere(
      (c) => c.id == constellationId && c.isCustom,
    );
    if (existingIndex != -1) {
      final existing = constellations[existingIndex];
      final updated = Constellation(
        id: constellationId,
        name: name,
        category: existing.category,
        primaryColor: primaryColor,
        secondaryColor: primaryColor.withValues(alpha: 0.7),
        glowColor: primaryColor.withValues(alpha: 0.35),
        emblemIcon: emblemIcon,
        center: existing.center,
        radius: existing.radius,
        rotation: existing.rotation,
        isExpanded: existing.isExpanded,
        initialProgress: existing.expansionProgress,
        isCustom: true,
        customPackageNames: cappedPackages,
      );
      constellations[existingIndex] = updated;
      assignApps(List.from(allApps));
      return updated;
    }

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
      customPackageNames: cappedPackages,
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

  /// Resolves every visible app into exactly one constellation.
  ///
  /// Priority is Essentials, then custom groups and overridden standard groups
  /// in constellation order, then category auto-fill for standard groups with
  /// no override. Each list used to check only itself, so a package held by two
  /// stored lists was painted in both groups; the per-frame morph then pulled
  /// that one node toward two ring slots and it settled off the ring, between
  /// them, while its slot in the open ring stayed empty. A single claim set
  /// makes double membership impossible, and [_scrubShadowedGroupMemberships]
  /// repairs the stored lists so the resolution is stable across saves.
  void assignApps(List<AppEntry> apps) {
    allApps.clear();
    allApps.addAll(apps);

    final visibleApps = apps.where((a) => !hiddenPackageNames.contains(a.packageName)).toList();

    for (final c in constellations) {
      c.apps.clear();
    }

    final coreConstellation = constellations.firstWhere((c) => c.id == 'core');
    final Set<AppEntry> claimed = <AppEntry>{};

    // Which constellation a stored list entry resolved into, by package. Only
    // list-driven claims (steps 1-3) are recorded: a package can also own a
    // second launcher activity that lands by category in step 4, and that must
    // not read as the list's entry being shadowed.
    final Map<String, Constellation> listOwner = <String, Constellation>{};

    // The visible entry for [pkg], unless some constellation already holds it.
    AppEntry? unclaimed(String pkg) {
      if (hiddenPackageNames.contains(pkg)) return null;
      final match = visibleApps.where((a) => a.packageName == pkg).firstOrNull;
      if (match == null || claimed.contains(match)) return null;
      return match;
    }

    void claim(Constellation c, AppEntry app, {bool fromList = true}) {
      c.apps.add(app);
      claimed.add(app);
      if (fromList) listOwner.putIfAbsent(app.packageName, () => c);
    }

    // 1. Essentials (strictly max 8 apps).
    if (corePackageNames.isNotEmpty) {
      for (final pkg in corePackageNames) {
        if (coreConstellation.apps.length >= maxCoreApps) break;
        final match = unclaimed(pkg);
        if (match != null) claim(coreConstellation, match);
      }
    } else {
      // Default: top 4 daily essentials.
      for (final app in visibleApps) {
        if (coreConstellation.apps.length >= 4) break;
        if (app.category == AppCategory.core && !claimed.contains(app)) {
          claim(coreConstellation, app, fromList: false);
        }
      }
    }

    // 2. Custom groups (strictly max 8 apps each).
    final customConstellations = constellations.where((c) => c.isCustom).toList();
    for (final customC in customConstellations) {
      for (final pkg in customC.customPackageNames) {
        if (customC.apps.length >= maxConstellationApps) break;
        final match = unclaimed(pkg);
        if (match != null) claim(customC, match);
      }
    }

    // 3. Standard groups with an override list (strictly max 8 apps each).
    final standardConstellations = constellations.where((c) => !c.isCustom && c.id != 'core').toList();
    for (final stdC in standardConstellations) {
      final pkgs = constellationAppOverrides[stdC.id];
      if (pkgs == null) continue;
      for (final pkg in pkgs) {
        if (stdC.apps.length >= maxConstellationApps) break;
        final match = unclaimed(pkg);
        if (match != null) claim(stdC, match);
      }
    }

    // 4. Everything else by category, into standard groups without an override.
    for (final app in visibleApps) {
      if (claimed.contains(app)) continue;

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

      if (target != null) claim(target, app, fromList: false);
    }

    _scrubShadowedGroupMemberships(listOwner);
    _layoutAppsInitial();
  }

  /// Drops a package from a group's stored list when a different group's list
  /// won it, so the next save writes lists that agree with the screen.
  ///
  /// [listOwner] is the resolution [assignApps] just made. Essentials is a
  /// pinned shelf, not a group: a package it shows stays in its group's list
  /// so that unpinning returns it there. Only group-versus-group overlap is
  /// repaired, and an entry whose package is hidden or not installed resolved
  /// nowhere, so it is left alone and comes back when the app does.
  void _scrubShadowedGroupMemberships(Map<String, Constellation> listOwner) {
    for (final c in constellations) {
      if (c.id == 'core') continue;
      final List<String>? stored =
          c.isCustom ? c.customPackageNames : constellationAppOverrides[c.id];
      if (stored == null) continue;
      stored.removeWhere((pkg) {
        final owner = listOwner[pkg];
        return owner != null && owner.id != 'core' && !identical(owner, c);
      });
    }
  }

  /// Removes [packageNames] from every group's stored list except [keepId].
  ///
  /// An app shows in one group, so the group being edited takes it. Essentials
  /// is left alone: it pins, it does not own (see
  /// [_scrubShadowedGroupMemberships]).
  void _releaseFromOtherGroups(String keepId, Iterable<String> packageNames) {
    final Set<String> taken = packageNames.toSet();
    if (taken.isEmpty) return;
    for (final c in constellations) {
      if (c.id == 'core' || c.id == keepId) continue;
      if (c.isCustom) {
        c.customPackageNames.removeWhere(taken.contains);
      } else {
        constellationAppOverrides[c.id]?.removeWhere(taken.contains);
      }
    }
  }

  void _layoutAppsInitial() {
    for (final c in constellations) {
      final count = c.apps.length;
      if (count == 0) continue;

      if (c.id == 'core') {
        // Initial ring uses the unfolded radius; updateGalaxyMorph settles it per posture.
        final double coreRadius = coreRingRadius(count, DevicePosture.flat);

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

  /// Snaps every hub, group and node to its resting target in one step.
  ///
  /// For reduce-motion, where no render loop runs to ease the morph: without
  /// this a tapped hub's expansion never advanced, so groups could not open.
  /// Orbits are not advanced, so nothing appears to spin on each change.
  void settleGalaxyMorph({
    required DevicePosture posture,
    required double hingeAngle,
  }) {
    updateGalaxyMorph(
      posture: posture,
      hingeAngle: hingeAngle,
      dt: 1.0,
      advanceOrbits: false,
    );
  }

  void updateGalaxyMorph({
    required DevicePosture posture,
    required double hingeAngle,
    required double dt,
    Offset? magneticTouchPoint,
    bool advanceOrbits = true,
  }) {
    // Orbital drift and ring rotation advance with real time only; a settle
    // (dt = 1, every lerp factor clamped to 1) must not spin the rings.
    final double orbitDt = advanceOrbits ? dt : 0.0;
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
      c.rotation += orbitDt * 0.02;

      final double effectiveExpansion = c.expansionProgress;

      for (final app in c.apps) {
        app.orbitalAngle += app.orbitalSpeed * orbitDt * 60;
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
    final double targetCoreRadius = coreRingRadius(coreCount, posture);

    final double effectiveCoreExpansion = core.expansionProgress.clamp(0.0, 1.0);
    // Celestial blooming spiral curve
    final double bloomFactor = Curves.easeOutBack.transform(effectiveCoreExpansion);
    final double spiralAngle = (1.0 - effectiveCoreExpansion) * 0.6;

    for (final app in core.apps) {
      // Smoothly adjust orbitalRadius when posture changes
      app.orbitalRadius = ui.lerpDouble(app.orbitalRadius, targetCoreRadius, (dt * 6.0).clamp(0.0, 1.0)) ?? targetCoreRadius;
      app.orbitalAngle += app.orbitalSpeed * orbitDt * 60;
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
