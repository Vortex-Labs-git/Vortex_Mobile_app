// =============================================================================
// VALVE UTILS
// =============================================================================
// Pure helper functions shared by the device detail screen and its controllers.
// No widgets, no state, no side effects — safe to unit test.
// =============================================================================

/// A valve is considered "open" at or above this angle.
const int kValveOpenAngle = 45;

/// A device counts as online when its last heartbeat is at most this old.
const Duration kDeviceOnlineWindow = Duration(seconds: 30);

/// True when [lastSeen] (an ISO-8601 timestamp from `vwv_last_seen`) is recent
/// enough for the device to count as online.
bool isDeviceOnline(String? lastSeen) {
  if (lastSeen == null || lastSeen.isEmpty || lastSeen == 'NULL') {
    return false;
  }
  try {
    final lastSeenTime = DateTime.parse(lastSeen);
    return DateTime.now().difference(lastSeenTime) <= kDeviceOnlineWindow;
  } catch (e) {
    print("⚠️ Error parsing vwv_last_seen: $e");
    return false;
  }
}

/// Reads an angle out of a raw field that may be an int, a numeric String or
/// null. Returns [fallback] when the value can't be parsed.
///
/// Use `fallback: -1` when null must NOT be mistaken for a real 0° position
/// (e.g. comparing against a pending target angle).
int parseAngle(Object? raw, {int fallback = 0}) {
  if (raw is int) return raw;
  return int.tryParse((raw ?? '').toString()) ?? fallback;
}
