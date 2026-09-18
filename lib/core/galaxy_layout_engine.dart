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

  void toggleConstellation(String id) {
    for (final c in constellations) {
      if (c.id == id) {
        c.isExpanded = !c.isExpanded;
      }
    }
  }

  void expandOnly(String id) {
    for (final c in constellations) {
      if (c.id == 'core') continue;
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
        // Symmetrical 4-point compass layout for Essentials
        const double coreRadius = 78.0;
        for (int i = 0; i < count; i++) {
          final angle = (i * 2 * math.pi / count) - (math.pi / 2);
          final pos = c.center + Offset(math.cos(angle) * coreRadius, math.sin(angle) * coreRadius);
          c.apps[i].orbitalAngle = angle;
          c.apps[i].orbitalRadius = coreRadius;
          c.apps[i].orbitalSpeed = 0.0003;
          c.apps[i].basePosition = pos;
          c.apps[i].worldPosition = pos;
        }
      } else {
        // Clean equidistant ring for category apps
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
    for (final c in constellations) {
      // Smooth expansion animation
      final double targetExpansion = c.isExpanded ? 1.0 : 0.0;
      c.expansionProgress += (targetExpansion - c.expansionProgress) * (dt * 9.0).clamp(0.0, 1.0);

      // Target center based on foldable posture
      Offset targetCenter;

      if (posture == DevicePosture.folded) {
        // Structured vertical column for tall, narrow cover screen
        switch (c.id) {
          case 'core':
            targetCenter = Offset.zero;
            break;
          case 'social':
            targetCenter = const Offset(0, -260);
            break;
          case 'productivity':
            targetCenter = const Offset(0, 260);
            break;
          case 'media':
            targetCenter = const Offset(0, -520);
            break;
          case 'tools':
            targetCenter = const Offset(0, 520);
            break;
          default:
            targetCenter = Offset.zero;
        }
      } else if (posture == DevicePosture.tabletop) {
        // Flex mode: Split between top observation and bottom thumb reach
        switch (c.id) {
          case 'core':
            targetCenter = const Offset(0, 180);
            break;
          case 'tools':
            targetCenter = const Offset(200, 210);
            break;
          case 'media':
            targetCenter = const Offset(-200, 210);
            break;
          case 'social':
            targetCenter = const Offset(-210, -190);
            break;
          case 'productivity':
            targetCenter = const Offset(210, -190);
            break;
          default:
            targetCenter = Offset.zero;
        }
      } else {
        // Expansive 4-quadrant layout for unfolded main screen
        switch (c.id) {
          case 'core':
            targetCenter = Offset.zero;
            break;
          case 'social':
            targetCenter = const Offset(-270, -180);
            break;
          case 'productivity':
            targetCenter = const Offset(270, -180);
            break;
          case 'media':
            targetCenter = const Offset(-270, 190);
            break;
          case 'tools':
            targetCenter = const Offset(270, 190);
            break;
          default:
            targetCenter = Offset.zero;
        }
      }

      c.center = Offset.lerp(c.center, targetCenter, (dt * 6.0).clamp(0.0, 1.0))!;
      c.rotation += dt * 0.02; // Very subtle ambient drift

      final double effectiveExpansion = c.id == 'core' ? 1.0 : c.expansionProgress;

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
  }
}
