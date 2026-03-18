import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// ESP32 Direct Communication Service
/// 
/// Aligned with actual ESP32 firmware implementation:
///   - websocket_server_fn.c: Server lifecycle, async broadcast, URI /ws
///   - websocket_state_fn.c: Event processing, authentication, state updates
///   - WEBSOCKET_MSG_FLOW.md: Message formats and flow
///
/// Connection Flow:
///   1. Connect to ws://<ip>:<port>/ws
///   2. Authenticate with request_device_info + passkey
///   3. ESP32 responds with device_info (device_id)
///   4. Request valve data with device_basic_info
///   5. Control valve with set_valve_basic
///   6. Configure WiFi with set_valve_wifi
class EspDirectService {
  static EspDirectService? _instance;
  static EspDirectService get instance => _instance ??= EspDirectService._();
  
  EspDirectService._();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isAuthenticated = false; // ESP32 requires auth before processing commands
  String? _connectedDeviceIp;
  String? _connectedDeviceId;
  
  // Stream controllers for different event types
  final _connectionStateController = StreamController<bool>.broadcast();
  final _deviceInfoController = StreamController<Map<String, dynamic>>.broadcast();
  final _valveDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<bool> get connectionStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get deviceInfoStream => _deviceInfoController.stream;
  Stream<Map<String, dynamic>> get valveDataStream => _valveDataController.stream;
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  String? get connectedDeviceIp => _connectedDeviceIp;
  String? get connectedDeviceId => _connectedDeviceId;

  // Default ESP32 AP mode settings
  // ESP32 httpd server runs on port 80, WebSocket URI is /ws
  static const String defaultApIp = '192.168.4.1';
  static const int defaultPort = 80;
  static const String wsPath = '/ws';

  // ============================================================
  // CONNECTION MANAGEMENT
  // ============================================================

