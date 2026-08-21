import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

import '../../../models/valve_device.dart';
import '../utils/schedule_utils.dart';

/// Shows the add/edit schedule dialog.
///
/// Pass the existing entry as [initial] to edit it; omit it to add a new one.
/// Returns the entry, or null if the user cancelled.
Future<ScheduleEntry?> showScheduleEntryDialog(
  BuildContext context, {
  ScheduleEntry? initial,
}) {
  final existing = initial;
  final isEditing = existing != null;

  String selectedDay = existing?.day ?? kScheduleDayOptions.first;
  TimeOfDay startTime = existing != null
      ? parseScheduleTime(existing.start)
      : const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay endTime = existing != null
      ? parseScheduleTime(existing.end)
      : const TimeOfDay(hour: 8, minute: 20);
  double angle = (existing?.angle ?? 90).toDouble();

  return showGlassDialog<ScheduleEntry>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // ───────────────────────────────────────────────────────────────
          // Helper: one tappable time field
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
                decoration: glassInputDecoration(labelText: label).copyWith(
                  isDense: true,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(formatScheduleTime(value),
                        style: const TextStyle(fontSize: 16)),
                    Icon(Icons.access_time, color: iconColor),
                  ],
                ),
              ),
            );
          }

          return GlassDialog(
            title: isEditing ? 'Edit Schedule' : 'Add Schedule',
            icon: Icons.schedule,
            content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: glassInputDecoration(labelText: 'Day').copyWith(
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

                  // Time range
                  Row(
                    children: [
                      Expanded(
                        child: timeField(
                          label: 'From',
                          value: startTime,
                          iconColor: GlassTokens.success,
                          onPicked: (v) => setDialogState(() => startTime = v),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: timeField(
                          label: 'To',
                          value: endTime,
                          iconColor: GlassTokens.danger,
                          onPicked: (v) => setDialogState(() => endTime = v),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Angle held during the range
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Valve angle: ${angle.round()}°',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Slider(
                    value: angle,
                    min: 0,
                    max: 90,
                    divisions: 18,              // 5° steps
                    label: '${angle.round()}°',
                    activeColor: GlassTokens.primary,
                    onChanged: (v) => setDialogState(() => angle = v),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('0° closed',
                          style: TextStyle(
                              fontSize: 11, color: GlassTokens.textMuted)),
                      const Text('90° open',
                          style: TextStyle(
                              fontSize: 11, color: GlassTokens.textMuted)),
                    ],
                  ),
                ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              GlassButton(
                label: isEditing ? 'Update' : 'Add',
                fullWidth: false,
                height: 44,
                onPressed: () {
                  final start = formatScheduleTime(startTime);
                  final end = formatScheduleTime(endTime);

                  if (start == end) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(
                        content: Text('Start and end time cannot be the same'),
                      ),
                    );
                    return;
                  }

                  Navigator.pop(
                    dialogContext,
                    ScheduleEntry(
                      day: selectedDay,
                      start: start,
                      end: end,
                      angle: angle.round(),
                    ),
                  );
                },
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
  ScheduleEntry entry,
) async {
  final confirmed = await showGlassDialog<bool>(
    context: context,
    builder: (dialogContext) => GlassDialog(
      title: 'Delete Schedule',
      icon: Icons.delete_outline,
      tint: GlassTokens.danger,
      content: Text(
        'Delete "${entry.day} — ${entry.timeRange} at ${entry.angle}°"?',
        style: const TextStyle(color: GlassTokens.textSecondary, fontSize: 15),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        GlassButton(
          label: 'Delete',
          color: GlassTokens.danger,
          fullWidth: false,
          height: 44,
          onPressed: () => Navigator.pop(dialogContext, true),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}