import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import '../config/env.dart';

/// ESP32 Direct Communication Service
/// 
/// Aligned with actual ESP32 firmware implementation:
///   - websocket_server_fn.c: Server lifecycle, async broadcast, URI /ws
///   - websocket_state_fn.c: Event processing, authentication, state updates
///   - WEBSOCKET_MSG_FLOW.md: Message formats and flow
///
/// Connection Flow (Valve  — VA-):
///   1. Connect to ws://<ip>:<port>/ws
///   2. Authenticate with request_device_info + passkey
///   3. ESP32 responds with device_info (device_id)
///   4. Request valve data with device_basic_info
///   5. Control valve with set_valve_basic
///   6. Configure WiFi with set_valve_wifi
///
/// Connection Flow (Sensor Unit — SU-):
///   1-3. Same as valve (connect + request_device_info + device_info)
///   4. Request unit data with device_basic_info (same request event)
///   5. Device responds with sensor_unit_info (instead of valve_data)
///   6. Configure WiFi with set_device_wifi (NOT set_valve_wifi)
///   7. Read/write sensor config with get_sensor_config / set_sensor_config
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
  final _sensorUnitInfoController = StreamController<Map<String, dynamic>>.broadcast();
  final _sensorConfigController = StreamController<Map<String, dynamic>>.broadcast();
  final _motorCalibrationController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<bool> get connectionStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get deviceInfoStream => _deviceInfoController.stream;
  Stream<Map<String, dynamic>> get valveDataStream => _valveDataController.stream;
  Stream<Map<String, dynamic>> get sensorUnitInfoStream => _sensorUnitInfoController.stream;
  Stream<Map<String, dynamic>> get sensorConfigStream => _sensorConfigController.stream;
  Stream<Map<String, dynamic>> get motorCalibrationStream => _motorCalibrationController.stream;
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isAuthenticated => _isAuthenticated;
  String? get connectedDeviceIp => _connectedDeviceIp;
  String? get connectedDeviceId => _connectedDeviceId;

  // Default ESP32 AP mode settings
  // ESP32 httpd server runs on port 80, WebSocket URI is /ws
  static const String defaultApIp = Env.espIp;
  static const int defaultPort = Env.espPort;
  static const String wsPath = Env.espPath;

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
      
      // Capture THIS channel so the callbacks below can tell whether they
      // belong to the current connection. During a forced reconnect the
      // OLD socket's onDone/onError can fire AFTER the new one is already
      // up — without this guard that stale event would wrongly tear down
      // the fresh connection (_handleDisconnect on a live link).
      final channel = _channel!;
      channel.stream.listen(
        _handleMessage,
        onError: (error) {
          print('❌ ESP32: WebSocket error: $error');
          if (_channel == channel) _handleDisconnect();
        },
        onDone: () {
          print('🔌 ESP32: WebSocket closed');
          if (_channel == channel) _handleDisconnect();
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
  ///   - sensor_unit_info: Sensor unit data (unit name, sensor readings)
  ///   - get_sensor_config: Sensor configuration (types + tag names, no values)
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
        
        // ── Sensor unit data ──
        // Sensor Unit (SU-) sends this in response to device_basic_info
        // request (the same request event the valve uses).
        // Architecture Doc v3 - Sensor Unit / Details Screen - Data visualizing:
        // Format: {"event":"sensor_unit_info","device_id":"SU202601003",
        //          "device_name":"garden 1","timestamp":"...",
        //          "no_sensors":"3","data":"[{...},{...}]"}
        // NOTE: keys differ from the cloud device_basic_detail payload —
        //       device_id/device_name/data here vs id/unit_name/sensor_data
        //       on the cloud path. `data` is an ESCAPED JSON STRING, same as
        //       the cloud sensor_data field. No version / last_seen fields.
        case 'sensor_unit_info':
          _sensorUnitInfoController.add(Map<String, dynamic>.from(data));
          break;
        
        // ── Sensor configuration data ──
        // Sensor Unit sends this in response to a get_sensor_config request.
        // Architecture Doc v3 - Sensor Configuration Process:
        // Format: {"event":"get_sensor_config","timestamp":"...",
        //          "device_id":"SU202505001","no_sensors":"3",
        //          "sensor_data":"[{sensor_id,sensor_type,sensor_name},...]"}
        // NOTE: sensor_data is an ESCAPED JSON STRING and — unlike
        //       sensor_unit_info — carries NO sensor_value fields.
        //       First 2 entries (S00/S01) are in-build sensors: the config
        //       screen must render them read-only.
        case 'get_sensor_config':
          _sensorConfigController.add(Map<String, dynamic>.from(data));
          break;
        
        // ── Motor calibration data ──
        // ESP32 sends this in response to:
        //   - get_motor_calibration request (initial load)
        //   - set_motor_rotation clockwise/anticlockwise (real-time encoder updates)
        // Format: {"event":"get_motor_calibration","timestamp":"...","device_id":"...",
        //          "encoder_data":{"value":2500,"Close_limit":2000,"Open_limit":3500}}
        // The app screen decides whether to use Close_limit/Open_limit (only on first reply)
        // or just the real-time `value` (on subsequent replies).
        case 'get_motor_calibration':
          _motorCalibrationController.add(Map<String, dynamic>.from(data));
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
  /// Real ESP32 expects (confirmed via Postman):
  /// ```json
  /// {
  ///   "event": "request_device_info",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "user_id": "user_id",
  ///   "passkey": "12345"
  /// }
  /// ```
  /// 
  /// ESP32 responds with:
  /// ```json
  /// {
  ///   "event": "device_info",
  ///   "timestamp": "1970-01-01T00:13:09",
  ///   "device_id": "VA202601001"
  /// }
  /// ```
  void authenticate({required String passkey, String? userId}) {
    _send({
      'event': 'request_device_info',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'user_id': userId ?? 'app_user',
      'passkey': passkey,
    });
  }

  // ============================================================
  // REQUEST DEVICE DATA (valve + sensor unit)
  // ============================================================

  /// Request full valve state from ESP32
  /// 
  /// Architecture Doc Page 11:
  /// ```json
  /// {
  ///   "event": "device_basic_info",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "data": {
  ///     "user_id": "user001",
  ///     "device_id": "dev0016",
  ///     "device_name": "home valve"
  ///   }
  /// }
  /// ```
  void requestValveData({
    required String userId,
    required String deviceId,
    String? deviceName,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'device_basic_info',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName ?? 'Valve',
      },
    });
  }

  /// Request sensor unit data from ESP32
  /// 
  /// Same `device_basic_info` request event as the valve — the DEVICE
  /// decides the response type. A Sensor Unit (SU-) replies with a
  /// `sensor_unit_info` event; listen on sensorUnitInfoStream.
  /// 
  /// Architecture Doc v3 - Sensor Unit / Details Screen:
  /// ```json
  /// {
  ///   "event": "device_basic_info",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "data": {
  ///     "user_id": "uid001",
  ///     "device_id": "SU202505001",
  ///     "device_name": "garden 1"
  ///   }
  /// }
  /// ```
  void requestSensorUnitData({
    required String userId,
    required String deviceId,
    String? deviceName,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'device_basic_info',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'data': {
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName ?? 'Sensor Unit',
      },
    });
  }

  // ============================================================
  // VALVE CONTROL
  // ============================================================

  /// Set valve angle (manual control)
  /// 
  /// Architecture Doc Page 12 - exact format ESP32 expects:
  /// ```json
  /// {
  ///   "event": "set_valve_basic",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "dev0016",
  ///   "set_controller": { "schedule": false, "sensor": false },
  ///   "valve_data": { "name": "MainValve01", "set_angle": true, "angle": 45 },
  ///   "ota_update": false
  /// }
  /// ```
  void setValveAngle({required int angle, String? deviceName}) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_valve_basic',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'set_controller': {
        'schedule': false,
        'sensor': false,
      },
      'valve_data': {
        'name': deviceName ?? 'Valve',
        'set_angle': true,
        'angle': angle.clamp(0, 90),
      },
      'ota_update': false,
    });
  }

  /// Open valve fully (angle = 90)
  void openValve({String? deviceName}) {
    setValveAngle(angle: 90, deviceName: deviceName);
  }

  /// Close valve fully (angle = 0)
  void closeValve({String? deviceName}) {
    setValveAngle(angle: 0, deviceName: deviceName);
  }

  // ============================================================
  // MOTOR CALIBRATION
  // ============================================================

  /// Request motor calibration data from ESP32 (initial load)
  /// 
  /// Called once when MotorCalibrationScreen opens.
  /// ESP32 responds with `get_motor_calibration` event containing
  /// encoder_data { value, Close_limit, Open_limit }.
  /// 
  /// edit.pdf - Motor Calibration process:
  /// ```json
  /// {
  ///   "event": "get_motor_calibration",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "VA202604001"
  /// }
  /// ```
  void requestMotorCalibration() {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'get_motor_calibration',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
    });
  }

  /// Turn motor clockwise or anti-clockwise (called per-tap)
  /// 
  /// User taps "Turn motor Clockwise" or "Turn motor Anticlockwise"
  /// continuously. Each tap sends one rotation command. ESP32 replies
  /// with a `get_motor_calibration` message containing the updated
  /// real-time encoder value.
  /// 
  /// edit.pdf - Motor Calibration process:
  /// ```json
  /// {
  ///   "event": "set_motor_rotation",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "VA202604001",
  ///   "set_motor": {
  ///     "turn_clkwise": true,
  ///     "Turn_anticlkwise": false
  ///   }
  /// }
  /// ```
  void setMotorRotation({required bool clockwise}) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_motor_rotation',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'set_motor': {
        'turn_clkwise': clockwise,
        'Turn_anticlkwise': !clockwise,
      },
    });
  }

  /// Save calibration limits to ESP32
  /// 
  /// Called when user taps "save" on MotorCalibrationScreen, after
  /// they have set close value / open value. Sends only the limits
  /// (no `value` field — that's sensor data, not user-set).
  /// 
  /// edit.pdf - Motor Calibration process:
  /// ```json
  /// {
  ///   "event": "set_motor_calibration",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "VA202604001",
  ///   "encoder_data": {
  ///     "Close_limit": 2000,
  ///     "Open_limit": 3500
  ///   }
  /// }
  /// ```
  void setMotorCalibration({
    required int closeLimit,
    required int openLimit,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_motor_calibration',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'encoder_data': {
        'Close_limit': closeLimit,
        'Open_limit': openLimit,
      },
    });
  }

  // ============================================================
  // WIFI CONFIGURATION
  // ============================================================

  /// Set WiFi credentials for ESP32 STA mode
  /// 
  /// Architecture Doc Page 13:
  /// ```json
  /// {
  ///   "event": "set_valve_wifi",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "dev0016",
  ///   "wifi_data": {
  ///     "ssid": "myNetWork",
  ///     "password": "1234"
  ///   }
  /// }
  /// ```
  /// 
  /// NOTE: This is the VALVE event name. The Sensor Unit uses
  ///       `set_device_wifi` — see setSensorUnitWifi() below.
  /// 
  /// WARNING: ESP32 will restart after saving new credentials!
  ///          The WebSocket connection will be lost.
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
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'wifi_data': {
        'ssid': ssid,
        'password': password,
      },
    });
  }

  /// Set WiFi credentials for a SENSOR UNIT's STA mode
  /// 
  /// Same payload shape as the valve, but the Sensor Unit firmware
  /// listens for `set_device_wifi` instead of `set_valve_wifi`.
  /// 
  /// Architecture Doc v3 - Sensor Unit / Details Screen - Data editing:
  /// ```json
  /// {
  ///   "event": "set_device_wifi",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "SU202505001",
  ///   "wifi_data": {
  ///     "ssid": "myNetWork",
  ///     "password": "1234"
  ///   }
  /// }
  /// ```
  /// 
  /// WARNING: ESP32 will restart after saving new credentials!
  ///          The WebSocket connection will be lost.
  void setSensorUnitWifi({
    required String ssid,
    required String password,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_device_wifi',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'wifi_data': {
        'ssid': ssid,
        'password': password,
      },
    });
  }

  // ============================================================
  // SENSOR CONFIGURATION (Sensor Unit only)
  // ============================================================

  /// Request sensor configuration from the Sensor Unit (initial load)
  /// 
  /// Called once when the Sensor Configuration screen opens. The unit
  /// replies with a `get_sensor_config` event (listen on
  /// sensorConfigStream) containing sensor_id / sensor_type /
  /// sensor_name per sensor — no values.
  /// 
  /// Architecture Doc v3 - Sensor Configuration Process:
  /// ```json
  /// {
  ///   "event": "get_sensor_config",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "SU202505001"
  /// }
  /// ```
  void requestSensorConfig() {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'get_sensor_config',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
    });
  }

  /// Save sensor configuration to the Sensor Unit
  /// 
  /// Called when the user taps Save on the Sensor Configuration screen.
  /// `sensors` is the FULL list (including the read-only in-build S00/S01
  /// entries, unchanged), each map holding sensor_id / sensor_type /
  /// sensor_name. Encoded to a JSON STRING to match the wire format —
  /// same escaped-string convention the unit uses when sending.
  /// 
  /// Architecture Doc v3 - Sensor Configuration Process:
  /// ```json
  /// {
  ///   "event": "set_sensor_config",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "SU202505001",
  ///   "no_sensors": "3",
  ///   "sensor_data": "[{\"sensor_id\":\"S00\",...},...]"
  /// }
  /// ```
  void setSensorConfig({
    required List<Map<String, dynamic>> sensors,
  }) {
    if (!_isAuthenticated) {
      print('⚠️ ESP32: Not authenticated. Call authenticate() first.');
      return;
    }
    _send({
      'event': 'set_sensor_config',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'device_id': _connectedDeviceId ?? '',
      'no_sensors': sensors.length.toString(), // spec sends this as a String
      'sensor_data': sensors,// escaped JSON string on the wire
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
    _sensorUnitInfoController.close();
    _sensorConfigController.close();
    _motorCalibrationController.close();
    _errorController.close();
  }
}