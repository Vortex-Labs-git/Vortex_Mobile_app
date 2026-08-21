import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// MODE TOGGLE CARD
// =============================================================================
// Switch between Manual and Schedule mode. Sends the new value to the parent
// via [onModeChanged]. Shows a spinner while [isSwitching] is true (parent is
// waiting for the server to confirm the mode change).
// =============================================================================

class ModeToggleCard extends StatelessWidget {
  final bool isAutomateMode;
  final bool isScheduleMode;
  final bool isSensorMode;
  final bool isSwitching;
  final ValueChanged<bool> onAutomateChanged;
  final ValueChanged<bool> onScheduleChanged;
  final ValueChanged<bool> onSensorChanged;

  const ModeToggleCard({
    super.key,
    required this.isAutomateMode,
    required this.isScheduleMode,
    required this.isSensorMode,
    required this.isSwitching,
    required this.onAutomateChanged,
    required this.onScheduleChanged,
    required this.onSensorChanged,
  });

  static const Color _manualColor = GlassTokens.primary;
  static const Color _scheduleColor = GlassTokens.warning;
  static const Color _sensorColor = GlassTokens.info;

  /// One-line description of the mode the current switches add up to.
  String get _modeSummary {
    if (!isAutomateMode) return 'You control the valve position';
    if (isScheduleMode && isSensorMode) {
      return 'Schedule + Sensor — schedule with sensor override';
    }
    if (isScheduleMode) return 'Schedule — valve follows the schedule';
    if (isSensorMode) return 'Sensor — valve follows sensor readings';
    return 'Pick Schedule, Sensor, or both';
  }

    @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─────────────────────────────────────────────────────────────
            // Header
            // ─────────────────────────────────────────────────────────────
            Text(
              'Control method',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: GlassTokens.textSecondary,
              ),
            ),

            const SizedBox(height: 12),

            // ─────────────────────────────────────────────────────────────
            // Master row: icon | Manual / Automate | switch
            // ─────────────────────────────────────────────────────────────
            Row(
              children: [
                _iconBox(
                  icon: isAutomateMode ? Icons.auto_mode : Icons.pan_tool,
                  color: isAutomateMode ? _scheduleColor : _manualColor,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _modeLabel('Manual', !isAutomateMode, _manualColor),
                          Text(
                            '  /  ',
                            style: TextStyle(
                              fontSize: 14,
                              color: GlassTokens.textMuted,
                            ),
                          ),
                          _modeLabel('Automate', isAutomateMode, _scheduleColor),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _modeSummary,
                        style: TextStyle(
                          fontSize: 11,
                          color: GlassTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // Switch, or the spinner while a request is out
                if (isSwitching)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch(
                    value: isAutomateMode,
                    activeColor: _scheduleColor,
                    inactiveThumbColor: _manualColor,
                    inactiveTrackColor: _manualColor.withValues(alpha: 0.3),
                    onChanged: onAutomateChanged,
                  ),
              ],
            ),

            // ─────────────────────────────────────────────────────────────
            // Automation section — only while Automate is on
            // ─────────────────────────────────────────────────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: isAutomateMode
                  ? Column(
                      children: [
                        const SizedBox(height: 8),
                        Divider(
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1,
                        ),
                        _automationRow(
                          icon: Icons.calendar_month,
                          color: _scheduleColor,
                          label: 'Schedule',
                          description: 'Open and close at set times',
                          value: isScheduleMode,
                          onChanged: onScheduleChanged,
                        ),
                        Divider(
                          color: Colors.white.withValues(alpha: 0.55),
                          height: 1,
                        ),
                        _automationRow(
                          icon: Icons.sensors,
                          color: _sensorColor,
                          label: 'Sensor',
                          description: 'React to sensor readings',
                          value: isSensorMode,
                          onChanged: onSensorChanged,
                        ),
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: one automation row (icon | label + description | switch)
  // ───────────────────────────────────────────────────────────────────────
  Widget _automationRow({
    required IconData icon,
    required Color color,
    required String label,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: value ? color : GlassTokens.textMuted),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: value ? FontWeight.bold : FontWeight.normal,
                    color: value ? color : GlassTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: GlassTokens.textMuted),
                ),
              ],
            ),
          ),

          Switch(
            value: value,
            activeColor: color,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: GlassTokens.textMuted.withValues(alpha: 0.25),
            // Locked while a request is in flight.
            onChanged: isSwitching ? null : onChanged,
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: "Manual" / "Automate" label, bold + coloured when active
  // ───────────────────────────────────────────────────────────────────────
  Widget _modeLabel(String text, bool isActive, Color activeColor) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        fontSize: 14,
        color: isActive ? activeColor : GlassTokens.textMuted,
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: rounded icon tile for the master row
  // ───────────────────────────────────────────────────────────────────────
  Widget _iconBox({required IconData icon, required Color color}) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}