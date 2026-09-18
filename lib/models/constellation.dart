import 'package:flutter/material.dart';
import 'app_entry.dart';

class Constellation {
  final String id;
  final String name;
  final AppCategory category;
  final Color primaryColor;
  final Color secondaryColor;
  final Color glowColor;
  Offset center;
  double radius;
  double rotation;
  List<AppEntry> apps;

  Constellation({
    required this.id,
    required this.name,
    required this.category,
    required this.primaryColor,
    required this.secondaryColor,
    required this.glowColor,
    required this.center,
    this.radius = 180.0,
    this.rotation = 0.0,
    List<AppEntry>? apps,
  }) : apps = apps ?? [];
}
