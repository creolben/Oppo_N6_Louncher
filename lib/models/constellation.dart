import 'package:flutter/material.dart';
import 'app_entry.dart';

class Constellation {
  final String id;
  final String name;
  final AppCategory category;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  final IconData emblemIcon;
  Offset center;
  double radius;
  double rotation;
  List<AppEntry> apps;

  // Expansion State: 0.0 (condensed celestial orb) to 1.0 (fully bloomed ring of apps)
  bool isExpanded;
  double expansionProgress;

  TextPainter? titlePainter;
  TextPainter? countBadgePainter;
  TextPainter? iconPainter;
  final bool isCustom;
  final List<String> customPackageNames;
  int _lastAppCount = -1;

  void invalidatePainters() {
    titlePainter = null;
    countBadgePainter = null;
    iconPainter = null;
    _lastAppCount = -1;
  }

  /// The system text scale the cached title and badge were laid out at.
  TextScaler _painterScaler = TextScaler.noScaling;

  /// Lays out the cached painters for this constellation.
  ///
  /// [textScaler] is the ambient system text scale. The title and app-count
  /// badge are words the user reads, so they follow it; the emblem glyph is
  /// sized to the pod and deliberately does not.
  void ensurePainters({TextScaler textScaler = TextScaler.noScaling}) {
    if (_painterScaler != textScaler) {
      _painterScaler = textScaler;
      titlePainter = null;
      countBadgePainter = null;
      _lastAppCount = -1;
    }

    titlePainter ??= TextPainter(
      text: TextSpan(
        text: name.toUpperCase(),
        style: TextStyle(
          color: primaryColor.withValues(alpha: 0.85),
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
          shadows: [
            Shadow(
              color: primaryColor.withValues(alpha: 0.8),
              blurRadius: 8.0,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();

    if (_lastAppCount != apps.length || countBadgePainter == null) {
      _lastAppCount = apps.length;
      countBadgePainter = TextPainter(
        text: TextSpan(
          text: '${apps.length} stars',
          style: TextStyle(
            color: primaryColor.withValues(alpha: 0.7),
            fontSize: 9.0,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
    }

    iconPainter ??= TextPainter(
      text: TextSpan(
        text: String.fromCharCode(emblemIcon.codePoint),
        style: TextStyle(
          fontSize: 22.0,
          fontFamily: emblemIcon.fontFamily,
          package: emblemIcon.fontPackage,
          color: primaryColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  Constellation({
    required this.id,
    required this.name,
    required this.category,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.center,
    this.emblemIcon = Icons.auto_awesome_rounded,
    this.radius = 160.0,
    this.rotation = 0.0,
    this.isExpanded = false,
    this.isCustom = false,
    List<String>? customPackageNames,
    double? initialProgress,
    List<AppEntry>? apps,
  })  : customPackageNames = customPackageNames ?? [],
        expansionProgress = initialProgress ?? (isExpanded ? 1.0 : 0.0),
        apps = apps ?? [];
}
