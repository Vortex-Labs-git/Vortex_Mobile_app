import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// =============================================================================
// DEVICE CONTROL API
// =============================================================================
// Every REST call to control_device.php lives here: mode switch, valve angle,
// device rename and schedule save. Pure networking — no BuildContext, no
// widgets, no setState. Callers get a [DeviceApiResult] and decide what to show.
// =============================================================================

/// Outcome of a control_device.php call.
class DeviceApiResult {
  /// True when the server replied with `success: true`.
  final bool success;

  /// The server's `message` field (only meaningful when [success] is false).
  final String? message;

  /// Set when the request never completed (no network, bad JSON, timeout…).
  final Object? error;

  const DeviceApiResult._({
    required this.success,
    this.message,
    this.error,
  });

  const DeviceApiResult.ok() : this._(success: true);

  const DeviceApiResult.serverError(String? message)
      : this._(success: false, message: message);

  const DeviceApiResult.connectionFailed(Object error)
      : this._(success: false, error: error);

  /// True when the failure was a connection problem rather than a rejection
  /// from the server.
  bool get failedToConnect => error != null;

  /// Ready-to-display failure text for a SnackBar.
  String get displayMessage =>
      failedToConnect ? 'Connection failed: $error' : 'Error: $message';
}

class DeviceControlApi {
  DeviceControlApi._();

  static const String controlEndpoint =
      'https://vortexlabsofficial.com/vortex_app/control_device.php';

  // ---------------------------------------------------------------------------
  // Public calls
  // ---------------------------------------------------------------------------

  /// Switches the valve between Manual and Schedule control.
  static Future<DeviceApiResult> switchControlMode({
    required Object? deviceId,
    required String deviceName,
    required int angle,
    required bool scheduleMode,
  }) {
    return _post(
      logTag: 'Mode Switch',
      body: {
        'event': 'set_valve_basic',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_id': deviceId,
        'set_controller': {
          'schedule': scheduleMode,
          'sensor': false,
        },
        'valve_data': {
          'name': deviceName,
          'set_angle': true,
          'angle': angle,
        },
        'ota_update': false,
      },
    );
  }

  /// Drives the valve to [angle] (0 = closed, 90 = open).
  static Future<DeviceApiResult> setValveAngle({
    required Object? deviceId,
    required String deviceName,
    required int angle,
  }) {
    return _post(
      logTag: 'Valve Angle',
      body: {
        'event': 'set_valve_basic',
        'device_id': deviceId,
        'set_controller': {
          'schedule': false,
          'sensor': false,
        },
        'valve_data': {
          'name': deviceName,
          'set_angle': true,
          'angle': angle,
        },
      },
    );
  }

  /// Renames the device. The current [angle] and [scheduleMode] are resent
  /// unchanged so the rename doesn't move the valve or flip its mode.
  static Future<DeviceApiResult> renameDevice({
    required Object? deviceId,
    required String newName,
    required int angle,
    required bool scheduleMode,
  }) {
    return _post(
      logTag: 'Name Update',
      body: {
        'event': 'set_valve_basic',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'device_id': deviceId,
        'set_controller': {
          'schedule': scheduleMode,
          'sensor': false,
        },
        'valve_data': {
          'name': newName,
          'set_angle': true,
          'angle': angle,
        },
        'ota_update': false,
      },
    );
  }

  /// Replaces the device's stored schedule with [schedules]. An empty list
  /// turns scheduling off.
  static Future<DeviceApiResult> saveSchedule({
    required Object? deviceId,
    required List<Map<String, dynamic>> schedules,
  }) {
    return _post(
      logTag: 'Schedule',
      body: {
        'event': 'set_valve_control',
        'device_id': deviceId,
        'set_scheduledata': {
          'set_schedule': schedules.isNotEmpty,
          'schedule_info': schedules,
        },
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  static Future<DeviceApiResult> _post({
    required Map<String, dynamic> body,
    required String logTag,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      print("📤 $logTag Request: ${jsonEncode(body)}");

      final response = await http.post(
        Uri.parse(controlEndpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      print("$logTag Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        return const DeviceApiResult.ok();
      }
      return DeviceApiResult.serverError(result['message']?.toString());
    } catch (e) {
      print("$logTag Error: $e");
      return DeviceApiResult.connectionFailed(e);
    }
  }
}
