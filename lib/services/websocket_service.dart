import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

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
  static const int _wsPort = 8084;
  static const Duration _reconnectDelay = Duration(seconds: 3);
  static const int _maxReconnectAttempts = 5;
  static const Duration _connectTimeout = Duration(seconds: 5);

  // ---- Connection State ----
  static IOWebSocketChannel? _channel;
  static bool _isConnected = false;
  static bool _isConnecting = false;
  static int _reconnectAttempts = 0;
  static Timer? _reconnectTimer;
  static String? _currentSubscription;
  static String? _currentDeviceId;
  static bool _isRefreshing = false; // ✅ Prevent multiple refresh attempts

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

  /// Server timestamp from the latest message.
  /// Used to compare vwv_last_seen against the SERVER's clock
  /// instead of the phone's clock (avoids timezone mismatch).
  static DateTime? lastServerTimestamp;

  // ============================================================
  // CONNECT - Call after login or app restart
  // ============================================================
  /// Connect to the server WebSocket.
  /// Has a 5-second timeout so it won't hang when there's no internet
  /// (e.g., phone is connected to ESP32 hotspot).
  ///
  /// [skipExpiryCheck] - set to true when calling after a token refresh
  /// to avoid an infinite loop (connect → refresh → connect → refresh...).
  static Future<bool> connect({bool skipExpiryCheck = false}) async {
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

      // ✅ Step 1.5: Check token expiry BEFORE connecting
      // Skip this check if we just refreshed the token (avoids loop)
      if (!skipExpiryCheck && AuthService.isTokenExpired()) {
        print("🔑 WS: Token expired — attempting silent refresh before connect...");
        _isConnecting = false;
        final success = await AuthService.refreshTokenAndReconnect();
        return success;
      }

      print("🔌 WS: Connecting to $_wsHost:$_wsPort...");
      return await _connectWithToken(token);
    } on TimeoutException catch (e) {
      print("⏱️ WS: $e");
      _isConnected = false;
      _isConnecting = false;
      _channel?.sink.close();
      _channel = null;
      _connectionController.add(false);
      // Don't auto-reconnect on timeout — user may be in AP mode intentionally
      return false;
    } catch (e) {
      print("❌ WS: Connection failed: $e");
      _isConnected = false;
      _isConnecting = false;
      _connectionController.add(false);
      _scheduleReconnect();
      return false;
    }
  }

  /// Internal: connect using a specific token
  static Future<bool> _connectWithToken(String token) async {
    try {
      // Connect with Authorization header
      _channel = IOWebSocketChannel.connect(
        'ws://$_wsHost:$_wsPort',
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      // Wait for connection WITH TIMEOUT
      await _channel!.ready.timeout(
        _connectTimeout,
        onTimeout: () {
          throw TimeoutException(
            'WebSocket connection timed out after ${_connectTimeout.inSeconds}s',
          );
        },
      );

      print("✅ WS: Connected!");
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _isRefreshing = false;
      _connectionController.add(true);

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print("❌ WS: Stream error: $error");
          _handleDisconnect();
        },
        onDone: () {
          final closeCode = _channel?.closeCode;
          final closeReason = _channel?.closeReason;
          print("🔌 WS: Connection closed (code: $closeCode, reason: $closeReason)");

          // ✅ Detect auth rejection: common close codes for auth failure
          // 4001/4003 = custom auth codes, 1008 = policy violation, 403 in reason
          if (closeCode == 4001 ||
              closeCode == 4003 ||
              closeCode == 1008 ||
              (closeReason != null &&
                  (closeReason.toLowerCase().contains('auth') ||
                      closeReason.toLowerCase().contains('token') ||
                      closeReason.toLowerCase().contains('expired') ||
                      closeReason.toLowerCase().contains('unauthorized')))) {
            print("🔑 WS: Auth rejection detected — attempting token refresh...");
            _handleAuthRejection();
            return;
          }

          _handleDisconnect();
        },
      );

      // Re-subscribe if we had a previous subscription (reconnect case)
      if (_currentSubscription != null) {
        subscribeTo(_currentSubscription!, deviceId: _currentDeviceId);
      }

      return true;
    } on TimeoutException {
      rethrow;
    } catch (e) {
      rethrow;
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
        case 'device_basic_detail':
          final Map<String, dynamic> deviceData = data['data'] != null
              ? Map<String, dynamic>.from(data['data'])
              : Map<String, dynamic>.from(data);
          print(
              "📊 WS: Received basic detail for ${data['device_id'] ?? data['id']}");
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
            final errorMsg = data['error'].toString().toLowerCase();
            print("⚠️ WS: Server error: ${data['error']}");

            // ✅ Detect auth errors in message payload
            if (errorMsg.contains('token') ||
                errorMsg.contains('auth') ||
                errorMsg.contains('expired') ||
                errorMsg.contains('unauthorized') ||
                errorMsg.contains('jwt')) {
              print("🔑 WS: Auth error in message — refreshing token...");
              _handleAuthRejection();
            }
          } else {
            print("⚠️ WS: Unknown event: $event");
          }
      }
    } catch (e) {
      print("❌ WS: Parse error: $e");
    }
  }

  // ============================================================
  // INTERNAL: Handle auth rejection — refresh token and reconnect
  // ============================================================
  static Future<void> _handleAuthRejection() async {
    if (_isRefreshing) {
      print("🔑 WS: Already refreshing, skipping...");
      return;
    }
    _isRefreshing = true;
    _isConnected = false;
    _isConnecting = false;
    _channel = null;
    _connectionController.add(false);

    print("🔑 WS: Attempting token refresh and reconnect...");
    final success = await AuthService.refreshTokenAndReconnect();

    if (success) {
      print("✅ WS: Token refreshed and reconnected!");
      // Re-subscribe to whatever we were listening to
      if (_currentSubscription != null) {
        subscribeTo(_currentSubscription!, deviceId: _currentDeviceId);
      }
    } else {
      print("❌ WS: Token refresh failed — user may need to re-login");
      _isRefreshing = false;
      // Don't schedule normal reconnect — it would fail with same expired token
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
  // RESET: Reset reconnect counter (call when network changes)
  // ============================================================
  /// Reset the reconnect attempt counter.
  /// Call this when the phone switches back to a network with internet
  /// so it can try connecting to the server again.
  static void resetReconnectAttempts() {
    _reconnectAttempts = 0;
    _isRefreshing = false; // ✅ Also reset refresh flag
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