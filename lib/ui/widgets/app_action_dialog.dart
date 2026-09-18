import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../core/launcher_bridge.dart';

class AppActionDialog extends StatelessWidget {
  final AppEntry app;

  const AppActionDialog({
    super.key,
    required this.app,
  });

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Center(
        child: Container(
          width: 310,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xEE121626),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: app.accentColor.withOpacity(0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: app.accentColor.withOpacity(0.2),
                blurRadius: 28,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App Emblem
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: app.accentColor.withOpacity(0.18),
                    border: Border.all(color: app.accentColor.withOpacity(0.6), width: 1.5),
                  ),
                  child: Icon(app.fallbackIcon, color: app.accentColor, size: 30),
                ),
                const SizedBox(height: 12),
                Text(
                  app.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  app.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 10),

                // Actions
                _actionTile(
                  context,
                  icon: Icons.launch_rounded,
                  label: 'Launch Application',
                  color: const Color(0xFF00E5FF),
                  onTap: () {
                    Navigator.of(context).pop();
                    LauncherBridge.launchApp(app);
                  },
                ),
                _actionTile(
                  context,
                  icon: Icons.info_outline_rounded,
                  label: 'App Details & Permissions',
                  color: Colors.white70,
                  onTap: () {
                    Navigator.of(context).pop();
                    LauncherBridge.openAppInfo(app);
                  },
                ),
                if (!app.isSystemApp)
                  _actionTile(
                    context,
                    icon: Icons.delete_outline_rounded,
                    label: 'Uninstall',
                    color: const Color(0xFFFF5252),
                    onTap: () {
                      Navigator.of(context).pop();
                      LauncherBridge.uninstallApp(app);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      leading: Icon(icon, color: color, size: 20),
      title: Text(
        label,
        style: TextStyle(color: color, fontSize: 13.5, fontWeight: FontWeight.w500),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}
