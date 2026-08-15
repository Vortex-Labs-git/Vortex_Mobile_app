import 'dart:async';

import '../../../services/esp_direct_service.dart';
import '../../../services/websocket_service.dart';

// =============================================================================
// DEVICE FEEDS
// =============================================================================
// Live-data plumbing for the device detail screen, one class per mode:
//
//   ServerDeviceFeed — cloud WebSocket: device_detail + device_schedule events
//   DirectDeviceFeed — ESP32 over its own AP: valve data stream + 2s polling
//
// Both filter events down to this device and hand the payload to callbacks.
// They own their subscriptions and timers; the screen just calls start() and
// dispose(). Deciding what to do with the data stays in the screen.
// =============================================================================

/// WebSocket feed used in server mode.
class ServerDeviceFeed {
  final String? deviceId;
  final void Function(bool connected) onConnectionChanged;
  final void Function(Map<String, dynamic> data) onDeviceUpdate;
  final void Function(Map<String, dynamic> data) onScheduleUpdate;

  ServerDeviceFeed({
    required this.deviceId,
    required this.onConnectionChanged,
    required this.onDeviceUpdate,
    required this.onScheduleUpdate,
  });

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<Map<String, dynamic>>? _scheduleSub;

  bool get isConnected => WebSocketService.isConnected;

  void start() {
    _connectionSub =
        WebSocketService.connectionStream.listen(onConnectionChanged);

    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (data['id']?.toString() == deviceId) {
        onDeviceUpdate(data);
      }
    });

    _scheduleSub = WebSocketService.scheduleStream.listen((data) {
      if (data['device_id']?.toString() == deviceId) {
        onScheduleUpdate(data);
      }
    });

    WebSocketService.subscribeTo('device_detail', deviceId: deviceId);
  }

  void dispose() {
    _connectionSub?.cancel();
    _detailSub?.cancel();
    _scheduleSub?.cancel();
    // Hand the socket back to the device list screen.
    WebSocketService.subscribeTo('device_list');
  }
}

/// ESP32-over-AP feed used in direct mode.
class DirectDeviceFeed {
  /// Live view of the device map — read on every poll so a rename is picked up.
  final Map<String, dynamic> Function() device;
  final void Function(bool connected) onConnectionChanged;

  /// Receives the `get_valvedata` sub-map of each ESP32 push.
  final void Function(Map<String, dynamic> valveData) onValveData;

  DirectDeviceFeed({
    required this.device,
    required this.onConnectionChanged,
    required this.onValveData,
  });

  static const Duration _pollInterval = Duration(seconds: 2);

  /// Delay before re-reading the valve after a command, so the ESP32 has a
  /// moment to actually move.
  static const Duration _postCommandRefreshDelay = Duration(milliseconds: 500);

  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Map<String, dynamic>>? _valveDataSub;
  Timer? _pollTimer;
  bool _disposed = false;

  EspDirectService get _esp => EspDirectService.instance;

  bool get isConnected => _esp.isConnected;

  String get _deviceName =>
      device()['vwv_name'] ?? device()['device_name'] ?? 'Valve';

  void start() {
    _connectionSub = _esp.connectionStream.listen(onConnectionChanged);

    _valveDataSub = _esp.valveDataStream.listen((data) {
      final raw = data['get_valvedata'];
      final valveData =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      print("📱 ESP32 Direct: valve data $valveData");
      onValveData(valveData);
    });

    requestValveData();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_esp.isAuthenticated) requestValveData();
    });
  }

  /// Asks the ESP32 for the current valve state.
  void requestValveData() {
    if (_disposed || !_esp.isAuthenticated) return;

    final data = device();
    _esp.requestValveData(
      userId: data['user_id']?.toString() ?? 'app_user',
      deviceId: data['id']?.toString() ?? '',
      deviceName: _deviceName,
    );
  }

  /// Sends an angle command straight to the ESP32, then re-reads the valve.
  void setValveAngle(int angle) {
    print("📤 ESP32 Direct: set_valve_basic angle=$angle");
    _esp.setValveAngle(angle: angle, deviceName: _deviceName);

    Future.delayed(_postCommandRefreshDelay, requestValveData);
  }

  void dispose() {
    _disposed = true;
    _connectionSub?.cancel();
    _valveDataSub?.cancel();
    _pollTimer?.cancel();
  }
}
