import '../../models/app_entry.dart';
import '../../models/quick_shortcut.dart';

/// Picks the installed app that fills a lock-screen shortcut role.
///
/// Package names are not portable, so nothing here matches a package exactly.
/// Verified against the Find N6 (CPH2765, ColorOS 16) app list, where the two
/// shortcuts are:
///
///  * phone — `com.android.contacts/.DialtactsActivityAlias`, labelled "Phone".
///    Note the package also publishes `.PeopleActivityAlias` labelled
///    "Contacts", so the package name alone is ambiguous and the activity name
///    is what identifies the dialer.
///  * camera — `com.oplus.camera/.Camera`, labelled "Camera".
///
/// The names a launcher must *not* pick are just as important: this device
/// ships `com.oplus.phonemanager`, `com.paybyphone` and
/// `com.android.cameraextensions`, all of which contain a shortcut keyword.
///
/// Returning `null` is a valid, expected answer — callers must fall back to a
/// platform intent rather than launching something arbitrary.
class QuickShortcutResolver {
  const QuickShortcutResolver._();

  /// The best app for [shortcut], or null when the list holds no match.
  static AppEntry? resolve(QuickShortcut shortcut, List<AppEntry> apps) {
    return switch (shortcut) {
      QuickShortcut.phone => phone(apps),
      QuickShortcut.camera => camera(apps),
    };
  }

  /// The dialer, i.e. the app that answers `ACTION_DIAL`.
  static AppEntry? phone(List<AppEntry> apps) =>
      _best(apps, _phoneScore);

  /// The camera app.
  static AppEntry? camera(List<AppEntry> apps) =>
      _best(apps, _cameraScore);

  static AppEntry? _best(List<AppEntry> apps, int Function(AppEntry) score) {
    AppEntry? best;
    var bestScore = 0; // A non-positive score is not a match.
    for (final app in apps) {
      final value = score(app);
      if (value > bestScore) {
        bestScore = value;
        best = app;
      }
    }
    return best;
  }

  /// Packages whose names contain a shortcut keyword without being that app.
  /// Scored as a hard disqualification: no amount of keyword overlap should
  /// let a "Phone Manager" or a camera plug-in win.
  static const List<String> _phoneDecoys = [
    'paybyphone',
    'phonemanager',
    'phoneclone',
    'phonecleaner',
    'phoneassistant',
    'phoneoverlay',
    'auto_generated',
    'overlay',
    'config',
  ];

  static const List<String> _cameraDecoys = [
    'cameraextensions',
    'engineercamera',
    'cameraoverlay',
    'cameraconfig',
    'overlay',
    'config',
  ];

  static int _phoneScore(AppEntry app) {
    final pkg = app.packageName.toLowerCase();
    final activity = (app.activityName ?? '').toLowerCase();
    final label = app.label.toLowerCase();

    if (_phoneDecoys.any(pkg.contains)) return -1;

    var score = 0;

    // The activity name is the most portable signal: the dialer is the
    // component registered for ACTION_DIAL, and it carries that in its name on
    // AOSP (DialtactsActivityAlias), Pixel (dialer.main.impl.MainActivity) and
    // OEM builds alike.
    if (activity.contains('dial')) score += 100;
    if (pkg.contains('dialer')) score += 90;

    if (label == 'phone') score += 60;
    // `.phone` as a whole segment, so `com.oplus.phone` counts but
    // `com.oplus.phonemanager` (already excluded) never reaches here.
    if (pkg.endsWith('.phone') || pkg.contains('.phone.')) score += 40;

    // The contacts alias shares the dialer's package, so it has to be pushed
    // below it explicitly rather than left to tie-break.
    if (activity.contains('people')) score -= 120;
    if (activity.contains('contact') && !activity.contains('dial')) score -= 80;
    if (label == 'contacts') score -= 60;

    return score;
  }

  static int _cameraScore(AppEntry app) {
    final pkg = app.packageName.toLowerCase();
    final activity = (app.activityName ?? '').toLowerCase();
    final label = app.label.toLowerCase();

    if (_cameraDecoys.any(pkg.contains)) return -1;

    var score = 0;

    if (pkg.contains('camera')) score += 90;
    if (label == 'camera') score += 60;
    if (activity.contains('camera')) score += 40;

    // A gallery or photo editor is not the camera.
    if (label.contains('gallery') || pkg.contains('gallery')) score -= 80;
    if (label.contains('photo') || pkg.contains('photo')) score -= 40;

    return score;
  }
}
