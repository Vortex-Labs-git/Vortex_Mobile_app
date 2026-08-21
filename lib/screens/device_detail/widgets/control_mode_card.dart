import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// CONTROL MODE CARD
// =============================================================================
// Three-button selector for: manual / schedule / sensor.
// In direct mode, schedule and sensor are locked (greyed out + lock icon).
// =============================================================================

class ControlModeCard extends StatelessWidget {
  final String controlMode; // 'manual' | 'schedule' | 'sensor'
  final bool isDirectMode;
  final bool isOffline; 
  final ValueChanged<String> onModeSelected;
  final ValueChanged<String> onDisabledTap; // Called when user taps a locked option

  const ControlModeCard({
    super.key,
    required this.controlMode,
    required this.isDirectMode,
    this.isOffline = false, 
    required this.onModeSelected,
    required this.onDisabledTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────────────────────────────────────────────────────────
            // Header
            // ─────────────────────────────────────────────────────────────
            const Text(
              'Control by',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            const SizedBox(height: 16),

            // ─────────────────────────────────────────────────────────────
            // Three mode buttons
            // ─────────────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Manual button
                _buildButton(
                  mode: 'manual',
                  icon: Icons.pan_tool,
                  label: 'manual',
                  isSelected: controlMode == 'manual',
                  isDisabled: isOffline,
                ),

                // Schedule button (locked in direct mode)
                _buildButton(
                  mode: 'schedule',
                  icon: Icons.schedule,
                  label: 'schedule',
                  isSelected: controlMode == 'schedule',
                  isDisabled: isDirectMode,
                ),

                // Sensor button (locked in direct mode)
                _buildButton(
                  mode: 'sensor',
                  icon: Icons.sensors,
                  label: 'sensor',
                  isSelected: controlMode == 'sensor',
                  isDisabled: isDirectMode,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Single mode button (kept inline as a helper inside this widget — not a
  // separate file because it's only used here and has no business logic)
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildButton({
    required String mode,
    required IconData icon,
    required String label,
    required bool isSelected,
    required bool isDisabled,
  }) {
    return GestureDetector(
      onTap: isDisabled ? () => onDisabledTap(mode) : () => onModeSelected(mode),
      child: Opacity(
        opacity: isDisabled ? 0.35 : 1.0,
        child: Container(
          width: 80,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            // Selected chip stays solid so it reads as "pressed in" against
            // the surrounding glass; unselected chips are another pane.
            gradient: isSelected ? GlassTokens.accentGradient : null,
            color: isSelected ? null : Colors.white.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: isSelected ? 0.35 : 0.65),
            ),
          ),
          child: Column(
            children: [
              Icon(
                isDisabled ? Icons.lock_outline : icon,
                color: isSelected ? Colors.white : GlassTokens.textSecondary,
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : GlassTokens.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
