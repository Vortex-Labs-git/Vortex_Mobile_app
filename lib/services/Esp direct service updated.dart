import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// ESP32 Direct Communication Service
/// Message structure follows Vortex_WiFi_Valve_Software_Architecture.pdf
/// Section: Mobile App And ESP32 Communication (WebSocket)
class EspDirectService {
  static EspDirectService? _instance;
  static EspDirectService get instance => _instance ??= EspDirectService._();
  
  EspDirectService._();

  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _connectedDeviceIp;
  String? _connectedDeviceId;
  
  // Stream controllers for different event types
  final _connectionStateController = StreamController<bool>.broadcast();
  final _deviceInfoController = StreamController<Map<String, dynamic>>.broadcast();
  final _valveDataController = StreamController<Map<String, dynamic>>.broadcast();
  final _wifiScanController = StreamController<List<Map<String, dynamic>>>.broadcast();
  final _wifiSavedController = StreamController<Map<String, dynamic>>.broadcast();
  final _errorController = StreamController<Map<String, dynamic>>.broadcast();
  
  // Public streams
  Stream<bool> get connectionStream => _connectionStateController.stream;
  Stream<Map<String, dynamic>> get deviceInfoStream => _deviceInfoController.stream;
  Stream<Map<String, dynamic>> get valveDataStream => _valveDataController.stream;
  Stream<List<Map<String, dynamic>>> get wifiScanStream => _wifiScanController.stream;
  Stream<Map<String, dynamic>> get wifiSavedStream => _wifiSavedController.stream;
  Stream<Map<String, dynamic>> get errorStream => _errorController.stream;
  
  // Getters
  bool get isConnected => _isConnected;
  String? get connectedDeviceIp => _connectedDeviceIp;
  String? get connectedDeviceId => _connectedDeviceId;

  // Default ESP32 AP mode settings
  static const String defaultApIp = '192.168.4.1';
  static const int defaultPort = 81;

  /// Generate ISO 8601 timestamp
  String _getTimestamp() => DateTime.now().toUtc().toIso8601String();

  /// Connect to ESP32 WebSocket
  Future<bool> connect({
    String ip = defaultApIp,
    int port = defaultPort,
  }) async {
    try {
      print('🔄 Connecting to ESP32 at ws://$ip:$port');
      
      await disconnect();
      
      // TEMPORARY: Point to Mock Python Script for testing
      // TODO: Switch back to real ESP32 IP when hardware is ready
      final wsUri = Uri.parse('ws://192.168.137.1:9090');
      
      // ORIGINAL (Keep this for later):
      // final wsUri = Uri(scheme: 'ws', host: ip, port: port);
      
      _channel = WebSocketChannel.connect(wsUri);
      
      await _channel!.ready;
      
      _isConnected = true;
      _connectedDeviceIp = ip;
      _connectionStateController.add(true);
      
      print('✅ Connected to ESP32!');
      
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          print('❌ WebSocket Error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('🔌 WebSocket Closed');
          _handleDisconnect();
        },
      );
      
      return true;
    } catch (e) {
      print('❌ Connection Error: $e');
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
    _connectedDeviceIp = null;
    _connectedDeviceId = null;
    _connectionStateController.add(false);
  }

