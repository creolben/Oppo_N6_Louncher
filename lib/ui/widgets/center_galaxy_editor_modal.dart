import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../core/galaxy_layout_engine.dart';
import '../../core/galaxy_storage_service.dart';

class CenterConstellationEditorModal extends StatefulWidget {
  final GalaxyLayoutEngine layoutEngine;
  final List<AppEntry> allApps;
  final VoidCallback onUpdated;

  const CenterConstellationEditorModal({
    super.key,
    required this.layoutEngine,
    required this.allApps,
    required this.onUpdated,
  });

  @override
  State<CenterConstellationEditorModal> createState() => _CenterConstellationEditorModalState();
}

/// Backwards compatibility alias
typedef CenterGalaxyEditorModal = CenterConstellationEditorModal;

class _CenterConstellationEditorModalState extends State<CenterConstellationEditorModal> {
  late List<AppEntry> _coreApps;

  @override
  void initState() {
    super.initState();
    final core = widget.layoutEngine.constellations.firstWhere((c) => c.id == 'core');
    _coreApps = List.from(core.apps);
  }

  void _saveChanges() {
    widget.layoutEngine.setCorePackageNames(_coreApps.map((a) => a.packageName).toList());
    widget.onUpdated();

    final customConfigs = widget.layoutEngine.constellations
        .where((c) => c.isCustom)
        .map((c) => CustomGalaxyConfig(
              id: c.id,
              name: c.name,
              primaryColorValue: c.primaryColor.toARGB32(),
              emblemIconCodePoint: c.emblemIcon.codePoint,
              packageNames: c.apps.map((a) => a.packageName).toList(),
            ))
        .toList();

    GalaxyStorageService.saveConfig(
      coreAppPackageNames: _coreApps.map((a) => a.packageName).toList(),
      customGalaxies: customConfigs,
    );
  }

  void _removeApp(int index) {
    setState(() {
      _coreApps.removeAt(index);
    });
    _saveChanges();
  }

  void _openAppPicker(int? replaceIndex) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableApps = widget.allApps.where((app) {
              // Don't show apps already in core (unless it's the one being replaced)
              final alreadyInCore = _coreApps.any((a) => a.packageName == app.packageName);
              if (alreadyInCore &&
                  (replaceIndex == null || _coreApps[replaceIndex].packageName != app.packageName)) {
                return false;
              }
              if (searchQuery.isNotEmpty) {
                return app.label.toLowerCase().contains(searchQuery.toLowerCase()) ||
                    app.packageName.toLowerCase().contains(searchQuery.toLowerCase());
              }
              return true;
            }).toList();

            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                height: MediaQuery.of(context).size.height * 0.70,
                decoration: const BoxDecoration(
                  color: Color(0xEE0D1224),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(color: Color(0x4400E5FF), width: 1.2),
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFFD54F), size: 22),
                          const SizedBox(width: 8),
                          Text(
                            replaceIndex != null ? 'Swap Core Star' : 'Add Star to Core Constellation',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${_coreApps.length}/6 Stars',
                            style: const TextStyle(
                              color: Color(0xFFFFD54F),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFF161B30),
                          borderRadius: BorderRadius.circular(23),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          onChanged: (q) => setModalState(() => searchQuery = q),
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Search apps...',
                            hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                            prefixIcon: Icon(Icons.search_rounded, color: Color(0xFF00E5FF), size: 20),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        physics: const BouncingScrollPhysics(),
                        itemCount: availableApps.length,
                        itemBuilder: (context, index) {
                          final app = availableApps[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF13182C).withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: app.accentColor.withValues(alpha: 0.2)),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: app.accentColor.withValues(alpha: 0.15),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: app.iconBytes != null
                                      ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
                                      : Icon(app.fallbackIcon, color: app.accentColor, size: 20),
                                ),
                              ),
                              title: Text(
                                app.label,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                app.packageName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                              trailing: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF00E5FF)),
                              onTap: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  if (replaceIndex != null && replaceIndex < _coreApps.length) {
                                    _coreApps[replaceIndex] = app;
                                  } else if (_coreApps.length < 6) {
                                    _coreApps.add(app);
                                  }
                                });
                                _saveChanges();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Center(
        child: Container(
          width: 340,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xEE0B0E1E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.4), width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33FFD54F),
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
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFFFD54F).withValues(alpha: 0.15),
                        border: Border.all(color: const Color(0xFFFFD54F).withValues(alpha: 0.6)),
                      ),
                      child: const Icon(Icons.star_rounded, color: Color(0xFFFFD54F), size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Center Constellation',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          'Max 6 Core Essentials',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Radial Visual Preview of the 6 Slots
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Center Orbit Line
                      Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFFFD54F).withValues(alpha: 0.2),
                            width: 1.2,
                          ),
                        ),
                      ),
                      // Center Solar Core Symbol
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const RadialGradient(
                            colors: [Color(0xFFFFD54F), Color(0xFFFF9800)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD54F).withValues(alpha: 0.4),
                              blurRadius: 16,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.auto_awesome, color: Color(0xFF101424), size: 24),
                      ),

                      // 6 Slots around the ring
                      ...List.generate(6, (index) {
                        final angle = (index * 2 * math.pi / 6) - (math.pi / 2);
                        const radius = 85.0;
                        final offset = Offset(math.cos(angle) * radius, math.sin(angle) * radius);

                        final bool isFilled = index < _coreApps.length;
                        final app = isFilled ? _coreApps[index] : null;

                        return Transform.translate(
                          offset: offset,
                          child: GestureDetector(
                            onTap: () {
                              if (isFilled) {
                                _openAppPicker(index); // swap
                              } else {
                                _openAppPicker(null); // add
                              }
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14),
                                    color: isFilled
                                        ? const Color(0xFF161C32)
                                        : const Color(0xFF101424).withValues(alpha: 0.5),
                                    border: Border.all(
                                      color: isFilled
                                          ? const Color(0xFFFFD54F).withValues(alpha: 0.7)
                                          : Colors.white24,
                                      width: 1.2,
                                    ),
                                  ),
                                  child: isFilled
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: app!.iconBytes != null
                                              ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
                                              : Icon(app.fallbackIcon, color: app.accentColor, size: 22),
                                        )
                                      : const Icon(Icons.add_rounded, color: Colors.white38, size: 22),
                                ),
                                if (isFilled)
                                  Positioned(
                                    top: -4,
                                    right: -4,
                                    child: GestureDetector(
                                      onTap: () => _removeApp(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFFFF3B5C),
                                        ),
                                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 12),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  '${_coreApps.length} of 6 slots active. Tap slot to swap or add.',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 18),

                // Done Button
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD54F),
                      foregroundColor: const Color(0xFF0F1424),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'Done',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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
}
