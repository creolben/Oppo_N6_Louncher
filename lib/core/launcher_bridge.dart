import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_entry.dart';
import '../models/app_shortcut.dart';
import '../models/now_playing.dart';
import '../models/quick_shortcut.dart';
import '../ui/theme/luminous_home_theme.dart';
import '../ui/theme/system_palette.dart';
import '../ui/theme/wallpaper_tone.dart';

class LauncherBridge {  static const MethodChannel _appsChannel =
      MethodChannel('com.launcher.chronofold/apps');
  static const EventChannel _fingerprintChannel =
      EventChannel('com.launcher.chronofold/fingerprint');
  static const EventChannel _mediaChannel =
      EventChannel('com.launcher.chronofold/media');
  static const EventChannel _badgesChannel =
      EventChannel('com.launcher.chronofold/badges');

  /// Test seam: on a host that is not Android (the unit-test binary on a
  /// desktop) the bridge normally never touches the platform channel. A test
  /// that asserts the exact channel payload sets this so the same code path
  /// runs; production never does.
  @visibleForTesting
  static bool debugUsePlatformChannels = false;

  /// Whether the platform channels should be used on this host.
  static bool get _usePlatformChannels =>
      !kIsWeb && (Platform.isAndroid || debugUsePlatformChannels);

  static Stream<NowPlaying?>? _mediaStream;
  static Stream<Map<String, dynamic>>? _badgesStream;

  /// Broadcasts the native `onSystemPaletteChanged` pushes. Broadcast so the
  /// launcher's bootstrap and a future second surface can both listen, and so
  /// a missed event before the first listener cannot queue up a stale palette.
  static final StreamController<SystemPalette?> _systemPaletteController =
      StreamController<SystemPalette?>.broadcast();

  /// Broadcasts the native `onWallpaperToneChanged` pushes, one per real
  /// wallpaper change while the launcher runs.
  static final StreamController<WallpaperTone?> _wallpaperToneController =
      StreamController<WallpaperTone?>.broadcast();

  static VoidCallback? _onLockScreenListener;
  static VoidCallback? _onPackageChangeListener;
  static VoidCallback? _onHomeButtonListener;
  static VoidCallback? _onScreenOnListener;
  static VoidCallback? _onUserPresentListener;
  static VoidCallback? _onRequestFrameListener;
  static void Function(String path)? _onSharedPdfListener;
  static bool _handlerInitialized = false;

