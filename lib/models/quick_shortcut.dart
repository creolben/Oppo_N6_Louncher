/// A lock-screen quick shortcut, named by the role it plays rather than by the
/// package that happens to implement it.
///
/// Lives with the shared models because both the lock screen and the platform
/// bridge name these roles, and `lib/core` does not depend on `lib/features`.
enum QuickShortcut {
  phone,
  camera;

  /// Human-readable name, used in the fallback diagnostic shown on screen.
  String get label => this == QuickShortcut.phone ? 'Phone' : 'Camera';

  /// Wire name used on the method channel.
  String get channelName => name;
}
