import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'dart:async';
import '../../services/websocket_service.dart';
import '../../services/esp_direct_service.dart';
import '../../models/sensor_unit.dart';
import '../../theme/glass_theme.dart';
import '../../widgets/glass/glass.dart';
import '../sensor_config_screen.dart';

// =============================================================================
// SENSOR DETAIL SCREEN
// =============================================================================
// Screen for one WiFi sensor unit (device id starts with "SU"). Two modes,
// mirroring DeviceDetailScreen:
//
//   - Server mode (isDirectMode = false): WebSocket through the cloud.
//     Subscribes to 'device_detail'; parses each device_basic_detail push
//     into a SensorUnit via SensorUnit.fromJson (keys: id / unit_name /
//     unit_version / unit_last_seen / no_sensors / sensor_data).
//
//   - Direct mode (isDirectMode = true): Talks straight to the ESP32 over
//     its AP via EspDirectService. Sends device_basic_info (initial +
//     2-second poll, same cadence as the valve screen); listens on
//     sensorUnitInfoStream for the sensor_unit_info reply and parses it via
//     SensorUnit.fromDirectJson (keys: device_id / device_name / no_sensors
//     / data). No lastSeen in this payload, so online status is simply the
//     ESP32 connection state.
//
// Preview mode (previewMode = true): used ONLY by the @Preview builders at
// the bottom of this file for the VS Code Flutter Widget Preview panel.
// Skips ALL networking (no WebSocketService, no EspDirectService, no poll
// timer) and seeds _unit directly from deviceData so the GUI renders with
// dummy data. Defaults to false — production behavior is unchanged.
//
// On dispose, server mode resubscribes to 'device_list' so the home list
// resumes; direct mode must NOT touch the cloud WebSocket. Bottom buttons
// ("Change WiFi connection" → set_device_wifi popup; "Sensor configuration"
// → SensorConfigScreen) render in DIRECT MODE ONLY — both are AP-mode
// operations, so server (online) mode shows no bottom buttons at all.
// Unit name Edit remains a stub until the sensor edit REST is defined.
// Sensor tag names are read-only.
// =============================================================================

class SensorDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData; // from the home list: id, name, ...
  final bool isDirectMode;
  final bool previewMode; // widget-preview only — bypasses all networking

  const SensorDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
    this.previewMode = false,
  });

  @override
  State<SensorDetailScreen> createState() => _SensorDetailScreenState();
}

class _SensorDetailScreenState extends State<SensorDetailScreen> {
  late final String _deviceId; // id we subscribe with / filter pushes against
  SensorUnit? _unit;           // latest push; null until the first one arrives
  bool _wsConnected = false;   // cloud WS (server mode) or ESP32 WS (direct)

  // -- Stream subscriptions (server mode) --
  StreamSubscription? _detailSub;
  StreamSubscription? _connectionSub;

  // -- Stream subscriptions (direct mode) --
  StreamSubscription? _espUnitInfoSub;
  StreamSubscription? _espConnectionSub;
  Timer? _espPollTimer;

  // -- Shortcuts --
  bool get _isDirectMode => widget.isDirectMode;
  bool get _isPreviewMode => widget.previewMode;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.deviceData['id']?.toString() ?? '';

    // Preview mode: no WebSocket, no ESP32, no polling. Seed the unit
    // straight from deviceData (cloud-style keys) so the UI renders.
    if (_isPreviewMode) {
      _unit = SensorUnit.fromJson(widget.deviceData);
      _wsConnected = true; // green connection icon in the app bar
      return;
    }

    // _unit starts null in BOTH modes, so no stale cloud state can leak into
    // direct mode — the first sensor_unit_info reply is the source of truth.
    if (_isDirectMode) {
      _setupEspDirect();
    } else {
      _setupWebSocket();
    }
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _connectionSub?.cancel();
    _espUnitInfoSub?.cancel();
    _espConnectionSub?.cancel();
    _espPollTimer?.cancel();
    // Preview mode never subscribed, so it must not touch the singleton here.
    if (!_isDirectMode && !_isPreviewMode) {
      WebSocketService.subscribeTo('device_list'); // resume home list updates
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // WebSocket setup (server mode)
  // ---------------------------------------------------------------------------
  void _setupWebSocket() {
    _wsConnected = WebSocketService.isConnected;

    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (!mounted) return;
      if (data['id']?.toString() != _deviceId) return; // only THIS unit
      setState(() => _unit = SensorUnit.fromJson(data));
    });