  /// Connect to ESP32 WebSocket server
  /// 
  /// ESP32 registers WebSocket handler at URI: /ws
  /// Server runs on default HTTP port 80
  /// See: websocket_server_fn.c → start_webserver()
  Future<bool> connect({
    String ip = defaultApIp,
    int port = defaultPort,
  }) async {
    try {
      print('🔄 ESP32: Connecting to ws://$ip:$port$wsPath');
      
      await disconnect();
      
      final wsUri = Uri(
        scheme: 'ws',
        host: ip,
        port: port,
        path: wsPath,
      );
      
      _channel = WebSocketChannel.connect(wsUri);
      
      await _channel!.ready;
      
      _isConnected = true;
      _isAuthenticated = false; // Must authenticate after connect
      _connectedDeviceIp = ip;
      _connectionStateController.add(true);
      
      print('✅ ESP32: WebSocket connected!');
      
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('❌ ESP32: WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('🔌 ESP32: WebSocket closed');
          _handleDisconnect();
        },
      );
      
      return true;
    } catch (e) {
      print('❌ ESP32: Connection failed: $e');
      _handleDisconnect();
      return false;
    }
  }

  /// Disconnect from ESP32
  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close(status.goingAway);
      _channel = null;
    }
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _isConnected = false;
    _isAuthenticated = false;
    _connectedDeviceIp = null;
    _connectedDeviceId = null;
    _connectionStateController.add(false);
  }

  // ============================================================
  // INCOMING MESSAGE HANDLER
  // ============================================================

  /// Handle incoming WebSocket messages from ESP32
  /// 
  /// ESP32 sends these event types:
  ///   - device_info: After successful authentication
  ///   - valve_data: Full valve state (controller, position, limits, error)
  ///   - valve_error: Error notification broadcast
  /// 
  /// See: websocket_state_fn.c → send_device_info(), send_device_data()
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      final event = data['event'] as String?;
      
      print('📨 ESP32 Event: $event');
      print('📨 Full message: $message');
      
      switch (event) {
        // ── Authentication response ──
        // ESP32 sends this after valid passkey
        // Format: {"event":"device_info","timestamp":"...","device_id":"DEVICE_ID"}
        // See: websocket_state_fn.c → send_device_info()
        case 'device_info':
          _isAuthenticated = true;
          _connectedDeviceId = data['device_id'];
          _deviceInfoController.add(Map<String, dynamic>.from(data));
          print('✅ ESP32: Authenticated! Device ID: $_connectedDeviceId');
          break;
        
        // ── Full valve state data ──
        // ESP32 sends this in response to device_basic_info request
        // Format: {"event":"valve_data","timestamp":"...","device_id":"...",
        //          "get_controller":{...},"get_valvedata":{...},
        //          "get_limitdata":{...},"Error":"..."}
        // See: websocket_state_fn.c → send_device_data()
        case 'valve_data':
          _valveDataController.add(Map<String, dynamic>.from(data));
          break;
        
        // ── Error broadcast ──
        // ESP32 can broadcast errors to all connected clients
        // Format: {"event":"valve_error","timestamp":"...","device_id":"...","error":"..."}
        case 'valve_error':
          _errorController.add(Map<String, dynamic>.from(data));
          break;
        
        default:
          print('⚠️ ESP32: Unknown event type: $event');
      }
    } catch (e) {
      print('❌ ESP32: Parse error: $e');
    }
  }

  /// Send JSON message to ESP32
  void _send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      print('⚠️ ESP32: Not connected');
      return;
    }
    final message = jsonEncode(data);
    print('📤 ESP32 Sending: $message');
    _channel!.sink.add(message);
  }

  // ============================================================
  // AUTHENTICATION
  // ============================================================

  /// Authenticate with ESP32 using passkey
  /// 
  /// This MUST be called first after connecting.
  /// ESP32 will not process any other events until authenticated.
  /// 
  /// ESP32 C code (websocket_state_fn.c → process_message):
  ///   - Checks event == "request_device_info"
  ///   - Validates passkey against CONFIG_WS_PASSKEY_VALUE
  ///   - If valid: sets connection_authorized = true, sends device_info
  ///   - If invalid: connection remains unauthorized
  /// 
  /// Sends:
  /// ```json
  /// {
  ///   "event": "request_device_info",
  ///   "passkey": "YOUR_PASSKEY"
  /// }
  /// ```
  /// 
  /// ESP32 responds with:
  /// ```json
  /// {
  ///   "event": "device_info",
  ///   "timestamp": "YYYY-MM-DD HH:MM:SS",
  ///   "device_id": "DEVICE_ID"
  /// }
  /// ```
  void authenticate({required String passkey}) {
    _send({
      'event': 'request_device_info',
      'passkey': passkey,
    });
  }

  // ============================================================
  // REQUEST VALVE DATA
  // ============================================================

  /// Request full valve state from ESP32
  /// 
  /// ESP32 C code (websocket_state_fn.c → offline_data):
  ///   - Checks event == "device_basic_info"
  ///   - Reads data.device_id and compares with DEVICE_ID
  ///   - If match: calls send_device_data() → sends valve_data event
  /// 
  /// Sends:
  /// ```json
  /// {
  ///   "event": "device_basic_info",
  ///   "data": {
  ///     "user_id": "user001",
  ///     "device_id": "dev0016"
  ///   }
  /// }
  /// ```
  void requestValveData({
    required String userId,
    required String deviceId,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'device_basic_info',
      'data': {
        'user_id': userId,
        'device_id': deviceId,
      },
    });
  }

  // ============================================================
  // VALVE CONTROL
  // ============================================================

  /// Set valve angle (manual control)
  /// 
  /// ESP32 C code (websocket_state_fn.c → offline_data):
  ///   - Checks event == "set_valve_basic"
  ///   - Reads valve_data.set_angle (bool) and valve_data.angle (number)
  ///   - Sets schedule_control = false, sensor_control = false
  ///   - Updates serverData via serverMutex
  /// 
  /// Note: ESP32 only reads the "valve_data" object.
  ///       It does NOT read device_id, set_controller, timestamp, or ota_update.
  /// 
  /// Sends:
  /// ```json
  /// {
  ///   "event": "set_valve_basic",
  ///   "valve_data": {
  ///     "set_angle": true,
  ///     "angle": 45
  ///   }
  /// }
  /// ```
  void setValveAngle({required int angle}) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_valve_basic',
      'valve_data': {
        'set_angle': true,
        'angle': angle.clamp(0, 90),
      },
    });
  }

  /// Open valve fully (angle = 90)
  void openValve() {
    setValveAngle(angle: 90);
  }

  /// Close valve fully (angle = 0)
  void closeValve() {
    setValveAngle(angle: 0);
  }

  // ============================================================
  // WIFI CONFIGURATION
  // ============================================================

  /// Set WiFi credentials for ESP32 STA mode
  /// 
  /// ESP32 C code (websocket_state_fn.c → offline_data):
  ///   - Checks event == "set_valve_wifi"
  ///   - Reads wifi_data.ssid and wifi_data.password
  ///   - Compares with current credentials
  ///   - If changed: saves to NVS via wifi_storage_save() and calls esp_restart()
  ///   - If unchanged: no action
  /// 
  /// WARNING: ESP32 will restart after saving new credentials!
  ///          The WebSocket connection will be lost.
  /// 
  /// Sends:
  /// ```json
  /// {
  ///   "event": "set_valve_wifi",
  ///   "wifi_data": {
  ///     "ssid": "YourSSID",
  ///     "password": "YourPassword"
  ///   }
  /// }
  /// ```
  void setWifiCredentials({
    required String ssid,
    required String password,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_valve_wifi',
      'wifi_data': {
        'ssid': ssid,
        'password': password,
      },
    });
  }

  // ============================================================
  // CONVENIENCE METHODS
  // ============================================================

  /// Connect and authenticate in one step
  /// Returns true if both connection and authentication message were sent
  /// Listen to deviceInfoStream to confirm authentication success
  Future<bool> connectAndAuthenticate({
    String ip = defaultApIp,
    int port = defaultPort,
    required String passkey,
  }) async {
    final connected = await connect(ip: ip, port: port);
    if (connected) {
      authenticate(passkey: passkey);
      return true;
    }
    return false;
  }

  /// Request valve data using the connected device ID
  /// Call this after authentication (when connectedDeviceId is available)
  void requestCurrentValveData({required String userId}) {
    if (_connectedDeviceId != null) {
      requestValveData(
        userId: userId,
        deviceId: _connectedDeviceId!,
      );
    } else {
      print('⚠️ ESP32: No device ID available. Authenticate first.');
    }
  }

  // ============================================================
  // CLEANUP
  // ============================================================

  /// Dispose all resources
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _deviceInfoController.close();
    _valveDataController.close();
    _errorController.close();
  }
}