import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/foldable_controller.dart';
import '../../models/app_entry.dart';
import '../../core/launcher_bridge.dart';

class CosmicLockScreen extends StatefulWidget {
  final FoldableController foldable;
  final VoidCallback onUnlock;
  final List<AppEntry> apps;

  const CosmicLockScreen({
    super.key,
    required this.foldable,
    required this.onUnlock,
    required this.apps,
  });

  @override
  State<CosmicLockScreen> createState() => _CosmicLockScreenState();
}

class _CosmicLockScreenState extends State<CosmicLockScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  double _dragOffset = 0.0;
  DateTime _currentTime = DateTime.now();
  late Timer _clockTimer;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _slideAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {});
      });

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta != null) {
      setState(() {
        _dragOffset = (_dragOffset - details.primaryDelta!).clamp(0.0, 600.0);
      });
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    // Fast swipe up or dragged past 140px unlocks
    if (velocity < -400 || _dragOffset > 140.0) {
      _unlock();
    } else {
      // Spring bounce back down
      _snapBack();
    }
  }

  void _unlock({VoidCallback? onComplete}) {
    HapticFeedback.lightImpact();
    _slideAnimation = Tween<double>(begin: _dragOffset, end: 900.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeInCubic),
    );
    _slideController.forward(from: 0.0).then((_) {
      widget.onUnlock();
      onComplete?.call();
    });
  }

  void _snapBack() {
    _slideAnimation = Tween<double>(begin: _dragOffset, end: 0.0).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack),
    );
    _slideController.forward(from: 0.0).then((_) {
      _dragOffset = 0.0;
    });
  }

  void _launchQuickApp(String packageName) {
    _unlock(onComplete: () {
      final app = widget.apps.firstWhere(
        (a) => a.packageName == packageName,
        orElse: () => widget.apps.first,
      );
      LauncherBridge.launchApp(app);
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final currentOffset = _slideController.isAnimating ? _slideAnimation.value : _dragOffset;
    final double unlockProgress = (currentOffset / 300.0).clamp(0.0, 1.0);
    final double opacity = (1.0 - (unlockProgress * 0.85)).clamp(0.0, 1.0);

    final timeHour = _currentTime.hour.toString().padLeft(2, '0');
    final timeMinute = _currentTime.minute.toString().padLeft(2, '0');
    final dateFormatted =
        '${_weekdayName(_currentTime.weekday)}, ${_monthName(_currentTime.month)} ${_currentTime.day}';

    final isTabletop = widget.foldable.isTabletop;
    final isUnfolded = !widget.foldable.isFolded && screenSize.width > 550;

    return Transform.translate(
      offset: Offset(0, -currentOffset),
      child: Opacity(
        opacity: opacity,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.0, -0.2),
                radius: 1.2,
                colors: [
                  Color(0xFF0F1528), // Deep cosmic glow
                  Color(0xFF070A14), // Dark indigo void
                  Color(0xFF020306), // Pitch black OLED
                ],
                stops: [0.0, 0.55, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Ambient Celestial Halo
                Positioned(
                  top: screenSize.height * 0.16,
                  left: screenSize.width * 0.5 - 140,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0x3300E5FF),
                          const Color(0x1564B5F6),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.45, 1.0],
                      ),
                    ),
                  ),
                ),

                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Top Telemetry Status (Lock Icon & Battery)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.lock_outline_rounded, color: Color(0xFF00E5FF), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  widget.foldable.posture.name.toUpperCase(),
                                  style: const TextStyle(
                                    color: Color(0xFF00E5FF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Icon(Icons.battery_charging_full_rounded, color: Colors.white70, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '92%',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const Spacer(flex: 2),

                        // Centerpiece Cosmic Clock
                        if (isUnfolded && !isTabletop)
                          // Wide Main Screen layout: Side-by-side time & widget
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$timeHour:$timeMinute',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 82,
                                      fontWeight: FontWeight.w100,
                                      letterSpacing: -2.0,
                                      height: 1.0,
                                      shadows: [
                                        Shadow(color: Color(0x7700E5FF), blurRadius: 28),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    dateFormatted.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.65),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 3.0,
                                    ),
                                  ),
                                ],
                              ),
                              _ambientCosmicOrb(),
                            ],
                          )
                        else
                          // Portrait / Folded / Cover screen layout
                          Column(
                            children: [
                              Text(
                                '$timeHour:$timeMinute',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: isTabletop ? 56 : 74,
                                  fontWeight: FontWeight.w100,
                                  letterSpacing: -2.0,
                                  height: 1.0,
                                  shadows: const [
                                    Shadow(color: Color(0x6600E5FF), blurRadius: 24),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                dateFormatted.toUpperCase(),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 2.8,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _ambientStatusChip(),
                            ],
                          ),

                        const Spacer(flex: 3),

                        // Bottom Swipe to Unlock indicator
                        Column(
                          children: [
                            const Icon(
                              Icons.keyboard_arrow_up_rounded,
                              color: Color(0xFF00E5FF),
                              size: 26,
                            ),
                            Text(
                              'SWIPE UP TO ENTER GALAXY',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Bottom Quick Shortcut Docks (Phone & Camera)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _quickActionCircle(
                              icon: Icons.phone_rounded,
                              onTap: () => _launchQuickApp('com.android.phone'),
                            ),
                            _quickActionCircle(
                              icon: Icons.camera_alt_rounded,
                              onTap: () => _launchQuickApp('com.android.camera'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _ambientStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x3310172C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x3300E5FF), width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wb_sunny_rounded, color: Color(0xFFFFD54F), size: 16),
          const SizedBox(width: 8),
          Text(
            '72°F  •  Solar Flares Mild  •  All Systems Nominal',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _ambientCosmicOrb() {
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0E1426),
        border: Border.all(color: const Color(0x5500E5FF), width: 1.5),
        boxShadow: const [
          BoxShadow(color: Color(0x3300E5FF), blurRadius: 24, spreadRadius: 2),
        ],
      ),
      child: const Center(
        child: Icon(
          Icons.brightness_3_rounded,
          color: Color(0xFF00E5FF),
          size: 44,
        ),
      ),
    );
  }

  Widget _quickActionCircle({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x5511172A),
          border: Border.all(color: const Color(0x44FFFFFF), width: 1.0),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 12),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  String _weekdayName(int day) {
    const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return names[(day - 1) % 7];
  }

  String _monthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[(month - 1) % 12];
  }
}
