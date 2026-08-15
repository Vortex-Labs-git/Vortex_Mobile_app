import 'dart:convert';

import 'package:flutter/material.dart';

// =============================================================================
// SCHEDULE UTILS
// =============================================================================
// Day options, HH:mm time formatting/parsing and the parser for the
// `device_schedule` WebSocket payload. Pure functions — no widgets, no state.
// =============================================================================

/// Days offered in the add/edit schedule dialog.
const List<String> kScheduleDayOptions = [
  'Every day',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Formats a [TimeOfDay] as `HH:mm` — the format the backend stores.
String formatScheduleTime(TimeOfDay time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// Parses an `HH:mm` string back into a [TimeOfDay]. Unparseable parts fall
/// back to 0.
TimeOfDay parseScheduleTime(String timeStr) {
  final parts = timeStr.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
  );
}

/// Parses the schedule list out of a `device_schedule` WebSocket event.
///
/// The server sends:
///   {"event":"device_schedule", "device_id":"...",
///    "schedule":{ ..., "schedule":"[JSON string]", ... }}
///
/// The inner `schedule` field may be a JSON string or an already-decoded list.
///
/// Returns an empty list when the device has no schedule, and `null` when the
/// payload carries nothing usable — in that case the caller should keep the
/// list it already has.
List<Map<String, dynamic>>? parseSchedulePayload(Map<String, dynamic> data) {
  try {
    final scheduleData = data['schedule'];
    if (scheduleData == null) return null;

    final scheduleJson = scheduleData['schedule'];
    if (scheduleJson == null || scheduleJson.toString().isEmpty) {
      return [];
    }

    final List<dynamic> parsed;
    if (scheduleJson is String) {
      parsed = jsonDecode(scheduleJson);
    } else if (scheduleJson is List) {
      parsed = scheduleJson;
    } else {
      print("⚠️ Unexpected schedule format: ${scheduleJson.runtimeType}");
      return null;
    }

    return parsed.map((e) => Map<String, dynamic>.from(e)).toList();
  } catch (e) {
    print("❌ Error parsing schedule data: $e");
    return null;
  }
}
