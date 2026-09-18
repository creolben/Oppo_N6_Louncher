import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/app_entry.dart';
import 'core/launcher_bridge.dart';
import 'core/foldable_controller.dart';
import 'core/galaxy_layout_engine.dart';
import 'canvas/camera_controller.dart';
import 'canvas/galaxy_interactive_canvas.dart';
import 'ui/widgets/foldable_cockpit_bar.dart';
import 'ui/widgets/search_overlay.dart';
import 'ui/widgets/app_action_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const ChronoFoldApp());
}

class ChronoFoldApp extends StatelessWidget {
  const ChronoFoldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChronoFold Launcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF020306),
        fontFamily: 'Roboto',
      ),
      home: const ChronoFoldHomeScreen(),
    );
  }
}

class ChronoFoldHomeScreen extends StatefulWidget {
  const ChronoFoldHomeScreen({super.key});

  @override
  State<ChronoFoldHomeScreen> createState() => _ChronoFoldHomeScreenState();
}

class _ChronoFoldHomeScreenState extends State<ChronoFoldHomeScreen> {
  late final FoldableController _foldable;
  late final CameraController _camera;
  late final GalaxyLayoutEngine _layoutEngine;

  List<AppEntry> _apps = [];
  bool _isLoading = true;
  bool _isSearchOpen = false;
  late Timer _clockTimer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _foldable = FoldableController();
    _camera = CameraController();
    _layoutEngine = GalaxyLayoutEngine();

    _loadApplications();

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  Future<void> _loadApplications() async {
    final apps = await LauncherBridge.getInstalledApps();
    _layoutEngine.assignApps(apps);
    if (mounted) {
      setState(() {
        _apps = apps;
        _isLoading = false;
      });
    }
  }

  void _openAppLongPressDialog(AppEntry app, Offset screenPosition) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'AppActions',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, anim1, anim2) {
        return AppActionDialog(app: app);
      },
      transitionBuilder: (context, anim, secondaryAnim, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _foldable.dispose();
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _foldable.updateFromMediaQuery(context);

    final timeString =
        '${_currentTime.hour.toString().padLeft(2, '0')}:${_currentTime.minute.toString().padLeft(2, '0')}';
    final dateString =
        '${_weekdayName(_currentTime.weekday)}, ${_monthName(_currentTime.month)} ${_currentTime.day}';

    return Scaffold(
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF00E5FF),
                strokeWidth: 2.0,
              ),
            )
          : Stack(
              children: [
                // 1. Kinetic Galaxy Canvas
                Positioned.fill(
                  child: GalaxyInteractiveCanvas(
                    apps: _apps,
                    foldable: _foldable,
                    camera: _camera,
                    layoutEngine: _layoutEngine,
                    onAppLongPressed: _openAppLongPressDialog,
                  ),
                ),

                // 2. Cosmic HUD Header (Clock, Date & Posture Telemetry)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Clock & Date
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                timeString,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w200,
                                  letterSpacing: -0.5,
                                  shadows: [
                                    Shadow(color: Color(0x6600E5FF), blurRadius: 16),
                                  ],
                                ),
                              ),
                              Text(
                                dateString.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),

                          // Galaxy Sector Status
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x33101424),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0x3364B5F6),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF00E5FF),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Color(0xFF00E5FF),
                                        blurRadius: 6,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _foldable.posture.name.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Ergonomic Bottom Cockpit Bar
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: FoldableCockpitBar(
                    foldable: _foldable,
                    camera: _camera,
                    layoutEngine: _layoutEngine,
                    onOpenSearch: () => setState(() => _isSearchOpen = true),
                    onOpenSettings: () => LauncherBridge.openHomeSettings(),
                  ),
                ),

                // 4. Fullscreen Search HUD
                if (_isSearchOpen)
                  Positioned.fill(
                    child: SearchOverlay(
                      allApps: _apps,
                      camera: _camera,
                      onClose: () => setState(() => _isSearchOpen = false),
                    ),
                  ),
              ],
            ),
    );
  }

  String _weekdayName(int day) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(day - 1) % 7];
  }

  String _monthName(int month) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[(month - 1) % 12];
  }
}
