import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/app_entry.dart';
import '../models/constellation.dart';
import 'foldable_controller.dart';

class GalaxyLayoutEngine {
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
        name: 'Solar Core',
        category: AppCategory.core,
        primaryColor: const Color(0xFFFFD54F),
        secondaryColor: const Color(0xFFFF8F00),
        glowColor: const Color(0x66FFD54F),
        emblemIcon: Icons.star_rounded,
        center: Offset.zero,
        radius: 125,
        isExpanded: true,
      ),
      Constellation(
        id: 'social',
        name: 'Social Nebula',
        category: AppCategory.social,
        primaryColor: const Color(0xFFF06292),
        secondaryColor: const Color(0xFFAB47BC),
        glowColor: const Color(0x55F06292),
        emblemIcon: Icons.forum_rounded,
        center: const Offset(-320, -180),
        radius: 160,
        isExpanded: false,
      ),
      Constellation(
        id: 'productivity',
        name: 'Productivity Helix',
        category: AppCategory.productivity,
        primaryColor: const Color(0xFF4DD0E1),
        secondaryColor: const Color(0xFF00ACC1),
        glowColor: const Color(0x554DD0E1),
        emblemIcon: Icons.workspaces_rounded,
        center: const Offset(320, -180),
        radius: 160,
        isExpanded: false,
      ),
      Constellation(
        id: 'media',
        name: 'Aurora Media',
        category: AppCategory.entertainment,
        primaryColor: const Color(0xFF81C784),
        secondaryColor: const Color(0xFF388E3C),
        glowColor: const Color(0x5581C784),
        emblemIcon: Icons.play_circle_filled_rounded,
        center: const Offset(-280, 260),
        radius: 160,
        isExpanded: false,
      ),
      Constellation(
        id: 'tools',
        name: 'Utility Forge',
        category: AppCategory.tools,
        primaryColor: const Color(0xFFFFB74D),
        secondaryColor: const Color(0xFFE65100),
        glowColor: const Color(0x55FFB74D),
        emblemIcon: Icons.handyman_rounded,
        center: const Offset(280, 260),
        radius: 160,
        isExpanded: false,
      ),
    ]);
  }

  void toggleConstellation(String id) {
    for (final c in constellations) {
      if (c.id == id) {
        c.isExpanded = !c.isExpanded;
      }
    }
  }

  void expandOnly(String id) {
    for (final c in constellations) {
      if (c.id == 'core') continue; // Core stays accessible
      c.isExpanded = (c.id == id);
    }
  }

  void collapseAllExceptCore() {
    for (final c in constellations) {
      if (c.id != 'core') {
        c.isExpanded = false;
      }
    }
  }

  void assignApps(List<AppEntry> apps) {
    allApps.clear();
    allApps.addAll(apps);

    for (final c in constellations) {
      c.apps.clear();
    }

    for (final app in apps) {
      Constellation target = constellations.firstWhere(
        (c) => c.category == app.category,
        orElse: () => constellations.first,
      );
      target.apps.add(app);
    }

    _layoutAppsInitial();
  }

  void _layoutAppsInitial() {
    for (final c in constellations) {
      final count = c.apps.length;
      if (count == 0) continue;

      if (c.id == 'core') {
        // Solar core apps arranged tightly around center
        for (int i = 0; i < count; i++) {
          final angle = (i * 2 * math.pi / count) - (math.pi / 2);
          final radius = count <= 3 ? 65.0 : 85.0;
          final pos = c.center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
          c.apps[i].orbitalAngle = angle;
          c.apps[i].orbitalRadius = radius;
          c.apps[i].orbitalSpeed = 0.0012 * (i % 2 == 0 ? 1 : -1);
          c.apps[i].basePosition = pos;
          c.apps[i].worldPosition = pos;
        }
      } else {
        // Cluster apps orbit in concentric rings around constellation center
        for (int i = 0; i < count; i++) {
          final ring = (i % 2 == 0) ? 1 : 2;
          final radius = ring == 1 ? 75.0 : 130.0;
          final angle = (i * (2 * math.pi / count)) + (ring * 0.4);
          final pos = c.center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
          c.apps[i].orbitalAngle = angle;
          c.apps[i].orbitalRadius = radius;
          c.apps[i].orbitalSpeed = 0.0008 * (i % 2 == 0 ? 1 : -1);
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
    final double foldFactor = (1.0 - (hingeAngle / 180.0)).clamp(0.0, 1.0);

    for (final c in constellations) {
      // 1. Smooth expansion progress animation (elastic ease-out)
      final double targetExpansion = c.isExpanded ? 1.0 : 0.0;
      c.expansionProgress += (targetExpansion - c.expansionProgress) * (dt * 8.0).clamp(0.0, 1.0);

      // 2. Constellation center morphing based on posture
      Offset targetCenter;

      if (posture == DevicePosture.folded || foldFactor > 0.8) {
        // Linear vertical galaxy filament for narrow outer screen
        switch (c.id) {
          case 'core':
            targetCenter = Offset.zero;
            break;
          case 'social':
            targetCenter = const Offset(0, -300);
            break;
          case 'productivity':
            targetCenter = const Offset(0, 300);
            break;
          case 'media':
            targetCenter = const Offset(0, -600);
            break;
          case 'tools':
            targetCenter = const Offset(0, 600);
            break;
          default:
            targetCenter = Offset.zero;
        }
      } else if (posture == DevicePosture.tabletop) {
        // Flex mode: Top half has observation deck, bottom half has thumb command dock
        switch (c.id) {
          case 'core':
            targetCenter = const Offset(0, 210);
            break;
          case 'tools':
            targetCenter = const Offset(-210, 250);
            break;
          case 'productivity':
            targetCenter = const Offset(210, 250);
            break;
          case 'social':
            targetCenter = const Offset(-230, -210);
            break;
          case 'media':
            targetCenter = const Offset(230, -210);
            break;
          default:
            targetCenter = Offset.zero;
        }
      } else {
        // Fully opened expansive galactic spiral
        switch (c.id) {
          case 'core':
            targetCenter = Offset.zero;
            break;
          case 'social':
            targetCenter = const Offset(-330, -190);
            break;
          case 'productivity':
            targetCenter = const Offset(330, -190);
            break;
          case 'media':
            targetCenter = const Offset(-290, 270);
            break;
          case 'tools':
            targetCenter = const Offset(290, 270);
            break;
          default:
            targetCenter = Offset.zero;
        }
      }

      // Smooth interpolation to target center
      c.center = Offset.lerp(c.center, targetCenter, (dt * 5.0).clamp(0.0, 1.0))!;
      c.rotation += dt * 0.04;

      // 3. Update apps inside constellation
      // When collapsed, effective radius shrinks down to center orb!
      final double effectiveExpansion = c.id == 'core' ? 1.0 : c.expansionProgress;

      for (final app in c.apps) {
        app.orbitalAngle += app.orbitalSpeed * dt * 60;

        final double cosA = math.cos(app.orbitalAngle + c.rotation * 0.2);
        final double sinA = math.sin(app.orbitalAngle + c.rotation * 0.2);

        // Radius scales with expansion progress
        final double currentRadius = app.orbitalRadius * effectiveExpansion;
        final restingPos = c.center + Offset(cosA * currentRadius, sinA * currentRadius);
        app.basePosition = restingPos;

        // Magnetic perturbation if finger is dragging near app
        Offset finalPos = restingPos;
        if (magneticTouchPoint != null && effectiveExpansion > 0.4) {
          final dist = (magneticTouchPoint - restingPos).distance;
          const magneticRadius = 140.0;
          if (dist < magneticRadius && dist > 1.0) {
            final pull = (1.0 - (dist / magneticRadius)) * 28.0;
            final dir = (magneticTouchPoint - restingPos) / dist;
            finalPos = restingPos + (dir * pull);
          }
        }

        // Smoothly settle towards final position
        app.worldPosition = Offset.lerp(
          app.worldPosition,
          finalPos,
          (dt * 12.0).clamp(0.0, 1.0),
        )!;
      }
    }
  }
}