    WebSocketService.subscribeTo('device_detail', deviceId: _deviceId);
  }

  // ---------------------------------------------------------------------------
  // ESP32 direct setup (direct mode)
  // ---------------------------------------------------------------------------
  void _setupEspDirect() {
    final esp = EspDirectService.instance;
    _wsConnected = esp.isConnected;

    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _espUnitInfoSub = esp.sensorUnitInfoStream.listen((data) {
      if (!mounted) return;
      if (data['device_id']?.toString() != _deviceId) return; // only THIS unit
      setState(() => _unit = SensorUnit.fromDirectJson(data));
      print('📱 ESP32 Direct: sensor_unit_info, '
          '${data['no_sensors']} sensors');
    });

    // Initial request, then poll every 2 seconds (same cadence as the
    // valve screen — the ESP32 replies per-request, it doesn't push).
    _requestEspSensorData();
    _espPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && esp.isAuthenticated) {
        _requestEspSensorData();
      }
    });
  }

  void _requestEspSensorData() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) return;

    final userId = widget.deviceData['user_id']?.toString() ?? 'app_user';
    final deviceName =
        widget.deviceData['name']?.toString() ?? 'Sensor Unit';
    esp.requestSensorUnitData(
      userId: userId,
      deviceId: _deviceId,
      deviceName: deviceName,
    );
  }

  // Online if reported within 30s (server mode only). Direct mode has no
  // lastSeen field — being connected to the ESP32 IS the online signal.
  bool _isDeviceOnline(String? lastSeen) {
    if (_isDirectMode) return _wsConnected;
    if (lastSeen == null || lastSeen.isEmpty || lastSeen.toUpperCase() == 'NULL') {
      return false;
    }
    try {
      return DateTime.now().difference(DateTime.parse(lastSeen)).inSeconds <= 30;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final unit = _unit;

    return GlassScaffold(
      appBar: GlassAppBar(
        title: _isDirectMode ? 'Direct Control' : 'Vortex Labs',
        tint: _isDirectMode ? GlassTokens.success : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _wsConnected
                  ? (_isDirectMode ? Icons.settings_remote : Icons.wifi)
                  : Icons.wifi_off,
              color: _wsConnected ? GlassTokens.success : GlassTokens.danger,
            ),
          ),
        ],
      ),
      body: unit == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildUnitInfoCard(unit),
                  const SizedBox(height: 16),
                  ...unit.sensors.map(_buildSensorCard),
                  if (unit.sensors.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No sensors reported',
                            style: TextStyle(color: GlassTokens.textMuted)),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _buildBottomButtons(),
                ],
              ),
            ),
    );
  }

  // ----- Unit info: Product Type / Name (Edit) / Status / Active Sensors -----
  Widget _buildUnitInfoCard(SensorUnit unit) {
    final bool online = _isDeviceOnline(unit.lastSeen);
    final Color statusColor = online ? GlassTokens.success : GlassTokens.danger;
    final String displayName = unit.name.isNotEmpty
        ? unit.name
        : (widget.deviceData['name']?.toString() ?? 'Sensor Unit');

    return GlassCard(
      // Highlighted so the unit summary stands apart from the sensor cards:
      // indigo-tinted glass, where the per-sensor cards below are neutral.
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(16),
      tint: GlassTokens.primary,
      tintStrength: 0.22,
      child: Column(
        children: [
          _infoRow('Product Type', Text(
            unit.version.isNotEmpty ? unit.version : 'Sensor unit',
            style: const TextStyle(fontWeight: FontWeight.w500),
          )),
          const Divider(),
          _infoRow('Name', Row(children: [
            TextButton(
              onPressed: _onEditName,
              child: const Text('Edit', style: TextStyle(color: GlassTokens.primary)),
            ),
            Text(displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
          ])),
          const Divider(),
          _infoRow('Connection Status', Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              online
                  ? (_isDirectMode ? 'direct' : 'online')
                  : 'offline',
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w500),
            ),
          ])),
          const Divider(),
          _infoRow('Active Sensors', Text(
            '${unit.sensorCount}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          )),
        ],
      ),
    );
  }

  // ----- One sensor: Sensor Type(S01) / Tag name / Sensor value -----
  Widget _buildSensorCard(Sensor sensor) {
    return GlassCard(
      padding: EdgeInsets.zero,
      // Material Card used to supply this gap through its default margin.
      margin: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _infoRow('Sensor Type(${_displaySensorId(sensor)})', Text(
              sensor.type.isNotEmpty ? sensor.type : '—',
              style: const TextStyle(fontWeight: FontWeight.w500),
            )),
            const Divider(),
            _infoRow('Tag name', Text(
              sensor.name.isNotEmpty ? sensor.name : '—',
              style: const TextStyle(fontWeight: FontWeight.w500),
            )),
            const Divider(),
            _infoRow('Sensor value', Text(
              _formatSensorValue(sensor),
              style: const TextStyle(fontWeight: FontWeight.w600),
            )),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, Widget trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            )),
        trailing,
      ],
    );
  }

  // ----- Sensor id display formatting -----
  // Backend sensor ids are 0-based (S00..S07) but the GUI shows them
  // 1-based (S01..S08) — same convention as the config screen headers.
  // Handles both bare "S00" and prefixed "SU202601003_S00" formats;
  // anything unrecognized is shown as-is.
  String _displaySensorId(Sensor sensor) {
    final raw = sensor.id.trim();
    final tail =
        raw.contains('_') ? raw.substring(raw.lastIndexOf('_') + 1) : raw;
    final match = RegExp(r'^[Ss](\d+)$').firstMatch(tail);
    if (match == null) return raw;
    final n = int.parse(match.group(1)!) + 1;
    return 'S${n.toString().padLeft(2, '0')}';
  }

  // ----- Sensor value display formatting -----
  // Numeric readings are shown with exactly 2 decimal places ("24.5" →
  // "24.50", "61" → "61.00"). Non-numeric values pass through unchanged
  // (the format varies per sensor, so don't break anything exotic).
  // Unit suffix by sensor type: temperature → °C, humidity → %.
  String _formatSensorValue(Sensor sensor) {
    final raw = sensor.value.trim();
    if (raw.isEmpty) return '—';

    final parsed = double.tryParse(raw);
    final text = parsed != null ? parsed.toStringAsFixed(2) : raw;

    final type = sensor.type.toLowerCase();
    if (type.contains('temp')) return '$text °C';
    if (type.contains('humid')) return '$text %';
    return text;
  }

  // ----- Bottom buttons: direct mode ONLY. Both are AP-mode operations,
  //       so in server (online) mode neither button exists. -----
  Widget _buildBottomButtons() {
    if (!_isDirectMode) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _onChangeWifi,
            icon: const Icon(Icons.wifi),
            label: const Text('Change WiFi connection'),
            style: _buttonStyle(),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _onSensorConfig,
            icon: const Icon(Icons.tune),
            label: const Text('Sensor configuration'),
            style: _buttonStyle(),
          ),
        ),
      ],
    );
  }

  ButtonStyle _buttonStyle() => ElevatedButton.styleFrom(
        backgroundColor:
            _isDirectMode ? GlassTokens.success : GlassTokens.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );

  // ----- Action stubs — unit name editing needs the sensor edit REST
  //       endpoint (server side, not defined yet). Sensor tag names are
  //       read-only in this screen. -----
  void _onEditName() => _todo('Rename sensor unit');

  /// get/set_sensor_config are AP-mode operations. The button that reaches
  /// this only renders in direct mode, so no server-mode guard is needed.
  /// Preview mode never navigates — SensorConfigScreen would try to talk
  /// to EspDirectService.
  void _onSensorConfig() {
    if (_isPreviewMode) {
      _todo('Sensor configuration (preview)');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SensorConfigScreen(deviceData: widget.deviceData),
      ),
    );
  }

  void _todo(String label) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label — not wired up yet')),
    );
  }

  // -------------------------------------------------------------------------
  // WiFi Credentials Dialog (Direct mode)
  // -------------------------------------------------------------------------
  /// The button that reaches this only renders in direct mode, so no
  /// server-mode guard is needed. In preview + direct mode the dialog opens
  /// too (safe: the Save button checks isAuthenticated, which is false in
  /// preview, so nothing is ever sent).
  void _onChangeWifi() {
    _showWifiCredentialsDialog();
  }

  /// Shows a popup to enter home WiFi SSID and password, then sends
  /// set_device_wifi (sensor unit event — NOT the valve's set_valve_wifi)
  /// to the connected ESP32. Architecture Doc v3 - Sensor Unit /
  /// Details Screen - Data editing.
  void _showWifiCredentialsDialog() {
    final ssidController = TextEditingController();
    final passwordController = TextEditingController();
    bool obscurePassword = true;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.wifi, color: GlassTokens.primary),
              SizedBox(width: 10),
              Text('Set Home WiFi'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your home WiFi credentials. The sensor unit will restart and connect to this network.',
                style: TextStyle(fontSize: 13, color: GlassTokens.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ssidController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'WiFi Name (SSID)',
                  hintText: 'Enter your home WiFi name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.wifi),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'WiFi Password',
                  hintText: 'Enter WiFi password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () {
                      setDialogState(
                          () => obscurePassword = !obscurePassword);
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSending ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: isSending
                  ? null
                  : () {
                      final ssid = ssidController.text.trim();
                      final password = passwordController.text;

                      if (ssid.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter WiFi name'),
                          ),
                        );
                        return;
                      }

                      if (!EspDirectService.instance.isAuthenticated) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Not connected to sensor unit. Go back and reconnect.'),
                            backgroundColor: GlassTokens.danger,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      EspDirectService.instance.setSensorUnitWifi(
                        ssid: ssid,
                        password: password,
                      );

                      print("📤 ESP32: set_device_wifi ssid=$ssid");

                      // ESP32 will restart — connection will be lost
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'WiFi credentials sent! Sensor unit will restart and connect to your home WiFi.',
                              ),
                              backgroundColor: GlassTokens.success,
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
                      });
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(isSending ? 'Sending...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// WIDGET PREVIEWS (VS Code Flutter Widget Preview panel only)
// =============================================================================
// previewMode: true bypasses all networking and seeds the unit straight from
// deviceData. last_seen is set to "now" at build time so the status dot shows
// online/green — a hardcoded timestamp would fail the 30-second check.
// =============================================================================

@Preview(
  name: 'Sensor Detail — Server mode',
  size: Size(390, 844),
)
Widget sensorDetailScreenPreview() {
  final now = DateTime.now().toUtc().toIso8601String();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SensorDetailScreen(
      previewMode: true,
      deviceData: {
        'id': 'SU202601003',
        'unit_name': 'Greenhouse Sensor',
        'unit_version': '1.0.0',
        'unit_last_seen': now,
        'last_seen': now,
        'no_sensors': '2',
        'sensor_data':
            '[{"sensor_id":"S00","sensor_type":"Temperature","sensor_name":"Temperature","sensor_value":"24.5"},{"sensor_id":"S01","sensor_type":"Humidity","sensor_name":"Humidity","sensor_value":"61"}]',
      },
    ),
  );
}

@Preview(
  name: 'Sensor Detail — Direct mode',
  size: Size(390, 844),
)
Widget sensorDetailScreenDirectPreview() {
  final now = DateTime.now().toUtc().toIso8601String();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    home: SensorDetailScreen(
      previewMode: true,
      isDirectMode: true,
      deviceData: {
        'id': 'SU202601003',
        'unit_name': 'Greenhouse Sensor',
        'unit_version': '1.0.0',
        'unit_last_seen': now,
        'last_seen': now,
        'no_sensors': '2',
        'sensor_data':
            '[{"sensor_id":"S00","sensor_type":"Temperature","sensor_name":"Temperature","sensor_value":"24.5"},{"sensor_id":"S01","sensor_type":"Humidity","sensor_name":"Humidity","sensor_value":"61"}]',
      },
    ),
  );
}