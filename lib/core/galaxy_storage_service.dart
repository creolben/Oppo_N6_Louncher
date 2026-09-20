import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'launcher_bridge.dart';

class CustomConstellationConfig {
  final String id;
  final String name;
  final int primaryColorValue;
  final int emblemIconCodePoint;
  final List<String> packageNames;

  CustomConstellationConfig({
    required this.id,
    required this.name,
    required this.primaryColorValue,
    required this.emblemIconCodePoint,
    required this.packageNames,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'primaryColorValue': primaryColorValue,
        'emblemIconCodePoint': emblemIconCodePoint,
        'packageNames': packageNames,
      };

  factory CustomConstellationConfig.fromJson(Map<String, dynamic> json) =>
      CustomConstellationConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        primaryColorValue: json['primaryColorValue'] as int? ?? 0xFF00E5FF,
        emblemIconCodePoint: json['emblemIconCodePoint'] as int? ?? Icons.star_rounded.codePoint,
        packageNames: List<String>.from(json['packageNames'] as List? ?? []),
      );

  IconData get icon {
    switch (emblemIconCodePoint) {
      case 0xe0ca:
        return Icons.auto_awesome_rounded;
      case 0xf0118:
        return Icons.rocket_launch_rounded;
      case 0xf01bf:
        return Icons.sports_esports_rounded;
      case 0xf0289:
        return Icons.workspaces_rounded;
      case 0xe25b:
        return Icons.favorite_rounded;
      case 0xe3e0:
        return Icons.menu_book_rounded;
      case 0xe415:
        return Icons.music_note_rounded;
      case 0xe0be:
        return Icons.attach_money_rounded;
      case 0xe130:
        return Icons.camera_alt_rounded;
      case 0xe17a:
        return Icons.code_rounded;
      case 0xe582:
        return Icons.shield_rounded;
      case 0xf0149:
        return Icons.satellite_alt_rounded;
      default:
        // ignore: non_const_argument_for_const_parameter
        return IconData(emblemIconCodePoint, fontFamily: 'MaterialIcons');
    }
  }
}

/// Backwards compatibility alias
typedef CustomGalaxyConfig = CustomConstellationConfig;

class GalaxyStorageService {
  static const String _fileName = 'galaxy_settings.json';

  static Future<File?> _getFile() async {
    try {
      String? dirPath = await LauncherBridge.getFilesDirPath();
      dirPath ??= '/data/user/0/com.launcher.chronofold.mylauncher/files';
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> loadConfig() async {
    try {
      final file = await _getFile();
      if (file != null && file.existsSync()) {
        final content = await file.readAsString();
        return jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error loading galaxy storage: $e');
    }
    return {};
  }

  static Future<void> saveConfig({
    required List<String> coreAppPackageNames,
    List<CustomConstellationConfig>? customConstellations,
    List<CustomGalaxyConfig>? customGalaxies,
    Map<String, List<String>>? constellationAppOverrides,
    List<String>? hiddenPackageNames,
    bool? nativeLauncherMode,
  }) async {
    try {
      final file = await _getFile();
      if (file != null) {
        final constellations = customConstellations ?? customGalaxies ?? [];
        final data = {
          'coreAppPackageNames': coreAppPackageNames,
          'customConstellations': constellations.map((g) => g.toJson()).toList(),
          'customGalaxies': constellations.map((g) => g.toJson()).toList(),
          'constellationAppOverrides': ?constellationAppOverrides,
          'hiddenPackageNames': ?hiddenPackageNames,
          'nativeLauncherMode': ?nativeLauncherMode,
        };
        await file.writeAsString(jsonEncode(data), flush: true);
      }
    } catch (e) {
      debugPrint('Error saving galaxy storage: $e');
    }
  }
}
