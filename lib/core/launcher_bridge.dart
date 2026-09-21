import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_entry.dart';
import '../models/quick_shortcut.dart';

class LauncherBridge {  static const MethodChannel _appsChannel =
      MethodChannel('com.launcher.chronofold/apps');
  static const EventChannel _shakeChannel =
      EventChannel('com.launcher.chronofold/shake');
  static const EventChannel _fingerprintChannel =
      EventChannel('com.launcher.chronofold/fingerprint');

  static Stream<Map<String, dynamic>>? _shakeStream;

  /// Edge length icons are decoded at, matching the native side's downscale.
  static const int _iconPixels = 96;

  static VoidCallback? _onLockScreenListener;
  static VoidCallback? _onPackageChangeListener;
  static VoidCallback? _onHomeButtonListener;
  static VoidCallback? _onScreenOnListener;
  static VoidCallback? _onUserPresentListener;
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

  @visibleForTesting
  static void dispatchUserPresentForTesting() {
    _onUserPresentListener?.call();
  }

  /// Fires when the panel turns on, i.e. the moment the platform will let an
  /// app hold the fingerprint reader again.
  static void setScreenOnListener(VoidCallback? onScreenOn) {
    _onScreenOnListener = onScreenOn;
    _ensureHandlerInitialized();
  }

  static void setPackageChangeListener(VoidCallback onPackageChange) {
    _onPackageChangeListener = onPackageChange;
    _ensureHandlerInitialized();
  }

  static void setHomeButtonListener(VoidCallback onHomePressed) {
    _onHomeButtonListener = onHomePressed;
    _ensureHandlerInitialized();
  }


  static Stream<Map<String, dynamic>> getShakeStream() {
    if (_shakeStream == null) {
      if (!kIsWeb && Platform.isAndroid) {
        _shakeStream = _shakeChannel
            .receiveBroadcastStream()
            .map((event) => Map<String, dynamic>.from(event as Map));
      } else {
        _shakeStream = const Stream.empty();
      }
    }
    return _shakeStream!;
  }