  static void _ensureHandlerInitialized() {
    if (_handlerInitialized) return;
    _handlerInitialized = true;
    _appsChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'lockScreen':
          _onLockScreenListener?.call();
          break;
        case 'onPackagesChanged':
          _onPackageChangeListener?.call();
          break;
        case 'onHomePressed':
          _onHomeButtonListener?.call();
          break;
        case 'screenOn':
          _onScreenOnListener?.call();
          break;
        case 'userPresent':
          _onUserPresentListener?.call();
          break;
        case 'requestFrame':
          _onRequestFrameListener?.call();
          break;
        case 'onSystemPaletteChanged':
          _systemPaletteController.add(SystemPalette.fromMap(call.arguments));
          break;
        case 'onWallpaperToneChanged':
          _wallpaperToneController.add(WallpaperTone.fromMap(call.arguments));
          break;
        case 'onSharedPdf':
          final Object? args = call.arguments;
          if (args is Map) {
            final Object? path = args['path'];
            if (path is String && path.isNotEmpty) {
              _onSharedPdfListener?.call(path);
            }
          }
          break;
      }
    });
  }

  static void setScreenLockListener(VoidCallback onLock) {
    _onLockScreenListener = onLock;
    _ensureHandlerInitialized();
  }

  /// Fires when the platform reports an unlock that followed a genuinely
  /// locked keyguard, i.e. it authenticated someone. The launcher's lock
  /// overlay clears on this, because covering the keyguard means the reader
  /// answers to the platform rather than to this app.
  static void setUserPresentListener(VoidCallback? onUserPresent) {
    _onUserPresentListener = onUserPresent;
    _ensureHandlerInitialized();
  }

  /// Clears the user-present listener only if it is still [owner].
  ///
  /// A lock panel that is being disposed must not clear the listener a newer
  /// panel has already installed, or that panel never hears the unlock.
  static void clearUserPresentListener(VoidCallback owner) {
    if (_onUserPresentListener == owner) _onUserPresentListener = null;
  }

  @visibleForTesting
  static void dispatchUserPresentForTesting() {
    _onUserPresentListener?.call();
  }

  /// Fires when the native lock surface needs a frame it can present.
  ///
  /// The lock activity can be RESUMED and top-most while its window is still
  /// `DRAW_PENDING`: the framework installs a pre-draw gate that opens only on
  /// `onFlutterUiDisplayed`, and a surface that produced no frame before the
  /// display went off has nothing scheduling one on wake. The native side asks
  /// here, and the lock surface answers with a forced frame.
  static void setRequestFrameListener(VoidCallback? onRequestFrame) {
    _onRequestFrameListener = onRequestFrame;
    _ensureHandlerInitialized();
  }

  @visibleForTesting
  static void dispatchRequestFrameForTesting() {
    _onRequestFrameListener?.call();
  }

  /// Fires when the panel turns on, i.e. the moment the platform will let an
  /// app hold the fingerprint reader again.
  static void setScreenOnListener(VoidCallback? onScreenOn) {
    _onScreenOnListener = onScreenOn;
    _ensureHandlerInitialized();
  }

  /// Clears the screen-on listener only if it is still [owner]; see
  /// [clearUserPresentListener].
  static void clearScreenOnListener(VoidCallback owner) {
    if (_onScreenOnListener == owner) _onScreenOnListener = null;
  }

  static void setPackageChangeListener(VoidCallback onPackageChange) {
    _onPackageChangeListener = onPackageChange;
    _ensureHandlerInitialized();
  }

  static void setHomeButtonListener(VoidCallback onHomePressed) {
    _onHomeButtonListener = onHomePressed;
    _ensureHandlerInitialized();
  }

  /// Receives the path of a PDF handed to the launcher from the share sheet or
  /// "Open with". The native side copies the URI into its cache first, so the
  /// path is a private file the launcher can read directly.
  static void setSharedPdfListener(void Function(String path) onSharedPdf) {
    _onSharedPdfListener = onSharedPdf;
    _ensureHandlerInitialized();
  }

  @visibleForTesting
  static void dispatchSharedPdfForTesting(String path) {
    _onSharedPdfListener?.call(path);
  }



  /// Fetches installed apps from Android native PackageManager, or returns
  /// rich mock apps on a non-Android host (desktop, tests).
  ///
  /// On Android a failed or empty scan returns null rather than the mocks:
  /// callers keep the inventory they already have instead of showing fake apps
  /// with fake badges to a real user.
  static Future<List<AppEntry>?> getInstalledApps({bool includeIcons = true}) async {
    if (_usePlatformChannels) {
      try {
        final List<dynamic>? rawApps =
            await _appsChannel.invokeMethod('getInstalledApps', {
          'includeIcons': includeIcons,
        });

        if (rawApps != null && rawApps.isNotEmpty) {
          final List<AppEntry> apps = [];
          final List<AppEntry> needsDecode = [];
          for (final raw in rawApps) {
            final map = Map<String, dynamic>.from(raw as Map);
            final String packageName = map['packageName'] as String? ?? '';
            final String? activityName = map['activityName'] as String?;
            final String label = map['label'] as String? ?? packageName;
            final bool isSystemApp = map['isSystemApp'] as bool? ?? false;
            final int categoryInt = map['category'] as int? ?? -1;
            final Uint8List? iconBytes = map['iconBytes'] as Uint8List?;

            final category = _mapCategory(categoryInt, packageName, label);
            final accentColor = _getCategoryColor(category);

            // An icon already decoded for this package is reused as-is: a
            // package-change event must not re-decode the whole device.
            final cachedIcon = _iconCache[packageName];

            final app = AppEntry(
              packageName: packageName,
              activityName: activityName,
              label: label,
              isSystemApp: isSystemApp,
              category: category,
              iconBytes: iconBytes,
              decodedIcon: cachedIcon,
              accentColor: accentColor,
            );

            if (iconBytes != null && cachedIcon == null) {
              needsDecode.add(app);
            }

            apps.add(app);
          }

          await _decodeIcons(needsDecode);
          _pruneIconCache(apps);
          return apps;
        }
      } catch (e) {
        debugPrint('Error querying Android PackageManager: $e');
      }
      // A scan error or an empty answer: never substitute mocks on a device.
      return null;
    }

    // High-fidelity mock apps for simulation / desktop / non-Android hosts.
    return _generateMockApps();
  }

  /// Decoded icons by package name.
  ///
  /// Icons are the most expensive thing a scan produces, and a package-change
  /// event used to re-decode every one of them. Keeping them here means only
  /// genuinely new packages pay for a decode.
  static final Map<String, ui.Image> _iconCache = {};

  /// How many icon decodes run at once.
  ///
  /// Starting one per app produced a burst of 150+ concurrent codecs right
  /// after the first frame; a small window bounds the CPU and memory spike
  /// without serialising the whole scan.
  static const int _iconDecodeWindow = 4;

  /// Decodes [apps]' icons with a bounded window, caching what it produces.
  static Future<void> _decodeIcons(List<AppEntry> apps) async {
    if (apps.isEmpty) return;

    var next = 0;
    Future<void> worker() async {
      while (next < apps.length) {
        final app = apps[next++];
        final image = await _decodeIconBytes(app.iconBytes);
        if (image == null) continue;
        app.decodedIcon = image;
        _iconCache[app.packageName] = image;
      }
    }

    await Future.wait([
      for (int i = 0; i < _iconDecodeWindow && i < apps.length; i++) worker(),
    ]);
  }

  /// Decodes an icon at the size native rasterised it: the display's own
  /// density times the largest edge the launcher draws, so nothing is
  /// upscaled on screen. The old fixed 96 px decode left every icon soft at
  /// 520 dpi.
  static Future<ui.Image?> _decodeIconBytes(Uint8List? bytes) async {
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (e) {
      debugPrint('Failed to decode an app icon: $e');
      return null;
    }
  }

  /// Drops cached icons for packages that are no longer installed. Removing the
  /// last reference is what lets the engine reclaim them; nothing is disposed
  /// eagerly, because a widget still painting the previous list may hold one.
  static void _pruneIconCache(List<AppEntry> apps) {
    if (_iconCache.isEmpty) return;
    final installed = {for (final app in apps) app.packageName};
    _iconCache.removeWhere((packageName, _) => !installed.contains(packageName));
  }

  static Future<bool> authenticate({String? appName}) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod('authenticate', {
          'appName': appName,
        });
        return success ?? false;
      } catch (e) {
        // Two very different failures collapse into `false` here, and the
        // difference matters: a user dismissing the prompt is a real "no", but
        // a prompt that never opened is a platform refusal, and reporting it as
        // a plain denial is what makes it look like the user did nothing.
        //
        // Measured on ColorOS 16 (CPH2765): branding the BiometricPrompt with a
        // logo made authenticate() throw
        //   SecurityException: Must have SET_BIOMETRIC_DIALOG_ADVANCED permission
        // server-side, so every app tapped on the lock screen produced "auth
        // required" without any prompt being shown. Nothing in the UI could
        // distinguish that from a cancel. Name it explicitly so the next
        // occurrence is one line of log rather than a device investigation.
        final text = e.toString();
        final refusedByPlatform = text.contains('SecurityException') ||
            text.contains('permission') ||
            text.contains('SET_BIOMETRIC_DIALOG_ADVANCED');
        if (refusedByPlatform) {
          debugPrint(
            'Biometric prompt was REFUSED by the platform and never opened '
            '(this is not a user cancel): $e',
          );
        } else {
          debugPrint('Biometric authentication failed or canceled: $e');
        }
        return false;
      }
    } else {
      debugPrint('Simulating biometric authentication success for $appName');
      return true;
    }
  }

  /// Whether a fingerprint reader exists and has at least one finger enrolled.
  static Future<FingerprintCapability> fingerprintCapability() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const FingerprintCapability(hardware: false, enrolled: false);
    }
    try {
      final Map<Object?, Object?>? raw =
          await _appsChannel.invokeMethod<Map<Object?, Object?>>(
        'fingerprintCapability',
      );
      return FingerprintCapability(
        hardware: raw?['hardware'] == true,
        enrolled: raw?['enrolled'] == true,
      );
    } catch (e) {
      debugPrint('Fingerprint capability probe failed: $e');
      return const FingerprintCapability(hardware: false, enrolled: false);
    }
  }

  /// Arms the sensor without showing any system UI, so a touch on the reader
  /// authenticates straight away. Results arrive on [fingerprintEvents].
  ///
  /// Returns whether a session genuinely started. Every refusal reports
  /// `false` alongside its event, so an arm that never happened cannot
  /// masquerade as a live session: the caller's armed state is "a scan was
  /// started and no terminal event has arrived", built from this answer —
  /// never from the arrival of `listening`, which the platform now emits
  /// only on real sensor activity (a partial read) and which a clean first
  /// touch never triggers at all. A bare touch needs no prompt, so a missing
  /// `listening` costs nothing.
  static Future<bool> startFingerprintScan() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? started =
          await _appsChannel.invokeMethod('startFingerprintScan');
      return started ?? false;
    } catch (e) {
      debugPrint('Starting fingerprint scan failed: $e');
      return false;
    }
  }

  /// Disarms the sensor.
  static Future<void> stopFingerprintScan() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _appsChannel.invokeMethod('stopFingerprintScan');
    } catch (e) {
      debugPrint('Stopping fingerprint scan failed: $e');
    }
  }

  /// Silent fingerprint events: `listening`, `failed`, `succeeded`,
  /// `error` (with `code`/`message`), `screenOff`, `background`,
  /// `keyguardLocked` and `unavailable`.
  ///
  /// The refusals carry the reason an arm did not happen, so the caller can
  /// tell "the sensor said no" from "this state will never say yes":
  /// `screenOff` and `background` are transient, while `keyguardLocked` means
  /// the platform keyguard owns the reader for this lock session and the
  /// request must resolve through the platform's own prompt instead.
  static Stream<Map<String, dynamic>> fingerprintEvents() {
    if (kIsWeb || !Platform.isAndroid) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _fingerprintChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
  }

  /// The platform's current now-playing session, or null when there is none.
  ///
  /// The native side emits only on metadata/transport changes, not on every
  /// position tick; the card extrapolates position itself. On a non-Android
  /// host there is no session to observe, so the stream is empty rather than a
  /// channel that would fail on every listen in a test.
  static Stream<NowPlaying?> get mediaStream {
    if (_mediaStream == null) {
      if (!kIsWeb && Platform.isAndroid) {
        _mediaStream = _mediaChannel.receiveBroadcastStream().map((event) {
          if (event == null) return null;
          return NowPlaying.fromMap(Map<String, dynamic>.from(event as Map));
        });
      } else {
        _mediaStream = const Stream<NowPlaying?>.empty();
      }
    }
    return _mediaStream!;
  }

  /// Per-package notification counts from the platform's notification listener.
  ///
  /// Only non-zero packages are emitted, and an empty map is the honest answer
  /// while notification access is not granted. The stream is empty on a
  /// non-Android host, so a widget test that listens simply never rebuilds.
  static Stream<Map<String, dynamic>> get badgesStream {
    if (_badgesStream == null) {
      if (!kIsWeb && Platform.isAndroid) {
        _badgesStream = _badgesChannel
            .receiveBroadcastStream()
            .map((event) => Map<String, dynamic>.from(event as Map));
      } else {
        _badgesStream = const Stream<Map<String, dynamic>>.empty();
      }
    }
    return _badgesStream!;
  }

  /// The device's Material You palette, or null when the platform has none.
  ///
  /// ColorOS 16 themes the launcher from the home wallpaper; Android exposes the
  /// resolved tones as `android.R.color.system_accent*` on API 31+. Older
  /// devices and any native read failure answer null, and the caller keeps the
  /// launcher's own aqua accent rather than inventing a tone.
  static Future<SystemPalette?> getSystemPalette() async {
    _ensureHandlerInitialized();
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final Map<dynamic, dynamic>? raw =
          await _appsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getSystemPalette',
      );
      if (raw == null) return null;
      return SystemPalette.fromMap(Map<String, dynamic>.from(raw));
    } catch (e) {
      debugPrint('CF_THEME: reading the system palette failed: $e');
      return null;
    }
  }

  /// Palette pushes from native, one per real change while a surface resumes.
  ///
  /// The stream is empty on a host without the platform channel, so a widget
  /// test that listens to it simply never rebuilds.
  static Stream<SystemPalette?> get systemPaletteChanges {
    _ensureHandlerInitialized();
    return _systemPaletteController.stream;
  }

  /// Whether the user has granted notification access, which is the one thing
  /// `MediaSessionManager.getActiveSessions` requires. False on a host that has
  /// no such setting, so the caller hides the card rather than promising media
  /// it cannot see.
  static Future<bool> hasMediaAccess() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? granted = await _appsChannel.invokeMethod('hasMediaAccess');
        return granted ?? false;
      } catch (e) {
        debugPrint('CF_MEDIA: checking notification-listener access failed: $e');
        return false;
      }
    }
    return false;
  }

  /// Opens the system's notification-access settings.
  ///
  /// The platform owns this grant and only the user can give it, so this is a
  /// handoff, not a request dialog. Returns whether the settings screen could be
  /// opened.
  static Future<bool> requestMediaAccess() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? opened =
            await _appsChannel.invokeMethod('requestMediaAccess');
        return opened ?? false;
      } catch (e) {
        debugPrint('CF_MEDIA: opening notification-listener settings failed: $e');
        return false;
      }
    }
    return false;
  }

  /// Sends `playPause`, `next` or `previous` to the primary media session.
  /// Returns whether the platform reported the transport control handled it.
  static Future<bool> mediaCommand(String command) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? handled = await _appsChannel.invokeMethod(
          'mediaCommand',
          {'command': command},
        );
        return handled ?? false;
      } catch (e) {
        debugPrint('CF_MEDIA: media command "$command" failed: $e');
        return false;
      }
    }
    return false;
  }

  static Future<bool> isDefaultLauncher() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? isDefault = await _appsChannel.invokeMethod('isDefaultLauncher');
        return isDefault ?? false;
      } catch (e) {
        debugPrint('Check default launcher failed: $e');
        return false;
      }
    }
    return false;
  }

  static Future<bool> requestDefaultLauncher() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod('requestDefaultLauncher');
        return success ?? false;
      } catch (e) {
        debugPrint('Request default launcher failed: $e');
        return false;
      }
    }
    return false;
  }

  /// Whether the Android Keyguard (lock screen) is currently locked.
  static Future<bool> isKeyguardLocked() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? locked = await _appsChannel.invokeMethod('isKeyguardLocked');
        return locked ?? false;
      } catch (e) {
        debugPrint('Check keyguard locked failed: $e');
        return false;
      }
    }
    // On non-Android test environments, simulate locked keyguard for lockscreen fixtures.
    return true;
  }

  /// Whether any credential (PIN, pattern, fingerprint) protects this device.
  ///
  /// Full lock ownership is the settled product decision — the launcher
  /// mounts its own lock surface on a device with no secure lock too — so
  /// this is not a gate for mounting anything. The panel uses it to stay
  /// honest on such a device: with no credential there is no fingerprint
  /// that could ever be enrolled, so it neither arms a reader nor asks for
  /// one. A missing answer is treated as secure (the capability gate still
  /// refuses a scan on a device with nothing enrolled), because answering
  /// "not secure" to a failed probe would silently take the reader away from
  /// a device that has one.
  static Future<bool> isDeviceSecure() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? secure = await _appsChannel.invokeMethod('isDeviceSecure');
        return secure ?? true;
      } catch (e) {
        debugPrint('Check device secure failed: $e');
        return true;
      }
    }
    // Non-Android test hosts simulate a locked keyguard for the lockscreen
    // fixtures (see [isKeyguardLocked]), and a locked keyguard implies a
    // credential; the panel's behaviour there stays on the secure path.
    return true;
  }

  /// The real battery state for the lock surface — level 0-100 and whether
  /// the device is charging — or null when the platform cannot report a
  /// level.
  ///
  /// The lock panel used to hardcode `92%` under an always-lit charging
  /// glyph, and a lock screen that lies about the battery is the opposite of
  /// feeling native. Unknown travels as null rather than a sentinel number
  /// so the panel can hide the percentage instead of inventing one: a
  /// sentinel could not be told apart from a genuine answer downstream.
  static Future<BatteryState?> batteryState() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final Map<Object?, Object?>? raw = await _appsChannel
            .invokeMethod<Map<Object?, Object?>>('getBatteryState');
        if (raw == null) return null;
        return BatteryState(
          level: raw['level'] as int?,
          charging: raw['charging'] == true,
        );
      } catch (e) {
        debugPrint('Reading battery state failed: $e');
        return null;
      }
    }
    // No platform to ask: unknown, which the panel renders as a glyph with
    // no percentage.
    return null;
  }

  /// Asks the platform to authenticate the user and clear the keyguard, without
  /// launching anything.
  ///
  /// The launcher's own lock panel cannot authenticate anyone — while the device
  /// is locked only the keyguard may use the fingerprint sensor — so this is the
  /// only mechanism by which that panel can honestly let someone in. On a secure
  /// keyguard the platform raises its own bouncer and the result reports what
  /// the user did.
  ///
  /// Returns false on a non-Android host: a surface that cannot ask the platform
  /// to authenticate must not behave as though the platform agreed.
  static Future<bool> dismissKeyguard() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? dismissed = await _appsChannel.invokeMethod('dismissKeyguard');
      return dismissed ?? false;
    } catch (e) {
      debugPrint('Keyguard dismissal request failed: $e');
      return false;
    }
  }

  /// Enables or disables drawing MainActivity over the lock screen.
  /// In Native Mode, this is false so ColorOS handles the lockscreen.
  static Future<bool> setLockScreenOverlayEnabled(bool enabled) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod('setLockScreenOverlayEnabled', {
          'enabled': enabled,
        });
        return success ?? false;
      } catch (e) {
        debugPrint('Set lock screen overlay enabled failed: $e');
        return false;
      }
    }
    return true;
  }

  /// Holds the screen awake while the shopping surface is in store mode, or
  /// releases it when store mode ends or the surface closes.
  ///
  /// A no-op on a non-Android host, where there is no window flag to set. The
  /// shopping surface takes an injectable callback so a widget test never needs
  /// this channel.
  static Future<void> setKeepScreenOn(bool enabled) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _appsChannel.invokeMethod('setKeepScreenOn', {'enabled': enabled});
    } catch (e) {
      debugPrint('CF_SHOPPING: setKeepScreenOn failed: $e');
    }
  }

  /// Leaves the lock surface so the user lands on whatever is underneath.
  ///
  /// Only meaningful for the lock activity (`lockMain`): dismissing the panel
  /// there has to finish the activity, not merely unmount a widget, or the
  /// empty lock task would sit over the app. The launcher's own panel
  /// acknowledges the request without closing the HOME activity. Returns
  /// whether the native host accepted it.
  static Future<bool> finishLock() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? finished = await _appsChannel.invokeMethod('finishLock');
        return finished ?? false;
      } catch (e) {
        debugPrint('CF_LOCK: finishLock failed: $e');
        return false;
      }
    }
    return false;
  }

  /// Whether this app may draw over other apps.
  ///
  /// That grant is the one exemption from Android's background-activity-launch
  /// limits, so it decides whether the lock surface can be raised directly on
  /// screen-off or needs a full-screen-intent notification instead.
  static Future<bool> hasOverlayAccess() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? granted = await _appsChannel.invokeMethod('hasOverlayAccess');
        return granted ?? false;
      } catch (e) {
        debugPrint('CF_LOCK: checking overlay access failed: $e');
        return false;
      }
    }
    return false;
  }

  /// Opens the system's "display over other apps" page for this app.
  ///
  /// The platform owns this grant and only the user can give it, so this is a
  /// handoff, not a request dialog. Returns whether the settings screen could
  /// be opened.
  static Future<bool> requestOverlayAccess() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? opened =
            await _appsChannel.invokeMethod('requestOverlayAccess');
        return opened ?? false;
      } catch (e) {
        debugPrint('CF_LOCK: opening overlay settings failed: $e');
        return false;
      }
    }
    return false;
  }

  /// The system wallpaper's colour verdict, or null when the platform has
  /// none. Null on a non-Android host, where there is no wallpaper.
  static Future<WallpaperTone?> getWallpaperTone() async {
    _ensureHandlerInitialized();
    if (!_usePlatformChannels) return null;
    try {
      final Map<dynamic, dynamic>? raw =
          await _appsChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getWallpaperTone',
      );
      return WallpaperTone.fromMap(raw);
    } catch (e) {
      debugPrint('CF_WALLPAPER: reading the wallpaper colours failed: $e');
      return null;
    }
  }

  /// Wallpaper-colour pushes from native, one per change while the launcher
  /// runs. Empty on a host without the platform channel.
  static Stream<WallpaperTone?> get wallpaperToneChanges {
    _ensureHandlerInitialized();
    return _wallpaperToneController.stream;
  }

  /// Reports where the launcher is scrolled to, in wallpaper fractions, so the
  /// system wallpaper pans with the galaxy the way it pans with a paged home.
  /// Both axes are 0..1 with 0.5 at rest. A no-op off Android.
  static Future<void> setWallpaperOffsets(double x, double y) async {
    if (!_usePlatformChannels) return;
    try {
      await _appsChannel.invokeMethod('setWallpaperOffsets', {
        'x': x.clamp(0.0, 1.0),
        'y': y.clamp(0.0, 1.0),
      });
    } catch (e) {
      debugPrint('CF_WALLPAPER: wallpaper offsets refused: $e');
    }
  }

  /// Blurs the wallpaper behind the launcher window while a full-screen
  /// surface is up, or clears the blur. Answers whether the blur is in effect:
  /// false on a platform or build that has no window blur, in which case the
  /// surface's own scrim is all there is.
  static Future<bool> setWindowBlur(bool enabled) async {
    if (!_usePlatformChannels) return false;
    try {
      return await _appsChannel.invokeMethod<bool>('setWindowBlur', {
            'enabled': enabled,
          }) ??
          false;
    } catch (e) {
      debugPrint('CF_WALLPAPER: window blur refused: $e');
      return false;
    }
  }

  /// Launches [app].
  ///
  /// The platform decides how to get past the keyguard, and the distinction
  /// matters: while the keyguard is locked the activity must be launched *with*
  /// the keyguard dismissed, because a plain start places it behind the lock
  /// screen — running but invisible, which reads as the app never opening. That
  /// dismiss is what makes the app visible, and on a keyguard an earlier
  /// authentication has already satisfied it dismisses silently rather than
  /// asking again.
  ///
  /// [sourceBounds] is the tapped node's on-screen rectangle in *logical*
  /// pixels; it is converted to physical pixels here and handed to the platform
  /// so the launch can reveal from the exact place the finger landed. Null — the
  /// lock-screen and non-visual paths — sends no bounds at all, which is the
  /// launch that was already there.
  static Future<bool> launchApp(AppEntry app, {Rect? sourceBounds}) async {
    if (_usePlatformChannels) {
      try {
        final bool? success = await _appsChannel.invokeMethod('launchApp', {
          'packageName': app.packageName,
          'activityName': app.activityName,
          if (sourceBounds != null)
            'sourceBounds': _physicalRect(sourceBounds),
        });
        return success ?? false;
      } catch (e) {
        debugPrint('Launch app failed: $e');
        return false;
      }
    } else {
      debugPrint('Simulating launching app: ${app.label} (${app.packageName})');
      return true;
    }
  }

  /// The package's dynamic, manifest and pinned shortcuts.
  ///
  /// Empty when the platform cannot be asked: a non-Android host, or a device
  /// where this app is not the default launcher and so does not hold the
  /// shortcut host permission. That is the honest answer rather than an error,
  /// because the UI treats "no shortcuts" and "cannot read shortcuts" the same
  /// way — it shows none.
  static Future<List<AppShortcut>> getAppShortcuts(String packageName) async {
    if (_usePlatformChannels) {
      try {
        final List<dynamic>? raw = await _appsChannel.invokeMethod(
          'getAppShortcuts',
          {'packageName': packageName},
        );
        if (raw == null) return const [];
        return raw
            .map((e) => AppShortcut.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (e) {
        debugPrint('CF_SHORTCUTS: reading app shortcuts failed: $e');
        return const [];
      }
    }
    return const [];
  }

  /// Launches [shortcut], optionally revealing from [sourceBounds].
  ///
  /// Returns false — never throws — when the host permission is missing or the
  /// shortcut is disabled: the platform refuses both the same way from here.
  static Future<bool> startAppShortcut(
    AppShortcut shortcut, {
    Rect? sourceBounds,
  }) async {
    if (_usePlatformChannels) {
      try {
        final bool? success = await _appsChannel.invokeMethod('startAppShortcut', {
          'packageName': shortcut.packageName,
          'id': shortcut.id,
          if (sourceBounds != null)
            'sourceBounds': _physicalRect(sourceBounds),
        });
        return success ?? false;
      } catch (e) {
        debugPrint('CF_SHORTCUTS: launching a shortcut failed: $e');
        return false;
      }
    }
    return false;
  }

  /// The device's physical-pixel rectangle for a logical-pixel [rect].
  static Map<String, int> _physicalRect(Rect rect) {
    final double ratio = _devicePixelRatio();
    return {
      'left': (rect.left * ratio).round(),
      'top': (rect.top * ratio).round(),
      'right': (rect.right * ratio).round(),
      'bottom': (rect.bottom * ratio).round(),
    };
  }

  /// The first view's device pixel ratio, or 1.0 when the platform has no view
  /// (a bare unit-test binary). Goes through the binding so a widget test's
  /// `tester.view.devicePixelRatio` override is the value used.
  static double _devicePixelRatio() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 1.0;
    return views.first.devicePixelRatio;
  }

  /// Opens the platform's own handler for a lock-screen shortcut.
  ///
  /// Used only when [QuickShortcutResolver] cannot resolve the role from the
  /// installed app list — the list is filtered to LAUNCHER activities and is
  /// empty until the first scan finishes. Resolves to false when the platform
  /// has no unambiguous handler, so the caller can say so rather than pretend
  /// something opened.
  static Future<bool> openQuickShortcut(QuickShortcut shortcut) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod(
          'openQuickShortcut',
          {'shortcut': shortcut.channelName},
        );
        return success ?? false;
      } catch (e) {
        debugPrint('Open quick shortcut ${shortcut.name} failed: $e');
        return false;
      }
    }
    debugPrint('Simulating opening the ${shortcut.label} shortcut');
    return false;
  }

  static Future<void> openAppInfo(AppEntry app) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _appsChannel.invokeMethod('openAppInfo', {
          'packageName': app.packageName,
        });
      } catch (e) {
        debugPrint('Open app info failed: $e');
      }
    } else {
      debugPrint('Simulating opening app info for: ${app.label}');
    }
  }

  /// Hands a raw query to the platform's web search handler.
  ///
  /// Uses `ACTION_WEB_SEARCH`, an Activity action whose documented output is
  /// "nothing" — it cannot return results to this app. On the tested ColorOS 16
  /// build it resolves to the system chooser, so treat this as a handoff and
  /// consult [describeWebSearchHandoff] before promising a silent launch.
  static Future<bool> startWebSearch(String query) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod('startWebSearch', {
          'query': query,
        });
        return success ?? false;
      } catch (e) {
        debugPrint('Start web search failed: $e');
        return false;
      }
    }
    debugPrint('Simulating web search for: $query');
    return true;
  }

  /// Opens [url] in the user's chosen browser via the BROWSER role holder.
  ///
  /// Preferred over [startWebSearch] for anything that is already a URL: it
  /// launches silently rather than raising a chooser.
  static Future<bool> openWebUrl(String url) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod('openWebUrl', {
          'url': url,
        });
        return success ?? false;
      } catch (e) {
        debugPrint('Open web url failed: $e');
        return false;
      }
    }
    debugPrint('Simulating opening url: $url');
    return true;
  }

  /// Probes how `ACTION_WEB_SEARCH` would resolve on this device.
  ///
  /// Exists so the UI can label the handoff honestly. On a device with a
  /// platform default this reports a single handler; where the platform would
  /// raise a chooser, [WebSearchHandoff.raisesChooser] is true.
  static Future<WebSearchHandoff> describeWebSearchHandoff() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final raw = await _appsChannel
            .invokeMethod<Map<Object?, Object?>>('getWebSearchHandlers');
        if (raw != null) {
          return WebSearchHandoff.fromMap(Map<String, dynamic>.from(raw));
        }
      } catch (e) {
        debugPrint('Describe web search handoff failed: $e');
      }
    }
    return const WebSearchHandoff.unknown();
  }

  static Future<void> uninstallApp(AppEntry app) async {    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _appsChannel.invokeMethod('uninstallApp', {
          'packageName': app.packageName,
        });
      } catch (e) {
        debugPrint('Uninstall app failed: $e');
      }
    } else {
      debugPrint('Simulating uninstall for: ${app.label}');
    }
  }

  static Future<void> openHomeSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _appsChannel.invokeMethod('openHomeSettings');
      } catch (e) {
        debugPrint('Open home settings failed: $e');
      }
    }
  }

  /// Whether ChronoFold's galaxy is the system live wallpaper — the surface
  /// ColorOS shows behind a closing app before the launcher can draw. False
  /// off Android or when the platform cannot say.
  static Future<bool> isCosmicWallpaperActive() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? active =
          await _appsChannel.invokeMethod<bool>('isCosmicWallpaperActive');
      return active ?? false;
    } catch (e) {
      debugPrint('Reading the live wallpaper failed: $e');
      return false;
    }
  }

  /// Opens Android's live-wallpaper chooser for ChronoFold's optional ambient
  /// layer. The system—not the launcher—owns selection, preview, and apply.
  static Future<bool> openCosmicLiveWallpaperPreview() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? opened = await _appsChannel.invokeMethod(
        'openCosmicLiveWallpaperPreview',
      );
      return opened ?? false;
    } catch (e) {
      debugPrint('Open cosmic live wallpaper chooser failed: $e');
      return false;
    }
  }

  static Future<String?> getFilesDirPath() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        return await _appsChannel.invokeMethod<String>('getFilesDirPath');
      } catch (e) {
        debugPrint('Get files dir path failed: $e');
      }
    }
    return null;
  }

  static Future<String?> getExternalFilesDirPath() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        return await _appsChannel.invokeMethod<String>(
          'getExternalFilesDirPath',
        );
      } catch (e) {
        debugPrint('Get external files dir path failed: $e');
      }
    }
    return null;
  }

  /// Extracts the text layer of the PDF at [path] on-device.
  ///
  /// The native side runs PdfBox-Android off the main thread, caps extraction
  /// at 30 pages and reports the true page count plus whether it truncated.
  /// Nothing here is OCR: a scanned PDF answers an empty [PdfTextResult.text].
  /// A platform refusal travels in [PdfTextResult.errorCode] rather than an
  /// exception, following this bridge's existing try/catch style.
  static Future<PdfTextResult> extractPdfText(String path) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final Map<Object?, Object?>? raw = await _appsChannel
            .invokeMethod<Map<Object?, Object?>>('extractPdfText', {
          'path': path,
        });
        if (raw == null) {
          return const PdfTextResult(errorCode: 'PDF_UNREADABLE');
        }
        return PdfTextResult(
          text: raw['text'] as String? ?? '',
          pageCount: (raw['pageCount'] as num?)?.toInt() ?? 0,
          truncated: raw['truncated'] == true,
        );
      } on PlatformException catch (e) {
        debugPrint('CF_PDF: extractPdfText failed: ${e.code} ${e.message}');
        return PdfTextResult(errorCode: e.code);
      } catch (e) {
        debugPrint('CF_PDF: extractPdfText failed: $e');
        return const PdfTextResult(errorCode: 'PDF_UNREADABLE');
      }
    }
    return const PdfTextResult(errorCode: 'PDF_UNREADABLE');
  }

  /// Raises the system PDF picker and resolves to the cached path of the chosen
  /// document, or null when the user cancels. Only one pick may be pending at a
  /// time; a second request resolves null rather than replacing the first.
  static Future<String?> pickPdf() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        return await _appsChannel.invokeMethod<String>('pickPdf');
      } on PlatformException catch (e) {
        // A file over the native size cap is not a cancel: let the import
        // service tell the user why nothing happened.
        if (e.code == 'PDF_TOO_LARGE') rethrow;
        debugPrint('CF_PDF: pickPdf failed: $e');
        return null;
      } catch (e) {
        debugPrint('CF_PDF: pickPdf failed: $e');
        return null;
      }
    }
    return null;
  }

  /// Takes the PDF path a share/open delivered at startup, clearing it so it is
  /// never imported twice, or null when there is none.
  static Future<String?> takePendingSharedPdf() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        return await _appsChannel.invokeMethod<String>('takePendingSharedPdf');
      } catch (e) {
        debugPrint('CF_PDF: takePendingSharedPdf failed: $e');
        return null;
      }
    }
    return null;
  }

  static AppCategory _mapCategory(int cat, String pkg, String label) {
    final lower = '$pkg $label'.toLowerCase();

    // 1. Explicit Core Essentials (Phone, Messages, Camera, Primary Browser)
    final isCoreApp = (lower.contains('dialer') ||
            lower.contains('phone') ||
            lower.contains('contact')) &&
        !lower.contains('paybyphone') &&
        !lower.contains('manager');
    final isSms = lower.contains('mms') ||
        lower.contains('messaging') ||
        lower.contains('securesms') ||
        lower.contains('textnow');
    final isCamera = lower.contains('camera') && !lower.contains('extensions');
    final isMainBrowser = lower.contains('chrome') ||
        lower.contains('sbrowser') ||
        lower.contains('brave') ||
        lower.contains('firefox');

    if (isCoreApp || isSms || isCamera || isMainBrowser) {
      return AppCategory.core;
    }

    if (lower.contains('message') ||
        lower.contains('chat') ||
        lower.contains('social') ||
        lower.contains('discord') ||
        lower.contains('whatsapp') ||
        lower.contains('telegram') ||
        lower.contains('twitter') ||
        lower.contains('instagram') ||
        lower.contains('reddit') ||
        lower.contains('bluesky')) {
      return AppCategory.social;
    }
    if (lower.contains('doc') ||
        lower.contains('sheet') ||
        lower.contains('mail') ||
        lower.contains('calendar') ||
        lower.contains('note') ||
        lower.contains('drive') ||
        lower.contains('slack') ||
        lower.contains('notion') ||
        lower.contains('task')) {
      return AppCategory.productivity;
    }
    if (lower.contains('music') ||
        lower.contains('audio') ||
        lower.contains('video') ||
        lower.contains('photo') ||
        lower.contains('gallery') ||
        lower.contains('youtube') ||
        lower.contains('spotify') ||
        lower.contains('netflix')) {
      return AppCategory.entertainment;
    }
    if (lower.contains('game') || cat == 0 /* ApplicationInfo.CATEGORY_GAME */) {
      return AppCategory.games;
    }
    if (lower.contains('clock') ||
        lower.contains('calc') ||
        lower.contains('file') ||
        lower.contains('setting') ||
        lower.contains('browser')) {
      return AppCategory.tools;
    }
    return AppCategory.tools;
  }

  static Color _getCategoryColor(AppCategory category) {
    return LuminousHomeTheme.categoryAccent(category);
  }

  static List<AppEntry> _generateMockApps() {
    return [
      // Core apps
      AppEntry(
        packageName: 'com.android.phone',
        label: 'Phone',
        category: AppCategory.core,
        accentColor: LuminousHomeTheme.accentCore,
        fallbackIcon: Icons.phone_in_talk_rounded,
        notificationCount: 2,
      ),
      AppEntry(
        packageName: 'com.android.mms',
        label: 'Messages',
        category: AppCategory.core,
        accentColor: LuminousHomeTheme.accentCore,
        fallbackIcon: Icons.forum_rounded,
        notificationCount: 5,
      ),
      AppEntry(
        packageName: 'com.android.chrome',
        label: 'Chrome',
        category: AppCategory.core,
        accentColor: LuminousHomeTheme.accentCore,
        fallbackIcon: Icons.language_rounded,
      ),
      AppEntry(
        packageName: 'com.android.camera',
        label: 'Camera',
        category: AppCategory.core,
        accentColor: LuminousHomeTheme.accentCore,
        fallbackIcon: Icons.camera_alt_rounded,
      ),

      // Social Galaxy
      AppEntry(
        packageName: 'com.whatsapp',
        label: 'WhatsApp',
        category: AppCategory.social,
        accentColor: LuminousHomeTheme.brandWhatsapp,
        fallbackIcon: Icons.chat_bubble_rounded,
        notificationCount: 12,
      ),
      AppEntry(
        packageName: 'com.discord',
        label: 'Discord',
        category: AppCategory.social,
        accentColor: LuminousHomeTheme.brandDiscord,
        fallbackIcon: Icons.headset_mic_rounded,
        notificationCount: 3,
      ),
      AppEntry(
        packageName: 'com.instagram.android',
        label: 'Instagram',
        category: AppCategory.social,
        accentColor: LuminousHomeTheme.brandInstagram,
        fallbackIcon: Icons.camera_rounded,
      ),
      AppEntry(
        packageName: 'com.twitter.android',
        label: 'X',
        category: AppCategory.social,
        accentColor: LuminousHomeTheme.white,
        fallbackIcon: Icons.tag_rounded,
      ),
      AppEntry(
        packageName: 'org.telegram.messenger',
        label: 'Telegram',
        category: AppCategory.social,
        accentColor: LuminousHomeTheme.brandTelegram,
        fallbackIcon: Icons.send_rounded,
        notificationCount: 1,
      ),

      // Productivity Ring
      AppEntry(
        packageName: 'com.google.android.gm',
        label: 'Gmail',
        category: AppCategory.productivity,
        accentColor: LuminousHomeTheme.brandGmail,
        fallbackIcon: Icons.mail_outline_rounded,
        notificationCount: 9,
      ),
      AppEntry(
        packageName: 'com.google.android.calendar',
        label: 'Calendar',
        category: AppCategory.productivity,
        accentColor: LuminousHomeTheme.brandGoogleBlue,
        fallbackIcon: Icons.calendar_today_rounded,
      ),
      AppEntry(
        packageName: 'notion.id',
        label: 'Notion',
        category: AppCategory.productivity,
        accentColor: LuminousHomeTheme.brandNotion,
        fallbackIcon: Icons.edit_note_rounded,
      ),
      AppEntry(
        packageName: 'com.slack',
        label: 'Slack',
        category: AppCategory.productivity,
        accentColor: LuminousHomeTheme.brandSlack,
        fallbackIcon: Icons.workspaces_filled,
        notificationCount: 4,
      ),
      AppEntry(
        packageName: 'com.github.mobile',
        label: 'GitHub',
        category: AppCategory.productivity,
        accentColor: LuminousHomeTheme.brandGithub,
        fallbackIcon: Icons.code_rounded,
      ),

      // Entertainment & Media
      AppEntry(
        packageName: 'com.spotify.music',
        label: 'Spotify',
        category: AppCategory.entertainment,
        accentColor: LuminousHomeTheme.brandSpotify,
        fallbackIcon: Icons.graphic_eq_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.youtube',
        label: 'YouTube',
        category: AppCategory.entertainment,
        accentColor: LuminousHomeTheme.brandYoutube,
        fallbackIcon: Icons.play_circle_fill_rounded,
      ),
      AppEntry(
        packageName: 'com.netflix.mediaclient',
        label: 'Netflix',
        category: AppCategory.entertainment,
        accentColor: LuminousHomeTheme.brandNetflix,
        fallbackIcon: Icons.movie_filter_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.apps.photos',
        label: 'Photos',
        category: AppCategory.entertainment,
        accentColor: LuminousHomeTheme.brandPhotos,
        fallbackIcon: Icons.photo_library_rounded,
      ),

      // Tools & Utilities
      AppEntry(
        packageName: 'com.google.android.deskclock',
        label: 'Clock',
        category: AppCategory.tools,
        accentColor: LuminousHomeTheme.brandClock,
        fallbackIcon: Icons.access_time_filled_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.calculator',
        label: 'Calculator',
        category: AppCategory.tools,
        accentColor: LuminousHomeTheme.brandCalculator,
        fallbackIcon: Icons.calculate_rounded,
      ),
      AppEntry(
        packageName: 'com.android.settings',
        label: 'Settings',
        category: AppCategory.tools,
        accentColor: LuminousHomeTheme.brandSettings,
        fallbackIcon: Icons.tune_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.apps.maps',
        label: 'Maps',
        category: AppCategory.tools,
        accentColor: LuminousHomeTheme.brandMaps,
        fallbackIcon: Icons.explore_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.apps.nbu.files',
        label: 'Files',
        category: AppCategory.tools,
        accentColor: LuminousHomeTheme.brandFiles,
        fallbackIcon: Icons.folder_rounded,
      ),
    ];
  }
}

