import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================
/// Vortex Labs Global WebSocket Service
/// ============================================================
/// Single persistent WebSocket connection shared across all screens.
///
/// Flow:
///   Login → WebSocketService.connect(token) → subscribe → screens listen
///
/// Usage:
///   // Connect after login:
///   await WebSocketService.connect();
///
///   // Listen to device list (HomeScreen):
///   WebSocketService.deviceListStream.listen((devices) { ... });
///
///   // Listen to device detail (DeviceDetailScreen / ManualControlScreen):
///   WebSocketService.subscribeTo('device_detail', deviceId: 'VA202601001');
///   WebSocketService.deviceDetailStream.listen((data) { ... });
///
///   // Disconnect on logout:
///   WebSocketService.disconnect();
/// ============================================================

class WebSocketService {
  // ---- Configuration ----
  static const String _wsHost = '82.29.161.52';
  static const int _wsPort = 8085;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const int _maxReconnectAttempts = 5;

  // ---- Connection State ----
  static IOWebSocketChannel? _channel;
  static bool _isConnected = false;
  static bool _isConnecting = false;
  static int _reconnectAttempts = 0;
  static Timer? _reconnectTimer;
  static String? _currentSubscription;
  static String? _currentDeviceId;

  // ---- Stream Controllers ----
  /// Broadcasts connection status changes (true = connected, false = disconnected)
  static final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  /// Broadcasts device list data from 'devices_data' events
  static final StreamController<List<dynamic>> _deviceListController =
      StreamController<List<dynamic>>.broadcast();

  /// Broadcasts single device detail data from 'device_detail' events
  static final StreamController<Map<String, dynamic>> _deviceDetailController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcasts device schedule data from 'device_schedule' events
  static final StreamController<Map<String, dynamic>> _scheduleController =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Broadcasts raw messages (for debugging)
  static final StreamController<String> _rawMessageController =
      StreamController<String>.broadcast();

  // ---- Public Streams ----
  static Stream<bool> get connectionStream => _connectionController.stream;
  static Stream<List<dynamic>> get deviceListStream => _deviceListController.stream;
  static Stream<Map<String, dynamic>> get deviceDetailStream => _deviceDetailController.stream;
  static Stream<Map<String, dynamic>> get scheduleStream => _scheduleController.stream;
  static Stream<String> get rawMessageStream => _rawMessageController.stream;

  // ---- Public Getters ----
  static bool get isConnected => _isConnected;

  // ============================================================
  // CONNECT - Call after login or app restart
  // ============================================================
  static Future<bool> connect() async {
    if (_isConnected || _isConnecting) {
      print("🔌 WS: Already connected or connecting");
      return _isConnected;
    }

    _isConnecting = true;

    try {
      // Step 1: Get JWT token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');

      if (token == null) {
        print("❌ WS: No access_token found");
        _isConnecting = false;
        return false;
      }

      print("🔌 WS: Connecting to $_wsHost:$_wsPort...");

      // Step 2: Connect with Authorization header
      _channel = IOWebSocketChannel.connect(
        'ws://$_wsHost:$_wsPort',
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      // Step 3: Wait for connection
      await _channel!.ready;

      print("✅ WS: Connected!");
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionController.add(true);

      // Step 4: Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print("❌ WS: Stream error: $error");
          _handleDisconnect();
        },
        onDone: () {
          print("🔌 WS: Connection closed (code: ${_channel?.closeCode}, reason: ${_channel?.closeReason})");
          _handleDisconnect();
        },
      );

      // Step 5: Re-subscribe if we had a previous subscription (reconnect case)
      if (_currentSubscription != null) {
        subscribeTo(_currentSubscription!, deviceId: _currentDeviceId);
      }

      return true;
    } catch (e) {
      print("❌ WS: Connection failed: $e");
      _isConnected = false;
      _isConnecting = false;
      _connectionController.add(false);
      _scheduleReconnect();
      return false;
    }
  }

  // ============================================================
  // SUBSCRIBE - Switch what data the server pushes
  // ============================================================
  /// Subscribe to 'device_list' or 'device_detail'
  ///
  /// Examples:
  ///   WebSocketService.subscribeTo('device_list');
  ///   WebSocketService.subscribeTo('device_detail', deviceId: 'VA202601001');
  static void subscribeTo(String process, {String? deviceId}) {
    _currentSubscription = process;
    _currentDeviceId = deviceId;

    if (!_isConnected || _channel == null) {
      print("⚠️ WS: Not connected, will subscribe when connected");
      return;
    }

    final msg = jsonEncode({
      'event': 'subscribe',
      'process': process,
      if (deviceId != null) 'device_id': deviceId,
    });

    print("📤 WS: Subscribing → $msg");
    _channel!.sink.add(msg);
  }

  // ============================================================
  // DISCONNECT - Call on logout
  // ============================================================
  static void disconnect() {
    print("🔌 WS: Disconnecting...");
    _reconnectTimer?.cancel();
    _reconnectAttempts = 0;
    _currentSubscription = null;
    _currentDeviceId = null;

    _channel?.sink.close(status.goingAway);
    _channel = null;
    _isConnected = false;
    _isConnecting = false;
    _connectionController.add(false);
  }

  // ============================================================
  // INTERNAL: Handle incoming messages
  // ============================================================
  static void _handleMessage(dynamic message) {
    final msgStr = message.toString();
    print("📥 WS: $msgStr");
    _rawMessageController.add(msgStr);

    try {
      final data = jsonDecode(msgStr);
      final event = data['event'];

      switch (event) {
        // ---- Device List Update ----
        case 'devices_data':
          final List<dynamic> deviceList = data['device_list'] ?? [];
          print("📊 WS: Received ${deviceList.length} devices");
          _deviceListController.add(deviceList);
          break;

        // ---- Device Detail Update ----
        case 'device_detail':
          final Map<String, dynamic> deviceData = data['data'] ?? {};
          print("📊 WS: Received detail for device ${data['device_id']}");
          _deviceDetailController.add(deviceData);
          break;

        // ---- Device Schedule Update ----
        case 'device_schedule':
          print("📅 WS: Received schedule for device ${data['device_id']}");
          _scheduleController.add(Map<String, dynamic>.from(data));
          break;

        // ---- Error from server ----
        default:
          if (data.containsKey('error')) {
            print("⚠️ WS: Server error: ${data['error']}");
          } else {
            print("⚠️ WS: Unknown event: $event");
          }
      }
    } catch (e) {
      print("❌ WS: Parse error: $e");
    }
  }

  // ============================================================
  // INTERNAL: Handle disconnection & auto-reconnect
  // ============================================================
  static void _handleDisconnect() {
    _isConnected = false;
    _isConnecting = false;
    _channel = null;
    _connectionController.add(false);
    _scheduleReconnect();
  }

  static void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print("❌ WS: Max reconnect attempts reached ($_maxReconnectAttempts)");
      return;
    }

    _reconnectAttempts++;
    print("🔄 WS: Reconnecting in ${_reconnectDelay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)...");

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectDelay, () {
      connect();
    });
  }

  // ============================================================
  // CLEANUP - Call when app is fully closing
  // ============================================================
  static void dispose() {
    disconnect();
    _connectionController.close();
    _deviceListController.close();
    _deviceDetailController.close();
    _scheduleController.close();
    _rawMessageController.close();
  }
}