  /// Handle incoming WebSocket messages from ESP32
  /// Message format follows architecture document specification
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message.toString());
      final event = data['event'] as String?;
      
      print('📨 ESP32 Event: $event');
      print('📨 Full message: $message');
      
      switch (event) {
        // Response to request_device_info
        // Doc: {"event": "device_info", "timestamp": "...", "device_id": "dev0016"}
        case 'device_info':
          _connectedDeviceId = data['device_id'];
          _deviceInfoController.add(Map<String, dynamic>.from(data));
          break;
        
        // Response to device_basic_info request
        // Doc: {"event": "valve_data", "device_id": "...", "get_controller": {...}, ...}
        case 'valve_data':
          _valveDataController.add(Map<String, dynamic>.from(data));
          break;
        
        // WiFi scan results
        case 'wifi_scan_result':
          final networks = (data['networks'] as List)
              .map((n) => Map<String, dynamic>.from(n))
              .toList();
          _wifiScanController.add(networks);
          break;
        
        // WiFi credentials saved confirmation
        case 'wifi_saved':
          _wifiSavedController.add(Map<String, dynamic>.from(data));
          break;
        
        // State update (real-time valve state changes)
        case 'state_update':
          _valveDataController.add(Map<String, dynamic>.from(data));
          break;
        
        // Error messages from ESP32
        case 'valve_error':
        case 'error':
          _errorController.add(Map<String, dynamic>.from(data));
          break;
        
        default:
          print('⚠️ Unknown event type: $event');
      }
    } catch (e) {
      print('❌ Parse Error: $e');
    }
  }

  /// Send message to ESP32
  void _send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      print('⚠️ Not connected to ESP32');
      return;
    }
    final message = jsonEncode(data);
    print('📤 Sending: $message');
    _channel!.sink.add(message);
  }

  // ============================================================
  // API Methods - Following Architecture Document Specification
  // ============================================================

  /// Request device info from ESP32
  /// Doc Page 10: Connection Establishment - Identify the Device
  /// 
  /// Sends:
  /// ```json
  /// {
  ///   "event": "request_device_info",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "user_id": "user_id",
  ///   "passkey": "key"
  /// }
  /// ```
  void requestDeviceInfo({required String userId, String passkey = ''}) {
    _send({
      'event': 'request_device_info',
      'timestamp': _getTimestamp(),
      'user_id': userId,
      'passkey': passkey,
    });
  }

  /// Request valve basic data
  /// Doc Page 11: WiFi Valve Details Screen - Data visualizing
  /// 
  /// Sends:
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
    required String deviceName,
  }) {
    _send({
      'event': 'device_basic_info',
      'timestamp': _getTimestamp(),
      'data': {
        'user_id': userId,
        'device_id': deviceId,
        'device_name': deviceName,
      },
    });
  }

  /// Set valve basic data (control valve)
  /// Doc Page 12: WiFi Valve Details Screen - Data editing
  /// 
  /// Sends:
  /// ```json
  /// {
  ///   "event": "set_valve_basic",
  ///   "timestamp": "2025-01-15T10:30:00Z",
  ///   "device_id": "dev0016",
  ///   "set_controller": {
  ///     "schedule": false,
  ///     "sensor": false
  ///   },
  ///   "valve_data": {
  ///     "name": "MainValve01",
  ///     "set_angle": true,
  ///     "angle": 45
  ///   },
  ///   "ota_update": false
  /// }
  /// ```
  void setValveBasic({
    required String deviceId,
    String? name,
    bool? setAngle,
    int? angle,
    bool scheduleEnabled = false,
    bool sensorEnabled = false,
    bool otaUpdate = false,
  }) {
    final valveData = <String, dynamic>{};
    if (name != null) valveData['name'] = name;
    if (setAngle != null) valveData['set_angle'] = setAngle;
    if (angle != null) valveData['angle'] = angle;
    
    _send({
      'event': 'set_valve_basic',
      'timestamp': _getTimestamp(),
      'device_id': deviceId,
      'set_controller': {
        'schedule': scheduleEnabled,
        'sensor': sensorEnabled,
      },
      'valve_data': valveData,
      'ota_update': otaUpdate,
    });
  }

  /// Open valve fully (angle = 90 or fully open)
  void openValve({required String deviceId}) {
    setValveBasic(
      deviceId: deviceId,
      setAngle: true,
      angle: 90, // Fully open
    );
  }

  /// Close valve fully (angle = 0 or fully closed)
  void closeValve({required String deviceId}) {
    setValveBasic(
      deviceId: deviceId,
      setAngle: true,
      angle: 0, // Fully closed
    );
  }

  /// Set valve to specific angle
  void setValveAngle({required String deviceId, required int angle}) {
    setValveBasic(
      deviceId: deviceId,
      setAngle: true,
      angle: angle.clamp(0, 90),
    );
  }

  /// Set WiFi credentials for STA mode
  /// Doc Page 13: Configure the Valve STA mode wifi credentials
  /// 
  /// Sends:
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
  void setWifiCredentials({
    required String deviceId,
    required String ssid,
    required String password,
  }) {
    _send({
      'event': 'set_valve_wifi',
      'timestamp': _getTimestamp(),
      'device_id': deviceId,
      'wifi_data': {
        'ssid': ssid,
        'password': password,
      },
    });
  }

  /// Scan for available WiFi networks
  /// (This is a convenience method, not explicitly in the doc)
  void scanWifiNetworks() {
    _send({
      'event': 'scan_wifi',
      'timestamp': _getTimestamp(),
    });
  }

  /// Restart the ESP32 device
  /// (This is a convenience method, not explicitly in the doc)
  void restartDevice({required String deviceId}) {
    _send({
      'event': 'restart_device',
      'timestamp': _getTimestamp(),
      'device_id': deviceId,
    });
  }

  // ============================================================
  // Legacy API Methods (for backward compatibility)
  // These wrap the new methods with simpler signatures
  // ============================================================

  /// Legacy: Get device info (uses default/empty user info)
  void getDeviceInfo() {
    requestDeviceInfo(userId: 'app_user');
  }

  /// Legacy: Simple open valve (requires connected device)
  void openValveSimple() {
    if (_connectedDeviceId != null) {
      openValve(deviceId: _connectedDeviceId!);
    } else {
      print('⚠️ No device connected, cannot open valve');
    }
  }

  /// Legacy: Simple close valve (requires connected device)
  void closeValveSimple() {
    if (_connectedDeviceId != null) {
      closeValve(deviceId: _connectedDeviceId!);
    } else {
      print('⚠️ No device connected, cannot close valve');
    }
  }

  /// Legacy: Set WiFi (requires connected device)
  void setWifiSimple(String ssid, String password) {
    if (_connectedDeviceId != null) {
      setWifiCredentials(
        deviceId: _connectedDeviceId!,
        ssid: ssid,
        password: password,
      );
    } else {
      print('⚠️ No device connected, cannot set WiFi');
    }
  }

  /// Dispose resources
  void dispose() {
    disconnect();
    _connectionStateController.close();
    _deviceInfoController.close();
    _valveDataController.close();
    _wifiScanController.close();
    _wifiSavedController.close();
    _errorController.close();
  }
}