/// What the platform reports about the fingerprint reader.
class FingerprintCapability {
  final bool hardware;
  final bool enrolled;

  const FingerprintCapability({required this.hardware, required this.enrolled});

  /// True only when a scan can actually be armed.
  bool get isReady => hardware && enrolled;
}

/// What the platform reports about the battery, for the lock surface.
class BatteryState {
  /// Remaining charge, 0-100. Null when the platform could not report a
  /// level — the lock surface then hides the percentage rather than
  /// inventing one.
  final int? level;

  /// Whether the device is currently charging.
  final bool charging;

  const BatteryState({required this.level, required this.charging});

  /// What the lock surface shows for the level: `'92%'`, or null when the
  /// level is unknown. Pure on purpose, so the unknown rule — hide, never
  /// invent — is pinned by a unit test without pumping a widget.
  String? get percentage => level == null ? null : '$level%';

  /// The glyph the lock surface shows: the charging glyph while plugged in,
  /// a plain battery otherwise. The old row lit the charging glyph forever.
  IconData get icon =>
      charging
          ? Icons.battery_charging_full_rounded
          : Icons.battery_std_rounded;
}

/// How `ACTION_WEB_SEARCH` resolves on this device.
///
/// The surface uses this to label the handoff truthfully. Verified on ColorOS 16
/// (CPH2765): seven handlers, no platform default, so the platform raises a
/// chooser — a fact the UI must not hide from the user.
class WebSearchHandoff {
  /// Packages that claim `ACTION_WEB_SEARCH`.
  final List<String> handlers;

