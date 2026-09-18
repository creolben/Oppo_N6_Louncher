import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum AppCategory {
  core,
  social,
  productivity,
  entertainment,
  tools,
  games,
}

class AppEntry {
  final String packageName;
  final String? activityName;
  final String label;
  final bool isSystemApp;
  final AppCategory category;
  final Uint8List? iconBytes;
  ui.Image? decodedIcon;
  final IconData fallbackIcon;

  // Cosmic Galaxy Canvas coordinates (in world space)
  Offset worldPosition;
  Offset basePosition; // resting position before magnetic perturbation
  double orbitalAngle;
  double orbitalRadius;
  double orbitalSpeed;
  Color accentColor;
  int notificationCount;

  // Cached TextPainters for butter-smooth 120 FPS rendering without layout thrashing
  TextPainter? labelPainter;
  TextPainter? iconPainter;
  TextPainter? badgePainter;
  int _lastBadgeCount = -1;

  void ensurePainters(double nodeRadius) {
    labelPainter ??= TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.0,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          shadows: [
            Shadow(color: Colors.black, blurRadius: 4.0),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    if (decodedIcon == null) {
      iconPainter ??= TextPainter(
        text: TextSpan(
          text: String.fromCharCode(fallbackIcon.codePoint),
          style: TextStyle(
            fontSize: nodeRadius * 1.15,
            fontFamily: fallbackIcon.fontFamily,
            package: fallbackIcon.fontPackage,
            color: accentColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }

    if (notificationCount > 0 && (_lastBadgeCount != notificationCount || badgePainter == null)) {
      _lastBadgeCount = notificationCount;
      badgePainter = TextPainter(
        text: TextSpan(
          text: '$notificationCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
  }

  AppEntry({
    required this.packageName,
    this.activityName,
    required this.label,
    this.isSystemApp = false,
    this.category = AppCategory.tools,
    this.iconBytes,
    this.decodedIcon,
    this.fallbackIcon = Icons.apps_rounded,
    this.worldPosition = Offset.zero,
    this.basePosition = Offset.zero,
    this.orbitalAngle = 0.0,
    this.orbitalRadius = 100.0,
    this.orbitalSpeed = 0.002,
    this.accentColor = const Color(0xFF64B5F6),
    this.notificationCount = 0,
  });

  AppEntry copyWith({
    String? packageName,
    String? activityName,
    String? label,
    bool? isSystemApp,
    AppCategory? category,
    Uint8List? iconBytes,
    ui.Image? decodedIcon,
    IconData? fallbackIcon,
    Offset? worldPosition,
    Offset? basePosition,
    double? orbitalAngle,
    double? orbitalRadius,
    double? orbitalSpeed,
    Color? accentColor,
    int? notificationCount,
  }) {
    return AppEntry(
      packageName: packageName ?? this.packageName,
      activityName: activityName ?? this.activityName,
      label: label ?? this.label,
      isSystemApp: isSystemApp ?? this.isSystemApp,
      category: category ?? this.category,
      iconBytes: iconBytes ?? this.iconBytes,
      decodedIcon: decodedIcon ?? this.decodedIcon,
      fallbackIcon: fallbackIcon ?? this.fallbackIcon,
      worldPosition: worldPosition ?? this.worldPosition,
      basePosition: basePosition ?? this.basePosition,
      orbitalAngle: orbitalAngle ?? this.orbitalAngle,
      orbitalRadius: orbitalRadius ?? this.orbitalRadius,
      orbitalSpeed: orbitalSpeed ?? this.orbitalSpeed,
      accentColor: accentColor ?? this.accentColor,
      notificationCount: notificationCount ?? this.notificationCount,
    );
  }
}
