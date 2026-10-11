import 'dart:typed_data';

/// One launchable Android app shortcut, as `LauncherApps` reports it.
///
/// This is the public, non-privileged shortcut surface: dynamic, manifest and
/// pinned shortcuts of one package on the current user, resolved only while the
/// launcher holds the platform's host permission. [iconPng] is a PNG rendered at
/// the display density, or null when the icon could not be read — the caller
/// falls back to a generic glyph rather than showing nothing.
class AppShortcut {
  /// The shortcut's stable id within its package.
  final String id;

  /// The package the shortcut belongs to.
  final String packageName;

  /// The app-supplied short label, or an empty string when it has none.
  final String shortLabel;

  /// The app-supplied long label, or an empty string when it has none.
  final String longLabel;

  /// The app's declared ordering rank; lower sorts first.
  final int rank;

  /// Whether the user pinned this shortcut.
  final bool isPinned;

  /// The shortcut icon as PNG bytes, or null when it could not be read.
  final Uint8List? iconPng;

  const AppShortcut({
    required this.id,
    required this.packageName,
    this.shortLabel = '',
    this.longLabel = '',
    this.rank = 0,
    this.isPinned = false,
    this.iconPng,
  });

  /// The label a row shows: the short label, else the long one, else the id.
  String get label =>
      shortLabel.isNotEmpty ? shortLabel : (longLabel.isNotEmpty ? longLabel : id);

  factory AppShortcut.fromMap(Map<String, dynamic> map) {
    return AppShortcut(
      id: map['id'] as String? ?? '',
      packageName: map['packageName'] as String? ?? '',
      shortLabel: map['shortLabel'] as String? ?? '',
      longLabel: map['longLabel'] as String? ?? '',
      rank: (map['rank'] as num?)?.toInt() ?? 0,
      isPinned: map['isPinned'] == true,
      iconPng: map['iconPng'] as Uint8List?,
    );
  }
}
