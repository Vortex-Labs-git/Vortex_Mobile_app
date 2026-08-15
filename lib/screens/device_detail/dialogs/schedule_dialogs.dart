import 'package:flutter/material.dart';

import '../utils/schedule_utils.dart';

// =============================================================================
// SCHEDULE DIALOGS
// =============================================================================
// Add/edit dialog and delete confirmation for a single schedule entry.
// Both are self-contained: they own their dialog-local state and return the
// user's answer. Nothing is saved here — the caller updates its list and the
// screen's "Save Schedule" button pushes it to the server.
// =============================================================================

/// Shows the add/edit schedule dialog.
///
/// Pass the existing entry as [initial] to edit it; omit it to add a new one.
/// Returns the entry as `{day, open, close}`, or null if the user cancelled.
Future<Map<String, dynamic>?> showScheduleEntryDialog(
  BuildContext context, {
  Map<String, dynamic>? initial,
}) {
  final existing = initial;
  final isEditing = existing != null;

  String selectedDay = existing?['day'] ?? kScheduleDayOptions.first;
  TimeOfDay openTime = existing != null
      ? parseScheduleTime(existing['open'] ?? '08:00')
      : const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay closeTime = existing != null
      ? parseScheduleTime(existing['close'] ?? '08:20')
      : const TimeOfDay(hour: 8, minute: 20);

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // ───────────────────────────────────────────────────────────────
          // Helper: one tappable time field (opens the platform time picker)
          // ───────────────────────────────────────────────────────────────
          Widget timeField({
            required String label,
            required TimeOfDay value,
            required Color iconColor,
            required ValueChanged<TimeOfDay> onPicked,
          }) {
            return InkWell(
              onTap: () async {
                final picked = await showTimePicker(
                  context: dialogContext,
                  initialTime: value,
                );
                if (picked != null) onPicked(picked);
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      formatScheduleTime(value),
                      style: const TextStyle(fontSize: 16),
                    ),
                    Icon(Icons.access_time, color: iconColor),
                  ],
                ),
              ),
            );
          }

          return AlertDialog(
            title: Text(isEditing ? 'Edit Schedule' : 'Add Schedule'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Day picker
                DropdownButtonFormField<String>(
                  value: selectedDay,
                  decoration: const InputDecoration(
                    labelText: 'Day',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: kScheduleDayOptions
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedDay = val);
                  },
                ),

                const SizedBox(height: 16),

                timeField(
                  label: 'Open Time',
                  value: openTime,
                  iconColor: Colors.green[600]!,
                  onPicked: (v) => setDialogState(() => openTime = v),
                ),

                const SizedBox(height: 16),

                timeField(
                  label: 'Close Time',
                  value: closeTime,
                  iconColor: Colors.red[600]!,
                  onPicked: (v) => setDialogState(() => closeTime = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext, <String, dynamic>{
                    'day': selectedDay,
                    'open': formatScheduleTime(openTime),
                    'close': formatScheduleTime(closeTime),
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                ),
                child: Text(isEditing ? 'Update' : 'Add'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Asks the user to confirm deleting [entry]. Returns true when confirmed.
Future<bool> showDeleteScheduleDialog(
  BuildContext context,
  Map<String, dynamic> entry,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete Schedule'),
      content: Text(
          'Delete "${entry['day']} — Open: ${entry['open']}, Close: ${entry['close']}"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}
