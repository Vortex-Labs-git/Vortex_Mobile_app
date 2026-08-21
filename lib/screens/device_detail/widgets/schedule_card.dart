import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

import '../../../widgets/glass/glass.dart';

import '../../../models/valve_device.dart';

// =============================================================================
// SCHEDULE CARD
// =============================================================================
// Shows the schedule table (Day | Time | Angle | delete), an "Add Schedule"
// button, and a "Save Schedule" button. All add/edit/delete dialogs and the
// REST save call live in the parent screen and are invoked through callbacks.
// =============================================================================

class ScheduleCard extends StatelessWidget {
  final List<ScheduleEntry> schedules;
  final bool isSavingSchedule;
  final bool readOnly; 
  final VoidCallback onAddPressed;
  final ValueChanged<int> onRowTapped;   // Tap a row to edit it
  final ValueChanged<int> onRowDeleted;
  final VoidCallback onSavePressed;

  const ScheduleCard({
    super.key,
    required this.schedules,
    required this.isSavingSchedule,
    this.readOnly = false, 
    required this.onAddPressed,
    required this.onRowTapped,
    required this.onRowDeleted,
    required this.onSavePressed,
  });

  // Column widths, shared by the header and every row so they stay aligned.
  static const int _dayFlex = 3;
  static const int _timeFlex = 3;
  static const int _angleFlex = 2;
  static const double _deleteWidth = 40;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // =========================================================
            // SECTION 1: HEADER ROW (title + entry count)
            // =========================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${schedules.length} entries',
                  style: TextStyle(color: GlassTokens.textMuted, fontSize: 12),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // =========================================================
            // SECTION 2: TABLE HEADER (Day | Time | Angle | _)
            // =========================================================
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: GlassTokens.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              child: const Row(
                children: [
                  Expanded(
                    flex: _dayFlex,
                    child: Center(
                      child: Text('Day',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Expanded(
                    flex: _timeFlex,
                    child: Center(
                      child: Text('Time',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  Expanded(
                    flex: _angleFlex,
                    child: Center(
                      child: Text('Angle',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  SizedBox(width: _deleteWidth), // delete button column
                ],
              ),
            ),

            // =========================================================
            // SECTION 3: SCHEDULE ROWS (or empty placeholder)
            // =========================================================
            if (schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No schedules added yet.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: GlassTokens.textMuted),
                  ),
                ),
              )
            else
              ...schedules.asMap().entries.map(
                    (e) => _buildRow(index: e.key, entry: e.value),
                  ),

            const SizedBox(height: 12),

            // =========================================================
            // SECTION 4: ADD SCHEDULE BUTTON
            // =========================================================
            Center(
              child: TextButton.icon(
                onPressed: onAddPressed,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: GlassTokens.primary,
                ),
              ),
            ),

            const SizedBox(height: 12),

            // =========================================================
            // SECTION 5: SAVE SCHEDULE BUTTON
            // =========================================================
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isSavingSchedule ? null : onSavePressed,
                icon: isSavingSchedule
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label: Text(isSavingSchedule ? 'Saving...' : 'Save Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: GlassTokens.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      GlassTokens.primary.withValues(alpha: 0.6),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // Helper: single schedule row (Day | Time | Angle | delete-icon)
  // Tapping the row body edits it; the delete icon deletes independently.
  // ───────────────────────────────────────────────────────────────────────
  Widget _buildRow({required int index, required ScheduleEntry entry}) {
    return InkWell(
      onTap: () => onRowTapped(index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.55)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: _dayFlex,
              child: Center(
                child: Text(
                  entry.day,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: _timeFlex,
              child: Center(
                child: Text(
                  '${entry.start} – ${entry.end}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: _angleFlex,
              child: Center(
                child: Text(
                  '${entry.angle}°',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _angleColor(entry.angle),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: _deleteWidth,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: GlassTokens.danger,
                onPressed: () => onRowDeleted(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Keeps the old table's colour language: green = open, red = closed,
  /// amber for anything in between.
  Color _angleColor(int angle) {
    if (angle <= 0) return GlassTokens.danger;
    if (angle >= 90) return GlassTokens.success;
    return GlassTokens.warning;
  }
}