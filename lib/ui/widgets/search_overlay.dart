import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../canvas/camera_controller.dart';
import '../../core/launcher_bridge.dart';

class SearchOverlay extends StatefulWidget {
  final List<AppEntry> allApps;
  final CameraController camera;
  final VoidCallback onClose;

  const SearchOverlay({
    super.key,
    required this.allApps,
    required this.camera,
    required this.onClose,
  });

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  List<AppEntry> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.allApps;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _onQueryChanged(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filtered = widget.allApps;
      } else {
        final q = query.toLowerCase().trim();
        _filtered = widget.allApps.where((app) {
          return app.label.toLowerCase().contains(q) ||
              app.packageName.toLowerCase().contains(q);
        }).toList();
      }
    });
  }

  void _flyToAndLaunch(AppEntry app) {
    widget.camera.flyTo(app.worldPosition, targetZoom: 1.6);
    widget.onClose();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
      child: Container(
        color: const Color(0x9904060C),
        child: SafeArea(
          child: Column(
            children: [
              // Search Input Field
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B2E).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: const Color(0xFF64B5F6).withOpacity(0.4),
                            width: 1.2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x2200E5FF),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          onChanged: _onQueryChanged,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            letterSpacing: 0.5,
                          ),
                          cursorColor: const Color(0xFF00E5FF),
                          decoration: InputDecoration(
                            hintText: 'Search the galaxy...',
                            hintStyle: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 15,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF00E5FF),
                            ),
                            suffixIcon: _controller.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Colors.white70),
                                    onPressed: () {
                                      _controller.clear();
                                      _onQueryChanged('');
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),

              // Filtered Results List
              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No stars found in this sector',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.4),
                            fontSize: 14,
                            letterSpacing: 1.0,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final app = _filtered[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF101424).withOpacity(0.7),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: app.accentColor.withOpacity(0.25),
                                width: 1.0,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: app.accentColor.withOpacity(0.15),
                                  border: Border.all(
                                    color: app.accentColor.withOpacity(0.5),
                                  ),
                                ),
                                child: Icon(
                                  app.fallbackIcon,
                                  color: app.accentColor,
                                  size: 22,
                                ),
                              ),
                              title: Text(
                                app.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              subtitle: Text(
                                app.packageName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.4),
                                  fontSize: 12,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.radar_rounded, color: Color(0xFF00E5FF)),
                                    tooltip: 'Fly to star',
                                    onPressed: () => _flyToAndLaunch(app),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.launch_rounded, color: Colors.white70),
                                    tooltip: 'Launch app',
                                    onPressed: () {
                                      LauncherBridge.launchApp(app);
                                      widget.onClose();
                                    },
                                  ),
                                ],
                              ),
                              onTap: () => _flyToAndLaunch(app),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
