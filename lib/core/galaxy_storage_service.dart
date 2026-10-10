import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../ui/theme/luminous_home_theme.dart';
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
        primaryColorValue:
            json['primaryColorValue'] as int? ??
            LuminousHomeTheme.aqua.toARGB32(),
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
        // Every codepoint the emblem picker can produce is handled above, so
        // this is only reached by stored data from outside that set. Building an
        // IconData from a runtime codepoint here would force the whole
        // MaterialIcons font (1.6MB) into the bundle, because the compiler can
        // no longer prove which glyphs are reachable.
        return Icons.star_rounded;
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

  static const String _importDirName = 'import';

  /// One-shot settings import, for reinstalls of release (non-debuggable)
  /// builds where `run-as` cannot reach internal storage:
  ///
  ///   adb push galaxy_settings.json \
  ///     /sdcard/Android/data/com.launcher.chronofold.mylauncher/files/import/
  ///
  /// Only adb/shell and this app can write that directory. The file is applied
  /// on the next launch and then removed.
  static Future<bool> importPendingConfig() async {
    final ext = await LauncherBridge.getExternalFilesDirPath();
    if (ext == null) return false;
    // Create the drop box as the app's own uid. If `adb push` creates it
    // instead, it is owned by `shell` (drwxrws--- ext_data_rw), the app cannot
    // open it, and the import is silently skipped. Created here, it is owned by
    // the app with group ext_data_rw, so adb shell can still write into it.
    try {
      final dir = Directory('$ext/$_importDirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } catch (e) {
      debugPrint('Galaxy settings import dir unavailable: $e');
    }
    final target = await _getFile();
    if (target == null) return false;
    return applyPendingImport(File('$ext/$_importDirName/$_fileName'), target);
  }

  /// Copies [source] over [target] if it holds a JSON object. The previous
  /// target is kept as `<name>.pre-import`; an invalid source is renamed to
  /// `<name>.rejected` so it is not retried on every launch.
  static Future<bool> applyPendingImport(File source, File target) async {
    if (!source.existsSync()) return false;
    try {
      final content = await source.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('settings import is not a JSON object');
      }
      if (target.existsSync()) {
        await target.copy('${target.path}.pre-import');
      }
      await target.writeAsString(content, flush: true);
      await source.delete();
      debugPrint('Galaxy settings import applied');
      return true;
    } catch (e) {
      debugPrint('Galaxy settings import rejected: $e');
      try {
        await source.rename('${source.path}.rejected');
      } catch (_) {}
      return false;
    }
  }

  static Future<Map<String, dynamic>> loadConfig() async {
    try {
      await importPendingConfig();
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
