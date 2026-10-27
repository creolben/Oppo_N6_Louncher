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

  /// Throws a [TypeError] when `id` or `name` is missing or not a string;
  /// [parseList] skips such entries. Optional fields of the wrong type fall
  /// back to their defaults, and non-string package names are dropped.
  factory CustomConstellationConfig.fromJson(Map<String, dynamic> json) {
    final color = json['primaryColorValue'];
    final emblem = json['emblemIconCodePoint'];
    final packages = json['packageNames'];
    return CustomConstellationConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      primaryColorValue:
          color is int ? color : LuminousHomeTheme.aqua.toARGB32(),
      emblemIconCodePoint:
          emblem is int ? emblem : Icons.star_rounded.codePoint,
      packageNames: packages is List
          ? packages.whereType<String>().toList()
          : <String>[],
    );
  }

  /// Parses a stored constellation list, skipping any entry that cannot be
  /// read. One malformed entry must not take down every other constellation —
  /// or the whole app load with it.
  static List<CustomConstellationConfig> parseList(Object? raw) {
    if (raw is! List) return const [];
    final parsed = <CustomConstellationConfig>[];
    for (final entry in raw) {
      if (entry is! Map<String, dynamic>) continue;
      try {
        parsed.add(CustomConstellationConfig.fromJson(entry));
      } catch (e) {
        debugPrint('Skipping unreadable custom constellation: $e');
      }
    }
    return parsed;
  }

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

  /// Test seam: when set, the settings file lives here instead of in the
  /// platform's files directory. Production never sets it.
  @visibleForTesting
  static Directory? debugStorageDirectory;

  /// Tail of the save queue. Every [saveConfig] is a read-merge-write, so two
  /// running at once could each read the same old file and the later write
  /// would undo the earlier one. Chaining them keeps the merges ordered.
  static Future<void> _saveQueue = Future<void>.value();

  static Future<File?> _getFile() async {
    try {
      // No platform answer (no channel, or a non-Android host) means there is
      // nowhere safe to persist: callers skip persistence rather than guess a
      // package path.
      final String? dirPath =
          debugStorageDirectory?.path ?? await LauncherBridge.getFilesDirPath();
      if (dirPath == null) return null;
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
      await _writeAtomically(target, content);
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
      if (file != null) return await readStored(file);
    } catch (e) {
      debugPrint('Error loading galaxy storage: $e');
    }
    return {};
  }

  /// Reads the stored settings in [file], or an empty object when there is
  /// none.
  ///
  /// A file that exists but does not decode to a JSON object (a write cut
  /// short, say) is moved aside to `<name>.corrupt.<epochMs>` before the empty
  /// object is returned. The next save then starts from defaults, but the
  /// damaged data survives on disk for recovery instead of being silently
  /// overwritten. An I/O failure while reading is rethrown, so a save aborts
  /// rather than replacing a file it could not read.
  @visibleForTesting
  static Future<Map<String, dynamic>> readStored(File file) async {
    if (!file.existsSync()) return {};
    final content = await file.readAsString();
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      debugPrint('Galaxy storage is not valid JSON: $e');
    }
    if (decoded is Map<String, dynamic>) return decoded;
    final backup =
        '${file.path}.corrupt.${DateTime.now().millisecondsSinceEpoch}';
    try {
      await file.rename(backup);
      debugPrint('Unreadable galaxy storage moved to $backup');
    } catch (e) {
      debugPrint('Could not back up unreadable galaxy storage: $e');
      rethrow;
    }
    return {};
  }

  /// Replaces [file] with [content] without ever leaving it half-written: the
  /// bytes go to a sibling `.tmp` file, are flushed, and the temp file is then
  /// renamed over the target, which is atomic on the same filesystem.
  static Future<void> _writeAtomically(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(file.path);
  }

  /// Pure merge of the non-null arguments into [existing].
  ///
  /// A key is only written when its argument is non-null, so a caller that
  /// omits a setting (for example the editors, which do not touch
  /// `nativeLauncherMode`) cannot silently reset it to null. The two legacy
  /// custom-constellation keys are always written together so old and new
  /// readers stay in sync.
  static Map<String, dynamic> mergeConfig(
    Map<String, dynamic> existing, {
    required List<String> coreAppPackageNames,
    List<CustomConstellationConfig>? customConstellations,
    List<CustomGalaxyConfig>? customGalaxies,
    Map<String, List<String>>? constellationAppOverrides,
    List<String>? hiddenPackageNames,
    bool? nativeLauncherMode,
    bool? doubleTapToSleep,
    String? swipeDownAction,
    bool? firstRunHintDismissed,
  }) {
    final data = Map<String, dynamic>.from(existing);
    data['coreAppPackageNames'] = coreAppPackageNames;

    final constellations = customConstellations ?? customGalaxies;
    if (constellations != null) {
      final encoded = constellations.map((g) => g.toJson()).toList();
      data['customConstellations'] = encoded;
      data['customGalaxies'] = encoded;
    }

    if (constellationAppOverrides != null) {
      data['constellationAppOverrides'] = constellationAppOverrides;
    }
    if (hiddenPackageNames != null) {
      data['hiddenPackageNames'] = hiddenPackageNames;
    }
    if (nativeLauncherMode != null) {
      data['nativeLauncherMode'] = nativeLauncherMode;
    }
    // The two gesture preferences. Null means "leave the stored value alone",
    // exactly like every other optional key here, so a save from an editor that
    // never touched gestures cannot reset them.
    if (doubleTapToSleep != null) {
      data['doubleTapToSleep'] = doubleTapToSleep;
    }
    if (swipeDownAction != null) {
      data['swipeDownAction'] = swipeDownAction;
    }
    // Absent in files written before the first-run hint existed; readers treat
    // a missing or non-bool value as "not dismissed yet".
    if (firstRunHintDismissed != null) {
      data['firstRunHintDismissed'] = firstRunHintDismissed;
    }

    return data;
  }

  /// Merges the non-null arguments into the stored settings.
  ///
  /// Saves are serialised: each one runs only after every earlier save has
  /// finished, so callers that fire saves without awaiting them cannot have
  /// one merge undo another.
  static Future<void> saveConfig({
    required List<String> coreAppPackageNames,
    List<CustomConstellationConfig>? customConstellations,
    List<CustomGalaxyConfig>? customGalaxies,
    Map<String, List<String>>? constellationAppOverrides,
    List<String>? hiddenPackageNames,
    bool? nativeLauncherMode,
    bool? doubleTapToSleep,
    String? swipeDownAction,
    bool? firstRunHintDismissed,
  }) {
    final Future<void> save = _saveQueue.then(
      (_) => _saveNow(
        coreAppPackageNames: coreAppPackageNames,
        customConstellations: customConstellations,
        customGalaxies: customGalaxies,
        constellationAppOverrides: constellationAppOverrides,
        hiddenPackageNames: hiddenPackageNames,
        nativeLauncherMode: nativeLauncherMode,
        doubleTapToSleep: doubleTapToSleep,
        swipeDownAction: swipeDownAction,
        firstRunHintDismissed: firstRunHintDismissed,
      ),
    );
    _saveQueue = save;
    return save;
  }

  static Future<void> _saveNow({
    required List<String> coreAppPackageNames,
    List<CustomConstellationConfig>? customConstellations,
    List<CustomGalaxyConfig>? customGalaxies,
    Map<String, List<String>>? constellationAppOverrides,
    List<String>? hiddenPackageNames,
    bool? nativeLauncherMode,
    bool? doubleTapToSleep,
    String? swipeDownAction,
    bool? firstRunHintDismissed,
  }) async {
    try {
      final file = await _getFile();
      if (file != null) {
        final existing = await readStored(file);
        final data = mergeConfig(
          existing,
          coreAppPackageNames: coreAppPackageNames,
          customConstellations: customConstellations,
          customGalaxies: customGalaxies,
          constellationAppOverrides: constellationAppOverrides,
          hiddenPackageNames: hiddenPackageNames,
          nativeLauncherMode: nativeLauncherMode,
          doubleTapToSleep: doubleTapToSleep,
          swipeDownAction: swipeDownAction,
          firstRunHintDismissed: firstRunHintDismissed,
        );
        await _writeAtomically(file, jsonEncode(data));
      }
    } catch (e) {
      debugPrint('Error saving galaxy storage: $e');
    }
  }
}
