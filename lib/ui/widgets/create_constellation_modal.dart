import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/app_entry.dart';
import '../../core/galaxy_layout_engine.dart';
import '../../core/galaxy_storage_service.dart';

class CreateConstellationModal extends StatefulWidget {
  final GalaxyLayoutEngine layoutEngine;
  final List<AppEntry> allApps;
  final VoidCallback onCreated;

  const CreateConstellationModal({
    super.key,
    required this.layoutEngine,
    required this.allApps,
    required this.onCreated,
  });

  @override
  State<CreateConstellationModal> createState() => _CreateConstellationModalState();
}

class _CreateConstellationModalState extends State<CreateConstellationModal> {
  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedPackages = {};
  Color _selectedColor = const Color(0xFF00E5FF);
  IconData _selectedIcon = Icons.auto_awesome_rounded;
  String _searchQuery = '';

  static const List<Color> _paletteHues = [
    Color(0xFF00E5FF), // Cyber Cyan
    Color(0xFFFF4081), // Vivid Rose
    Color(0xFF00E676), // Emerald Mint
    Color(0xFFBA68C8), // Violet Quasar
    Color(0xFFFFAB00), // Amber Gold
    Color(0xFFFF5252), // Solar Flare
    Color(0xFF40C4FF), // Azure Sky
    Color(0xFFE040FB), // Neon Purple
  ];

  static const List<IconData> _emblemIcons = [
    Icons.auto_awesome_rounded,
    Icons.rocket_launch_rounded,
    Icons.sports_esports_rounded,
    Icons.workspaces_rounded,
    Icons.favorite_rounded,
    Icons.menu_book_rounded,
    Icons.music_note_rounded,
    Icons.attach_money_rounded,
    Icons.camera_alt_rounded,
    Icons.code_rounded,
    Icons.shield_rounded,
    Icons.satellite_alt_rounded,
  ];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _createConstellation() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final newConstellation = widget.layoutEngine.createCustomConstellation(
      name: name,
      primaryColor: _selectedColor,
      emblemIcon: _selectedIcon,
      packageNames: _selectedPackages.toList(),
    );

    widget.layoutEngine.expandOnly(newConstellation.id);
    widget.onCreated();

    // Persist to storage
    final customConfigs = widget.layoutEngine.constellations
        .where((c) => c.isCustom)
        .map((c) => CustomConstellationConfig(
              id: c.id,
              name: c.name,
              primaryColorValue: c.primaryColor.toARGB32(),
              emblemIconCodePoint: c.emblemIcon.codePoint,
              packageNames: c.apps.map((a) => a.packageName).toList(),
            ))
        .toList();

    GalaxyStorageService.saveConfig(
      coreAppPackageNames: widget.layoutEngine.corePackageNames,
      customConstellations: customConfigs,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final filteredApps = widget.allApps.where((app) {
      if (_searchQuery.isNotEmpty) {
        return app.label.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            app.packageName.toLowerCase().contains(_searchQuery.toLowerCase());
      }
      return true;
    }).toList();

    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Center(
        child: Container(
          width: 360,
          height: 620,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xEE0B0E1E),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _selectedColor.withValues(alpha: 0.5), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: _selectedColor.withValues(alpha: 0.25),
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _selectedColor.withValues(alpha: 0.18),
                        border: Border.all(color: _selectedColor.withValues(alpha: 0.6)),
                      ),
                      child: Icon(_selectedIcon, color: _selectedColor, size: 22),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Create New Constellation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 22),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Name Input
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14192E),
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: _selectedColor.withValues(alpha: 0.4)),
                  ),
                  child: TextField(
                    controller: _nameController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Constellation Name (e.g. Crypto, Reading...)',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      prefixIcon: Icon(Icons.drive_file_rename_outline_rounded, color: _selectedColor, size: 20),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Color Palette
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _paletteHues.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final c = _paletteHues[index];
                      final isSel = _selectedColor == c;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSel ? Colors.white : Colors.transparent,
                              width: 2.0,
                            ),
                            boxShadow: isSel
                                ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 10)]
                                : null,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Emblem Icon Selector
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _emblemIcons.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final ic = _emblemIcons[index];
                      final isSel = _selectedIcon == ic;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedIcon = ic),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSel ? _selectedColor.withValues(alpha: 0.25) : const Color(0xFF14192E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSel ? _selectedColor : Colors.white12,
                            ),
                          ),
                          child: Icon(ic, color: isSel ? _selectedColor : Colors.white60, size: 20),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 12),

                // Search Apps Input
                Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14192E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    onChanged: (q) => setState(() => _searchQuery = q),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Select stars to assign (${_selectedPackages.length}/8)...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white54, size: 18),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                // Selectable Apps List
                Expanded(
                  child: ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = filteredApps[index];
                      final isSelected = _selectedPackages.contains(app.packageName);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? _selectedColor.withValues(alpha: 0.15)
                              : const Color(0xFF121628).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? _selectedColor.withValues(alpha: 0.6) : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: app.accentColor.withValues(alpha: 0.15),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: app.iconBytes != null
                                  ? Image.memory(app.iconBytes!, fit: BoxFit.cover)
                                  : Icon(app.fallbackIcon, color: app.accentColor, size: 18),
                            ),
                          ),
                          title: Text(
                            app.label,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          trailing: Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            color: isSelected ? _selectedColor : Colors.white24,
                            size: 20,
                          ),
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedPackages.remove(app.packageName);
                              } else {
                                if (_selectedPackages.length >= 8) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Constellations hold up to 8 stars to maintain clean orbital spacing.'),
                                      duration: Duration(seconds: 2),
                                      backgroundColor: Color(0xFF161B30),
                                    ),
                                  );
                                  return;
                                }
                                _selectedPackages.add(app.packageName);
                              }
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 10),

                // Create Constellation Button
                SizedBox(
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedColor,
                      foregroundColor: const Color(0xFF0B0E1E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
                    ),
                    onPressed: _nameController.text.trim().isNotEmpty ? _createConstellation : null,
                    child: Text(
                      'Launch ${_nameController.text.trim().isNotEmpty ? _nameController.text.trim() : "Constellation"} (${_selectedPackages.length}/8 stars)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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

/// Backwards compatibility alias
typedef CreateGalaxyModal = CreateConstellationModal;