  /// Package the platform resolves `ACTION_WEB_SEARCH` to. `android` means the
  /// platform's internal ResolverActivity, i.e. a chooser will appear.
  final String? resolvedPackage;

  /// True when the platform would show a disambiguation chooser.
  final bool raisesChooser;

  /// Whether *this* app holds the BROWSER role. Not the browser's identity —
  /// no public API exposes that — so this is diagnostics only.
  final bool holdsBrowserRole;

  /// True when the platform could not be asked at all (non-Android, or the
  /// probe failed). Callers should stay neutral rather than claiming either way.
  final bool isKnown;

  const WebSearchHandoff({
    required this.handlers,
    this.resolvedPackage,
    required this.raisesChooser,
    this.holdsBrowserRole = false,
    this.isKnown = true,
  });

  const WebSearchHandoff.unknown()
      : handlers = const [],
        resolvedPackage = null,
        raisesChooser = false,
        holdsBrowserRole = false,
        isKnown = false;

  int get handlerCount => handlers.length;

  factory WebSearchHandoff.fromMap(Map<String, dynamic> map) {
    return WebSearchHandoff(
      handlers: (map['handlers'] as List?)
              ?.map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      resolvedPackage: map['resolvedPackage'] as String?,
      raisesChooser: map['raisesChooser'] as bool? ?? false,
      holdsBrowserRole: map['holdsBrowserRole'] as bool? ?? false,
    );
  }
}

/// The on-device result of reading a PDF's text layer.
///
/// A failure carries only [errorCode] (`PDF_ENCRYPTED` or `PDF_UNREADABLE`), so
/// a caller can name the reason instead of treating every failure as the same
/// unreadable file. The text is empty — never absent — when a PDF has no text
/// layer, which is what a scanned document looks like.
class PdfTextResult {
  final String text;
  final int pageCount;
  final bool truncated;
  final String? errorCode;

  const PdfTextResult({
    this.text = '',
    this.pageCount = 0,
    this.truncated = false,
    this.errorCode,
  });

  bool get hasError => errorCode != null;
}
