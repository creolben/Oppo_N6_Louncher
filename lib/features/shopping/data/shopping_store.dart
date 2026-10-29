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

  /// Remembered `normalizedName -> aisle` choices. Stores written before this
  /// field existed load as an empty map.
  final Map<String, String> aisleMemory;

  /// Whether the surface should open in the larger, touch-friendly store mode.
  /// Stores written before this field existed load as `false`.
  final bool storeMode;

  /// Whether the user dismissed the cover-display store-mode suggestion.
  /// Stores written before this field existed load as `false`.
  final bool storeModeHintDismissed;

  /// How many malformed lists, recipes or items were skipped while parsing.
  /// Never persisted; [ShoppingStore.load] uses it to keep a backup.
  final int skippedEntries;

  const ShoppingStoreData({
    this.lists = const [],
    this.recipes = const [],
    this.activeListId,
    this.preferImperial = false,
    this.aisleMemory = const <String, String>{},
    this.storeMode = false,
    this.storeModeHintDismissed = false,
    this.skippedEntries = 0,
  });

  Map<String, dynamic> toJson() => {
        'lists': lists.map((list) => list.toJson()).toList(),
        'recipes': recipes.map((recipe) => recipe.toJson()).toList(),
        'activeListId': activeListId,
        'preferImperial': preferImperial,
        'aisleMemory': aisleMemory,
        'storeMode': storeMode,
        'storeModeHintDismissed': storeModeHintDismissed,
      };

  /// Parses the store leniently: each list, item and recipe is parsed on its
  /// own, so one malformed entry is dropped (and counted in [skippedEntries])
  /// instead of discarding the whole file.
  factory ShoppingStoreData.fromJson(Map<String, dynamic> json) {
    var skipped = 0;
    void skip(Object error) {
      skipped += 1;
      debugPrint('Shopping store entry skipped: $error');
    }

    final lists = <ShoppingList>[];
    for (final raw in json['lists'] as List? ?? const []) {
      try {
        lists.add(
          ShoppingList.fromJson(
            Map<String, dynamic>.from(raw as Map),
            onSkippedItem: skip,
          ),
        );
      } catch (error) {
        skip(error);
      }
    }
    final recipes = <Recipe>[];
    for (final raw in json['recipes'] as List? ?? const []) {
      try {
        recipes.add(Recipe.fromJson(Map<String, dynamic>.from(raw as Map)));
      } catch (error) {
        skip(error);
      }
    }
    final Object? rawMemory = json['aisleMemory'];
    final Object? activeListId = json['activeListId'];
    return ShoppingStoreData(
      lists: lists,
      recipes: recipes,
      activeListId: activeListId is String ? activeListId : null,
      preferImperial: json['preferImperial'] == true,
      aisleMemory: rawMemory is Map
          ? <String, String>{
              for (final entry in rawMemory.entries)
                entry.key.toString(): entry.value.toString(),
            }
          : const <String, String>{},
      storeMode: json['storeMode'] == true,
      storeModeHintDismissed: json['storeModeHintDismissed'] == true,
      skippedEntries: skipped,
    );
  }
}

/// Persists shopping lists and recipes as JSON.
///
/// The production directory comes from [LauncherBridge.getFilesDirPath]; tests
/// inject [directoryPath]. Each write goes through its own `.tmp` file and an
/// atomic rename, and a write that finishes after a newer one has already
/// landed is discarded, so overlapping saves never clobber each other or the
/// newest state. A corrupt store is renamed to
/// `shopping_lists.json.corrupt.<epochMs>` and reported as empty so a bad write
/// can never take the launcher down; a store with only some malformed entries
/// loads the rest and keeps a copy under the same name.
class ShoppingStore {
  ShoppingStore({this.directoryPath});

  /// Directory to persist into. Null means the production files directory.
  final String? directoryPath;

  static const String fileName = 'shopping_lists.json';

  /// Sequence of the last save started and the last one renamed into place.
  int _startedWrites = 0;
  int _committedWrite = 0;

  /// Saves currently between their first await and their rename.
  int _writesInFlight = 0;

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
    if (file == null) return const ShoppingStoreData();
    if (_writesInFlight == 0) _deleteStaleTemporaries(file);
    if (!file.existsSync()) return const ShoppingStoreData();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('shopping store root is not a JSON object');
      }
      final data = ShoppingStoreData.fromJson(decoded);
      if (data.skippedEntries > 0) {
        await _backupCorrupt(file, keepOriginal: true);
      }
      return data;
    } catch (error) {
      debugPrint('Shopping store unreadable, backing up: $error');
      await _backupCorrupt(file);
      return const ShoppingStoreData();
    }
  }

  /// Writes [data]. The JSON is encoded before the first await, so the file
  /// always reflects the state at the moment of the call.
  Future<void> save(ShoppingStoreData data) async {
    final int sequence = ++_startedWrites;
    final String encoded = jsonEncode(data.toJson());
    _writesInFlight += 1;
    try {
      await _writeSequenced(sequence, encoded);
    } finally {
      _writesInFlight -= 1;
    }
  }

  Future<void> _writeSequenced(int sequence, String encoded) async {
    final file = await _file();
    if (file == null) return;
    final temporary = File('${file.path}.$sequence.tmp');
    try {
      await temporary.writeAsString(encoded, flush: true);
      if (sequence < _committedWrite) {
        // A newer save already landed; this snapshot is stale.
        temporary.deleteSync();
        return;
      }
      // Synchronous so the newer-wins check and the rename cannot interleave
      // with another save's.
      temporary.renameSync(file.path);
      _committedWrite = sequence;
    } catch (error) {
      try {
        if (temporary.existsSync()) temporary.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  /// Removes `.tmp` files left behind by a write that never finished.
  void _deleteStaleTemporaries(File file) {
    try {
      final String prefix = '${file.uri.pathSegments.last}.';
      for (final entity in file.parent.listSync()) {
        final String name = entity.uri.pathSegments.last;
        if (entity is File && name.startsWith(prefix) && name.endsWith('.tmp')) {
          entity.deleteSync();
        }
      }
    } catch (error) {
      debugPrint('Could not clean shopping store temporaries: $error');
    }
  }

  /// Moves (or, with [keepOriginal], copies) [file] to a timestamped
  /// `.corrupt.<epochMs>` backup so repeated failures never overwrite an
  /// earlier backup.
  Future<void> _backupCorrupt(File file, {bool keepOriginal = false}) async {
    try {
      final int stamp = DateTime.now().millisecondsSinceEpoch;
      var backupPath = '${file.path}.corrupt.$stamp';
      for (var n = 1; File(backupPath).existsSync(); n++) {
        backupPath = '${file.path}.corrupt.$stamp-$n';
      }
      if (keepOriginal) {
        await file.copy(backupPath);
      } else {
        await file.rename(backupPath);
      }
    } catch (error) {
      debugPrint('Could not back up corrupt shopping store: $error');
    }
  }
}
