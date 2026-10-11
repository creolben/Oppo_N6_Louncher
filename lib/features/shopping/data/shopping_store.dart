import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/launcher_bridge.dart';
import '../models/recipe.dart';
import '../models/shopping_list.dart';

/// Everything persisted by [ShoppingStore].
class ShoppingStoreData {
  final List<ShoppingList> lists;
  final List<Recipe> recipes;
  final String? activeListId;
  final bool preferImperial;

  const ShoppingStoreData({
    this.lists = const [],
    this.recipes = const [],
    this.activeListId,
    this.preferImperial = false,
  });

  Map<String, dynamic> toJson() => {
        'lists': lists.map((list) => list.toJson()).toList(),
        'recipes': recipes.map((recipe) => recipe.toJson()).toList(),
        'activeListId': activeListId,
        'preferImperial': preferImperial,
      };

  factory ShoppingStoreData.fromJson(Map<String, dynamic> json) {
    return ShoppingStoreData(
      lists: (json['lists'] as List? ?? const [])
          .map((list) => ShoppingList.fromJson(
                Map<String, dynamic>.from(list as Map),
              ))
          .toList(),
      recipes: (json['recipes'] as List? ?? const [])
          .map((recipe) => Recipe.fromJson(
                Map<String, dynamic>.from(recipe as Map),
              ))
          .toList(),
      activeListId: json['activeListId'] as String?,
      preferImperial: json['preferImperial'] as bool? ?? false,
    );
  }
}

/// Persists shopping lists and recipes as JSON.
///
/// The production directory comes from [LauncherBridge.getFilesDirPath]; tests
/// inject [directoryPath]. Writes go through a `.tmp` file and an atomic
/// rename. A corrupt store is renamed to `shopping_lists.json.corrupt` and
/// reported as empty so a bad write can never take the launcher down.
class ShoppingStore {
  ShoppingStore({this.directoryPath});

  /// Directory to persist into. Null means the production files directory.
  final String? directoryPath;

  static const String fileName = 'shopping_lists.json';

  Future<Directory?> _directory() async {
    var path = directoryPath;
    path ??= await LauncherBridge.getFilesDirPath();
    if (path == null || path.isEmpty) return null;
    final directory = Directory(path);
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return directory;
  }

  Future<File?> _file() async {
    final directory = await _directory();
    if (directory == null) return null;
    return File('${directory.path}/$fileName');
  }

  /// True when a persisted store file exists.
  Future<bool> get hasStoredData async {
    final file = await _file();
    return file != null && file.existsSync();
  }

  Future<ShoppingStoreData> load() async {
    final file = await _file();
    if (file == null || !file.existsSync()) return const ShoppingStoreData();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('shopping store root is not a JSON object');
      }
      return ShoppingStoreData.fromJson(decoded);
    } catch (error) {
      debugPrint('Shopping store unreadable, backing up: $error');
      await _backupCorrupt(file);
      return const ShoppingStoreData();
    }
  }

  Future<void> save(ShoppingStoreData data) async {
    final file = await _file();
    if (file == null) return;
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data.toJson()), flush: true);
    await temporary.rename(file.path);
  }

  Future<void> _backupCorrupt(File file) async {
    try {
      final backup = File('${file.path}.corrupt');
      if (backup.existsSync()) {
        await backup.delete();
      }
      await file.rename(backup.path);
    } catch (error) {
      debugPrint('Could not back up corrupt shopping store: $error');
    }
  }
}
