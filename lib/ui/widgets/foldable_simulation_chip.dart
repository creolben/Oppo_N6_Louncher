import 'package:flutter/material.dart';
import '../../core/foldable_controller.dart';

/// Compact "SIMULATED" chip shown while the in-app posture simulator is
/// overriding the hardware hinge sensor. Tapping it hands control back to the
/// sensor, so a simulated posture can never become a dead end.
class FoldableSimulationChip extends StatelessWidget {
  final FoldableController foldable;
  final double fontSize;

  const FoldableSimulationChip({
    super.key,
    required this.foldable,
    this.fontSize = 9.5,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Release the simulator and follow the hardware hinge sensor',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: foldable.clearSimulation,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0x3300E5FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF), width: 0.9),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.sensors_rounded,
                  color: Color(0xFF00E5FF),
                  size: 12,
                ),
                const SizedBox(width: 4),
                Text(
                  'SIMULATED',
                  style: TextStyle(
                    color: const Color(0xFF00E5FF),
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
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
