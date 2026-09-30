import 'dart:ui' show Color;

/// The device's Material You tonal palette, as ColorOS reports it on Android 12+.
///
/// Native sends a nested map: one entry per tonal group (`accent1`, `accent2`,
/// `accent3`, `neutral1`, `neutral2`) whose keys are the Material tone numbers
/// as strings (`"0"` through `"1000"`), plus a `"source"` marker. This parses
/// that into something the theme can ask by tone, and refuses anything it does
/// not recognise rather than half-reading it.
///
/// The palette is deliberately read-only and value-equal: the theme caches the
/// accent it produced, and a re-read that resolves to the same tones must not
/// count as a change.
class SystemPalette {
  /// The tonal groups, in the order the native side writes them.
  static const List<String> _groupNames = <String>[
    'accent1',
    'accent2',
    'accent3',
    'neutral1',
    'neutral2',
  ];

  /// Tones that are guaranteed opaque; a missing one is a legitimate null.
  final Map<String, Map<String, int>> _groups;

  SystemPalette._(this._groups);

  /// Parses a native palette map, or returns null when it is missing,
  /// malformed or has no `accent1` group to theme from.
  ///
  /// A missing *tone* is not malformed — the lookup simply returns null — but a
  /// group that is not a map, or a map with no usable `accent1`, is refused so
  /// the theme falls back rather than deriving an accent from noise.
  static SystemPalette? fromMap(dynamic map) {
    if (map is! Map) return null;
    final Map<String, Map<String, int>> groups = <String, Map<String, int>>{};
    for (final String name in _groupNames) {
      final dynamic raw = map[name];
      if (raw == null) continue;
      if (raw is! Map) return null;
      final Map<String, int> tones = <String, int>{};
      raw.forEach((dynamic key, dynamic value) {
        if (key is String && value is int) tones[key] = value;
      });
      if (tones.isNotEmpty) {
        groups[name] = Map<String, int>.unmodifiable(tones);
      }
    }
    if (!groups.containsKey('accent1')) return null;
    return SystemPalette._(Map<String, Map<String, int>>.unmodifiable(groups));
  }

  int? _argb(String group, int tone) => _groups[group]?['$tone'];

  Color? _color(String group, int tone) {
    final int? argb = _argb(group, tone);
    return argb == null ? null : Color(argb);
  }

  /// The tone at [tone] in the primary Material You accent ramp.
  Color? accent1(int tone) => _color('accent1', tone);

  /// The tone at [tone] in the secondary accent ramp.
  Color? accent2(int tone) => _color('accent2', tone);

  /// The tone at [tone] in the tertiary accent ramp.
  Color? accent3(int tone) => _color('accent3', tone);

  /// The tone at [tone] in the first neutral ramp.
  Color? neutral1(int tone) => _color('neutral1', tone);

  /// The tone at [tone] in the second neutral ramp.
  Color? neutral2(int tone) => _color('neutral2', tone);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SystemPalette) return false;
    return _sameGroups(_groups, other._groups);
  }

  static bool _sameGroups(
    Map<String, Map<String, int>> a,
    Map<String, Map<String, int>> b,
  ) {
    if (a.length != b.length) return false;
    for (final MapEntry<String, Map<String, int>> entry in a.entries) {
      final Map<String, int>? otherGroup = b[entry.key];
      if (otherGroup == null || otherGroup.length != entry.value.length) {
        return false;
      }
      for (final MapEntry<String, int> tone in entry.value.entries) {
        if (otherGroup[tone.key] != tone.value) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    final List<Object> flat = <Object>[];
    for (final String name in _groupNames) {
      final Map<String, int>? tones = _groups[name];
      if (tones == null) continue;
      for (final MapEntry<String, int> tone in tones.entries) {
        flat.add(name);
        flat.add(tone.key);
        flat.add(tone.value);
      }
    }
    return Object.hashAll(flat);
  }
}
