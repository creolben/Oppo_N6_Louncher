import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_entry.dart';

class LauncherBridge {
  static const MethodChannel _appsChannel =
      MethodChannel('com.launcher.chronofold/apps');

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

            final app = AppEntry(
              packageName: packageName,
              activityName: activityName,
              label: label,
              isSystemApp: isSystemApp,
              category: category,
              iconBytes: iconBytes,
              accentColor: accentColor,
            );

            if (iconBytes != null) {
              _decodeAppIcon(app);
            }

            apps.add(app);
          }
          return apps;
        }
      } catch (e) {
        debugPrint('Error querying Android PackageManager: $e');
      }
    }

    // Fallback to high-fidelity mock apps for simulation / desktop / non-Android
    return _generateMockApps();
  }

  static Future<void> _decodeAppIcon(AppEntry app) async {
    if (app.iconBytes == null) return;
    try {
      final codec = await ui.instantiateImageCodec(
        app.iconBytes!,
        targetWidth: 96,
        targetHeight: 96,
      );
      final frame = await codec.getNextFrame();
      app.decodedIcon = frame.image;
    } catch (e) {
      debugPrint('Failed to decode icon for ${app.label}: $e');
    }
  }

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

  static Future<void> uninstallApp(AppEntry app) async {
    if (!kIsWeb && Platform.isAndroid) {
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

  static AppCategory _mapCategory(int cat, String pkg, String label) {
    final lower = '$pkg $label'.toLowerCase();
    if (lower.contains('message') ||
        lower.contains('chat') ||
        lower.contains('contact') ||
        lower.contains('phone') ||
        lower.contains('social') ||
        lower.contains('discord') ||
        lower.contains('whatsapp') ||
        lower.contains('telegram') ||
        lower.contains('twitter') ||
        lower.contains('instagram')) {
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
        lower.contains('camera') ||
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
        lower.contains('browser') ||
        lower.contains('chrome')) {
      return AppCategory.tools;
    }
    return AppCategory.core;
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
