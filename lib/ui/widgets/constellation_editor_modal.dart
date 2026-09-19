import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../models/constellation.dart';
import '../../core/galaxy_layout_engine.dart';
import '../../core/galaxy_storage_service.dart';

class ConstellationEditorModal extends StatefulWidget {
  final Constellation constellation;
  final GalaxyLayoutEngine layoutEngine;
  final List<AppEntry> allApps;
  final VoidCallback onUpdated;

  const ConstellationEditorModal({
    super.key,
    required this.constellation,
    required this.layoutEngine,
    required this.allApps,
    required this.onUpdated,
  });

  @override
  State<ConstellationEditorModal> createState() => _ConstellationEditorModalState();
}

class _ConstellationEditorModalState extends State<ConstellationEditorModal> {
  late List<AppEntry> _constellationApps;
  bool get _isCore => widget.constellation.id == 'core';

  @override
  void initState() {
    super.initState();
    _constellationApps = List.from(widget.constellation.apps);
  }

  void _saveChanges() {
    final pkgNames = _constellationApps.map((a) => a.packageName).toList();
    widget.layoutEngine.setConstellationAppPackages(widget.constellation.id, pkgNames);
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
      coreAppPackageNames: widget.layoutEngine.corePackageNames,
      customGalaxies: customConfigs,
      constellationAppOverrides: widget.layoutEngine.constellationAppOverrides,
    );
  }

  void _removeApp(int index) {
    setState(() {
      _constellationApps.removeAt(index);
    });
    _saveChanges();
  }

  void _openAppPicker({int? replaceIndex}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final availableApps = widget.allApps.where((app) {
              final alreadyIn = _constellationApps.any((a) => a.packageName == app.packageName);
              if (alreadyIn &&
                  (replaceIndex == null || _constellationApps[replaceIndex].packageName != app.packageName)) {
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
                height: MediaQuery.of(context).size.height * 0.72,
                decoration: BoxDecoration(
                  color: const Color(0xEE0D1224),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border(
                    top: BorderSide(
                      color: widget.constellation.primaryColor.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
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
                          Icon(
                            widget.constellation.emblemIcon,
                            color: widget.constellation.primaryColor,
                            size: 22,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            replaceIndex != null
                                ? 'Swap Star in ${widget.constellation.name}'
                                : 'Add Star to ${widget.constellation.name}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _isCore
                                ? '${_constellationApps.length}/6 Stars'
                                : '${_constellationApps.length}/8 Stars',
                            style: TextStyle(
                              color: widget.constellation.primaryColor,
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
                          decoration: InputDecoration(
                            hintText: 'Search apps...',
                            hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                            prefixIcon: Icon(Icons.search_rounded,
                                color: widget.constellation.primaryColor, size: 20),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
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
                              trailing: Icon(
                                Icons.add_circle_outline_rounded,
                                color: widget.constellation.primaryColor,
                              ),
                              onTap: () {
                                Navigator.of(context).pop();
                                setState(() {
                                  if (replaceIndex != null && replaceIndex < _constellationApps.length) {
                                    _constellationApps[replaceIndex] = app;
                                  } else if (_isCore ? _constellationApps.length < 6 : _constellationApps.length < 8) {
                                    _constellationApps.add(app);
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
    final c = widget.constellation;

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Center(
        child: Container(
          width: 340,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78,
          ),
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xEE0B0E1E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: c.primaryColor.withValues(alpha: 0.4),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: c.primaryColor.withValues(alpha: 0.25),
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
                        color: c.primaryColor.withValues(alpha: 0.15),
                        border: Border.all(color: c.primaryColor.withValues(alpha: 0.6)),
                      ),
                      child: Icon(c.emblemIcon, color: c.primaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _isCore
                                ? '${_constellationApps.length}/6 Stars Active'
                                : '${_constellationApps.length}/8 Stars Active',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Radial View for Core, or Scrollable Grid/Wrap for outer constellations
                if (_isCore)
                  // Core Radial Visual Preview
                  SizedBox(
                    width: 230,
                    height: 230,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 165,
                          height: 165,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: c.primaryColor.withValues(alpha: 0.2),
                              width: 1.2,
                            ),
                          ),
                        ),
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [c.primaryColor, c.secondaryColor],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: c.primaryColor.withValues(alpha: 0.4),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.auto_awesome, color: Color(0xFF101424), size: 22),
                        ),
                        ...List.generate(6, (index) {
                          final angle = (index * 2 * math.pi / 6) - (math.pi / 2);
                          const radius = 82.0;
                          final offset = Offset(math.cos(angle) * radius, math.sin(angle) * radius);
                          final bool isFilled = index < _constellationApps.length;
                          final app = isFilled ? _constellationApps[index] : null;

                          return Transform.translate(
                            offset: offset,
                            child: GestureDetector(
                              onTap: () {
                                if (isFilled) {
                                  _openAppPicker(replaceIndex: index);
                                } else {
                                  _openAppPicker();
                                }
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(13),
                                      color: isFilled
                                          ? const Color(0xFF161C32)
                                          : const Color(0xFF101424).withValues(alpha: 0.5),
                                      border: Border.all(
                                        color: isFilled
                                            ? c.primaryColor.withValues(alpha: 0.7)
                                            : Colors.white24,
                                        width: 1.2,
                                      ),
                                    ),
                                    child: isFilled
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(11),
                                            child: app!.iconBytes != null
                                                ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
                                                : Icon(app.fallbackIcon, color: app.accentColor, size: 20),
                                          )
                                        : const Icon(Icons.add_rounded, color: Colors.white38, size: 20),
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
                  )
                else
                  // Outer Constellation: Scrollable App Cards + Add Button
                  Flexible(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 280),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          children: [
                            Wrap(
                              spacing: 12,
                              runSpacing: 14,
                              alignment: WrapAlignment.center,
                              children: [
                                ...List.generate(_constellationApps.length, (index) {
                                  final app = _constellationApps[index];
                                  return SizedBox(
                                    width: 62,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF161C32),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: c.primaryColor.withValues(alpha: 0.5),
                                                  width: 1.2,
                                                ),
                                              ),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: app.iconBytes != null
                                                    ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
                                                    : Icon(app.fallbackIcon,
                                                        color: app.accentColor, size: 24),
                                              ),
                                            ),
                                            Positioned(
                                              top: -4,
                                              right: -4,
                                              child: GestureDetector(
                                                onTap: () => _removeApp(index),
                                                child: Container(
                                                  padding: const EdgeInsets.all(3),
                                                  decoration: const BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Color(0xFFFF3B5C),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Color(0x66FF3B5C),
                                                        blurRadius: 4,
                                                      ),
                                                    ],
                                                  ),
                                                  child: const Icon(Icons.close_rounded,
                                                      color: Colors.white, size: 12),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          app.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),

                                // Add App Button tile (only shown if under 8-star limit)
                                if (_constellationApps.length < 8)
                                  GestureDetector(
                                    onTap: () => _openAppPicker(),
                                    child: SizedBox(
                                      width: 62,
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: c.primaryColor.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(
                                                color: c.primaryColor.withValues(alpha: 0.4),
                                                width: 1.2,
                                                style: BorderStyle.solid,
                                              ),
                                            ),
                                            child: Icon(Icons.add_rounded,
                                                color: c.primaryColor, size: 26),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Add Star',
                                            style: TextStyle(
                                              color: c.primaryColor.withValues(alpha: 0.8),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                Text(
                  _isCore
                      ? '${_constellationApps.length} of 6 slots active. Tap slot to swap or add.'
                      : '${_constellationApps.length} of 8 slots active. Tap (✕) to remove or (+) to add.',
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
                      backgroundColor: c.primaryColor,
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
