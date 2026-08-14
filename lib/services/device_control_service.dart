import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/env.dart';

// =============================================================================
// DEVICE CONTROL SERVICE  (cloud REST — valve commands)
// =============================================================================
// Owns every REST call to control_device.php. Previously these lived inline in
// DeviceDetailScreen — five copies of the same request, each re-reading the
// token and rebuilding the same headers by hand.
//
// SCOPE — this is the CLOUD half only.
//   Cloud commands  → here (REST over the internet, JWT auth)
//   Direct commands → EspDirectService (WebSocket to the valve's own AP)
//   The screen decides which one to call based on isDirectMode.
//
// CONTRACT — the service does network, never UI. It returns a ControlResult
// and never touches BuildContext, snackbars, or setState. Callers render the
// outcome however they like.
//
// WIRE FORMAT — deliberately preserved byte-for-byte from the original inline
// calls. Note that mode-switch and rename send `timestamp` + `ota_update`
// while the plain angle/state commands do NOT. That asymmetry is inherited
// from the existing backend contract, so [includeMeta] keeps it explicit
// rather than silently normalising it. Verify against the PHP before changing.
// =============================================================================

/// Outcome of a control request. Carries no Flutter types on purpose.
///
/// Two distinct failure kinds, because the UI words them differently:
///   [ControlResult.rejected] — reached the server, it said no  → "Error: …"
///   [ControlResult.error]    — never got a usable reply        → "Connection failed: …"
class ControlResult {
  final bool success;

  /// Server-provided message on rejection, or the exception text on error.
  /// Null on success.
  final String? message;

  /// True when the request never completed (timeout, socket, bad JSON).
  final bool isNetworkError;

  const ControlResult.ok()
      : success = true,
        message = null,
        isNetworkError = false;

  const ControlResult.rejected(this.message)
      : success = false,
        isNetworkError = false;

  const ControlResult.error(this.message)
      : success = false,
        isNetworkError = true;

  /// Ready-to-show failure text, matching the strings the screens used inline.
  String get displayMessage =>
      isNetworkError ? 'Connection failed: $message' : 'Error: $message';
}

class DeviceControlService {
  DeviceControlService._();
  static final DeviceControlService instance = DeviceControlService._();

  // ---------------------------------------------------------------------------
  // INTERNALS
  // ---------------------------------------------------------------------------

  /// The one place the access token is read for REST calls.
  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Single POST + decode path shared by every command below.
  Future<ControlResult> _post(
    Map<String, dynamic> body, {
    required String logLabel,
  }) async {
    try {
      print("📤 $logLabel Request: ${jsonEncode(body)}");

      final response = await http.post(
        Uri.parse(Env.controlDeviceUrl),
        headers: await _headers(),
        body: jsonEncode(body),
      );

      print("$logLabel Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        return const ControlResult.ok();
      }
      return ControlResult.rejected(result['message']?.toString());
    } catch (e) {
      print("$logLabel Error: $e");
      return ControlResult.error(e.toString());
    }
  }

  // ---------------------------------------------------------------------------
  // COMMANDS
  // ---------------------------------------------------------------------------

  /// `set_valve_basic` — covers open/close, angle, mode switch and rename.
  ///
  /// [includeMeta] adds `timestamp` + `ota_update`, which the mode-switch and
  /// rename calls send and the angle/state calls do not (see header note).
  Future<ControlResult> setValveBasic({
    required dynamic deviceId,
    required String name,
    required int angle,
    required bool scheduleMode,
    bool includeMeta = false,
    String logLabel = 'Valve',
  }) {
    final body = <String, dynamic>{
      'event': 'set_valve_basic',
      if (includeMeta) 'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': deviceId,
      'set_controller': {
        'schedule': scheduleMode,
        'sensor': false,
      },
      'valve_data': {
        'name': name,
        'set_angle': true,
        'angle': angle,
      },
      if (includeMeta) 'ota_update': false,
    };

    return _post(body, logLabel: logLabel);
  }

  /// `set_valve_control` — pushes the full schedule list for a device.
  Future<ControlResult> setSchedule({
    required dynamic deviceId,
    required List<Map<String, dynamic>> schedules,
  }) {
    return _post(
      {
        'event': 'set_valve_control',
        'device_id': deviceId,
        'set_scheduledata': {
          'set_schedule': schedules.isNotEmpty,
          'schedule_info': schedules,
        },
      },
      logLabel: '📅 Schedule',
    );
  }
}