  /// Fetches installed apps from Android native PackageManager,
  /// or returns rich mock apps when running on desktop / emulator without packages.
  static Future<List<AppEntry>> getInstalledApps({bool includeIcons = true}) async {
    if (!kIsWeb && Platform.isAndroid) {
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
    }

    // Fallback to high-fidelity mock apps for simulation / desktop / non-Android
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

  static Future<ui.Image?> _decodeIconBytes(Uint8List? bytes) async {
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _iconPixels,
        targetHeight: _iconPixels,
      );
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
  static Future<void> startFingerprintScan() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _appsChannel.invokeMethod('startFingerprintScan');
    } catch (e) {
      debugPrint('Starting fingerprint scan failed: $e');
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
  /// `error` (with `code`/`message`) and `unavailable`.
  static Stream<Map<String, dynamic>> fingerprintEvents() {
    if (kIsWeb || !Platform.isAndroid) {
      return const Stream<Map<String, dynamic>>.empty();
    }
    return _fingerprintChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
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

  /// Tells Android that Flutter has produced a new launcher frame after a
  /// foreground return. The native return bridge remains opaque until this
  /// acknowledgement, preventing the system task compositor from flashing
  /// ColorOS content between the external app and the cover screen.
  static Future<void> notifyLauncherFrameReady() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _appsChannel.invokeMethod('launcherFrameReady');
      } catch (e) {
        debugPrint('Could not acknowledge launcher frame: $e');
      }
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
  static Future<bool> launchApp(AppEntry app) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bool? success = await _appsChannel.invokeMethod('launchApp', {
          'packageName': app.packageName,
          'activityName': app.activityName,
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
    switch (category) {
      case AppCategory.core:
        return const Color(0xFFFFD54F); // Radiant Gold
      case AppCategory.social:
        return const Color(0xFFF06292); // Cosmic Pink
      case AppCategory.productivity:
        return const Color(0xFF4DD0E1); // Cyan Nebula
      case AppCategory.entertainment:
        return const Color(0xFF81C784); // Aurora Green
      case AppCategory.tools:
        return const Color(0xFFFFB74D); // Solar Orange
      case AppCategory.games:
        return const Color(0xFFBA68C8); // Violet Quasar
    }
  }

  static List<AppEntry> _generateMockApps() {
    return [
      // Core apps
      AppEntry(
        packageName: 'com.android.phone',
        label: 'Phone',
        category: AppCategory.core,
        accentColor: const Color(0xFFFFD54F),
        fallbackIcon: Icons.phone_in_talk_rounded,
        notificationCount: 2,
      ),
      AppEntry(
        packageName: 'com.android.mms',
        label: 'Messages',
        category: AppCategory.core,
        accentColor: const Color(0xFFFFD54F),
        fallbackIcon: Icons.forum_rounded,
        notificationCount: 5,
      ),
      AppEntry(
        packageName: 'com.android.chrome',
        label: 'Chrome',
        category: AppCategory.core,
        accentColor: const Color(0xFFFFD54F),
        fallbackIcon: Icons.language_rounded,
      ),
      AppEntry(
        packageName: 'com.android.camera',
        label: 'Camera',
        category: AppCategory.core,
        accentColor: const Color(0xFFFFD54F),
        fallbackIcon: Icons.camera_alt_rounded,
      ),

      // Social Galaxy
      AppEntry(
        packageName: 'com.whatsapp',
        label: 'WhatsApp',
        category: AppCategory.social,
        accentColor: const Color(0xFF25D366),
        fallbackIcon: Icons.chat_bubble_rounded,
        notificationCount: 12,
      ),
      AppEntry(
        packageName: 'com.discord',
        label: 'Discord',
        category: AppCategory.social,
        accentColor: const Color(0xFF7289DA),
        fallbackIcon: Icons.headset_mic_rounded,
        notificationCount: 3,
      ),
      AppEntry(
        packageName: 'com.instagram.android',
        label: 'Instagram',
        category: AppCategory.social,
        accentColor: const Color(0xFFE1306C),
        fallbackIcon: Icons.camera_rounded,
      ),
      AppEntry(
        packageName: 'com.twitter.android',
        label: 'X',
        category: AppCategory.social,
        accentColor: const Color(0xFFFFFFFF),
        fallbackIcon: Icons.tag_rounded,
      ),
      AppEntry(
        packageName: 'org.telegram.messenger',
        label: 'Telegram',
        category: AppCategory.social,
        accentColor: const Color(0xFF29B6F6),
        fallbackIcon: Icons.send_rounded,
        notificationCount: 1,
      ),

      // Productivity Ring
      AppEntry(
        packageName: 'com.google.android.gm',
        label: 'Gmail',
        category: AppCategory.productivity,
        accentColor: const Color(0xFFEA4335),
        fallbackIcon: Icons.mail_outline_rounded,
        notificationCount: 9,
      ),
      AppEntry(
        packageName: 'com.google.android.calendar',
        label: 'Calendar',
        category: AppCategory.productivity,
        accentColor: const Color(0xFF4285F4),
        fallbackIcon: Icons.calendar_today_rounded,
      ),
      AppEntry(
        packageName: 'notion.id',
        label: 'Notion',
        category: AppCategory.productivity,
        accentColor: const Color(0xFFE0E0E0),
        fallbackIcon: Icons.edit_note_rounded,
      ),
      AppEntry(
        packageName: 'com.slack',
        label: 'Slack',
        category: AppCategory.productivity,
        accentColor: const Color(0xFF4A154B),
        fallbackIcon: Icons.workspaces_filled,
        notificationCount: 4,
      ),
      AppEntry(
        packageName: 'com.github.mobile',
        label: 'GitHub',
        category: AppCategory.productivity,
        accentColor: const Color(0xFF80CBC4),
        fallbackIcon: Icons.code_rounded,
      ),

      // Entertainment & Media
      AppEntry(
        packageName: 'com.spotify.music',
        label: 'Spotify',
        category: AppCategory.entertainment,
        accentColor: const Color(0xFF1DB954),
        fallbackIcon: Icons.graphic_eq_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.youtube',
        label: 'YouTube',
        category: AppCategory.entertainment,
        accentColor: const Color(0xFFFF0000),
        fallbackIcon: Icons.play_circle_fill_rounded,
      ),
      AppEntry(
        packageName: 'com.netflix.mediaclient',
        label: 'Netflix',
        category: AppCategory.entertainment,
        accentColor: const Color(0xFFE50914),
        fallbackIcon: Icons.movie_filter_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.apps.photos',
        label: 'Photos',
        category: AppCategory.entertainment,
        accentColor: const Color(0xFFFBBC05),
        fallbackIcon: Icons.photo_library_rounded,
      ),

      // Tools & Utilities
      AppEntry(
        packageName: 'com.google.android.deskclock',
        label: 'Clock',
        category: AppCategory.tools,
        accentColor: const Color(0xFF26A69A),
        fallbackIcon: Icons.access_time_filled_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.calculator',
        label: 'Calculator',
        category: AppCategory.tools,
        accentColor: const Color(0xFFFFA726),
        fallbackIcon: Icons.calculate_rounded,
      ),
      AppEntry(
        packageName: 'com.android.settings',
        label: 'Settings',
        category: AppCategory.tools,
        accentColor: const Color(0xFF78909C),
        fallbackIcon: Icons.tune_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.apps.maps',
        label: 'Maps',
        category: AppCategory.tools,
        accentColor: const Color(0xFF34A853),
        fallbackIcon: Icons.explore_rounded,
      ),
      AppEntry(
        packageName: 'com.google.android.apps.nbu.files',
        label: 'Files',
        category: AppCategory.tools,
        accentColor: const Color(0xFF42A5F5),
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
