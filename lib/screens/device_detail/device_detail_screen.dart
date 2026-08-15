import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/device_control_api.dart';
import '../motor_calibration_screen.dart';

// Controllers (live data + confirmation wait)
import 'controllers/device_feeds.dart';
import 'controllers/valve_confirmation_controller.dart';

// Dialogs
import 'dialogs/edit_device_name_dialog.dart';
import 'dialogs/schedule_dialogs.dart';
import 'dialogs/wifi_credentials_dialog.dart';

// Pure helpers
import 'utils/schedule_utils.dart';
import 'utils/valve_utils.dart';

// Card widgets
import 'widgets/change_wifi_button.dart';
import 'widgets/control_mode_card.dart';
import 'widgets/device_info_card.dart';
import 'widgets/mode_toggle_card.dart';
import 'widgets/motor_calibration_button.dart';
import 'widgets/schedule_card.dart';
import 'widgets/sensor_card.dart';
import 'widgets/valve_control_card.dart';

// =============================================================================
// DEVICE DETAIL SCREEN
// =============================================================================
// Screen for one valve. It owns the UI state and wires everything together;
// the heavy lifting lives next door:
//
//   services/device_control_api.dart      → REST calls to control_device.php
//   controllers/device_feeds.dart         → WebSocket / ESP32 subscriptions
//   controllers/valve_confirmation_*.dart → "waiting for the valve" countdown
//   dialogs/                              → add-edit schedule, rename, wifi
//   utils/                                → time + angle + payload parsing
//   widgets/                              → the cards this screen composes
//
// Two modes:
//   - Server mode (isDirectMode = false): WebSocket + REST through the cloud
//   - Direct mode (isDirectMode = true):  Talks straight to the ESP32 over
//                                         its AP via EspDirectService
// =============================================================================

class DeviceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData;
  final bool isDirectMode;

  const DeviceDetailScreen({
    super.key,
    required this.deviceData,
    this.isDirectMode = false,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  // ===========================================================================
  // SECTION 1: STATE
  // ===========================================================================

  // -- Device data --
  late Map<String, dynamic> _device;

  // -- Connection state --
  bool _wsConnected = false;

  // -- Control mode: 'manual' | 'schedule' | 'sensor' --
  String _controlMode = 'manual';

  // -- Schedule/Manual mode toggle (synced with user_schedule_ctrl in DB) --
  bool _isScheduleMode = false;
  bool _isSwitchingMode = false;

  // -- Valve control (state mode) --
  bool _isUpdating = false;
  bool _valveControlEnabled = true; // ON = state mode, OFF = angle mode

  // -- Angle control (angle mode) --
  double _sliderAngle = 0;
  bool _isAngleUpdating = false;
  bool _userIsEditingAngle = false;
  Timer? _angleEditDebounce;

  // -- Schedule data --
  List<Map<String, dynamic>> _schedules = [];
  bool _isSavingSchedule = false;
  bool _schedulesLocallyEdited = false;

  // -- Controllers --
  late final ValveConfirmationController _confirmation;
  ServerDeviceFeed? _serverFeed;
  DirectDeviceFeed? _directFeed;

  // -- Shortcuts --
  bool get _isDirectMode => widget.isDirectMode;

  String get _deviceName =>
      _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown';

  /// Position the valve actually reports, in degrees.
  int get _actualPosition => parseAngle(_device['vwv_pos']);

  /// Where the valve will be once the pending command lands.
  bool get _isValveOpen {
    final pending = _confirmation.targetAngle;
    if (_confirmation.isWaiting && pending != null) {
      return pending >= kValveOpenAngle;
    }
    return _actualPosition >= kValveOpenAngle;
  }

  // ===========================================================================
  // SECTION 2: LIFECYCLE
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);
    print("🔍 INIT _device = $_device");

    _confirmation = ValveConfirmationController(
      onChanged: () {
        if (mounted) setState(() {});
      },
      onSuccess: () => _showMessage(
        '✅ Valve position confirmed!',
        color: Colors.green,
        duration: const Duration(seconds: 2),
      ),
      onTimeout: _onConfirmationTimeout,
    );

    // Read initial schedule mode from DB field user_schedule_ctrl
    _isScheduleMode = _readScheduleFlag(_device['user_schedule_ctrl']);

    if (_isDirectMode) {
      // Direct mode: only manual control is allowed; clear cached state so
      // the first ESP32 poll response is the source of truth.
      _controlMode = 'manual';
      _isScheduleMode = false;
      _device['vwv_pos'] = null;
      _device['vwv_is_open'] = null;
      _device['vwv_is_close'] = null;
    } else {
      _controlMode = _isScheduleMode ? 'schedule' : 'manual';
    }

    // Initialize slider angle from DB
    if (_device['vwv_pos'] != null) {
      _sliderAngle = _actualPosition.toDouble();
    }

    if (_isDirectMode) {
      _startDirectFeed();
    } else {
      _startServerFeed();
    }
  }

  @override
  void dispose() {
    _serverFeed?.dispose();
    _directFeed?.dispose();
    _confirmation.dispose();
    _angleEditDebounce?.cancel();
    super.dispose();
  }

  /// `user_schedule_ctrl` arrives as 1, '1' or true depending on the source.
  bool _readScheduleFlag(Object? raw) =>
      raw == 1 || raw == '1' || raw == true;

  // ===========================================================================
  // SECTION 3: LIVE DATA (server WebSocket / ESP32 direct)
  // ===========================================================================

  void _startServerFeed() {
    final feed = ServerDeviceFeed(
      deviceId: _device['id']?.toString(),
      onConnectionChanged: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onDeviceUpdate: _onServerDeviceUpdate,
      onScheduleUpdate: _onServerScheduleUpdate,
    );

    _serverFeed = feed;
    _wsConnected = feed.isConnected;
    feed.start();
  }

  void _startDirectFeed() {
    final feed = DirectDeviceFeed(
      device: () => _device,
      onConnectionChanged: (connected) {
        if (mounted) setState(() => _wsConnected = connected);
      },
      onValveData: _onDirectValveData,
    );

    _directFeed = feed;
    _wsConnected = feed.isConnected;
    feed.start();
  }

  void _onServerDeviceUpdate(Map<String, dynamic> data) {
    if (!mounted) return;

    setState(() => _device = {..._device, ...data});

    // Sync schedule mode from server (unless we're in the middle of sending a
    // switch ourselves)
    if (!_isSwitchingMode) {
      final serverScheduleMode = _readScheduleFlag(_device['user_schedule_ctrl']);
      if (serverScheduleMode != _isScheduleMode) {
        setState(() {
          _isScheduleMode = serverScheduleMode;
          _controlMode = serverScheduleMode ? 'schedule' : 'manual';
        });
      }
    }

    // Did vwv_pos catch up to our pending target? (-1 so a missing position
    // can never be mistaken for a real 0°)
    _confirmation.reportPosition(parseAngle(_device['vwv_pos'], fallback: -1));

    // Follow the reported position while the user isn't dragging and we aren't
    // waiting on an angle-mode confirmation.
    if (!_userIsEditingAngle &&
        !(_confirmation.isWaiting && !_valveControlEnabled)) {
      final reported = _device['vwv_pos'];
      final parsed = reported == null ? null : int.tryParse(reported.toString());
      if (parsed != null) {
        setState(() => _sliderAngle = parsed.toDouble());
      }
    }
  }

  void _onServerScheduleUpdate(Map<String, dynamic> data) {
    // Never overwrite edits the user hasn't saved yet.
    if (!mounted || _schedulesLocallyEdited) return;

    final parsed = parseSchedulePayload(data);
    if (parsed == null) return;

    setState(() => _schedules = parsed);
    print("📅 Loaded ${_schedules.length} schedule entries from server");
  }

  /// Maps the ESP32's `get_valvedata` fields onto the server DB-equivalent
  /// fields, so the rest of this screen works the same in both modes.
  void _onDirectValveData(Map<String, dynamic> valveData) {
    if (!mounted) return;

    final angle = valveData['angle'];
    if (angle != null) {
      final angleInt = parseAngle(angle);
      setState(() {
        _device['vwv_pos'] = angleInt.toString();
        _device['vwv_is_open'] = (valveData['is_open'] == true) ? 1 : 0;
        _device['vwv_is_close'] = (valveData['is_close'] == true) ? 1 : 0;
        if (!_userIsEditingAngle) {
          _sliderAngle = angleInt.toDouble();
        }
      });
    }

    _confirmation.reportPosition(_actualPosition);
  }

  // ===========================================================================
  // SECTION 4: MODE SWITCH (Manual ↔ Schedule)
  // ===========================================================================

  Future<void> _sendModeSwitch(bool scheduleMode) async {
    setState(() => _isSwitchingMode = true);

    final result = await DeviceControlApi.switchControlMode(
      deviceId: _device['id'],
      deviceName: _deviceName,
      angle: _actualPosition,
      scheduleMode: scheduleMode,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isScheduleMode = scheduleMode;
        _controlMode = scheduleMode ? 'schedule' : 'manual';
      });
      _showMessage(
        scheduleMode
            ? 'Switched to Schedule mode — valve follows schedule'
            : 'Switched to Manual mode — you control the valve',
        color: Colors.blue,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showMessage(result.displayMessage, color: Colors.red);
    }

    setState(() => _isSwitchingMode = false);
  }

  // ===========================================================================
  // SECTION 5: VALVE COMMANDS (Open/Close + Angle)
  // ===========================================================================

  Future<void> _sendControlCommand(String command) async {
    final bool opening = command == 'Open';
    final int targetAngle = opening ? 90 : 0;

    setState(() => _isUpdating = true);

    if (_isDirectMode) {
      _sendDirectAngle(targetAngle);
      _showMessage(
        'Direct command sent! Valve ${opening ? "opening" : "closing"}...',
        color: Colors.blue,
        duration: const Duration(seconds: 2),
      );
      setState(() => _isUpdating = false);
      return;
    }

    final result = await DeviceControlApi.setValveAngle(
      deviceId: _device['id'],
      deviceName: _deviceName,
      angle: targetAngle,
    );

    if (!mounted) return;

    if (result.success) {
      _startConfirmationWait(targetAngle);
      _showMessage(
        'Command sent! Waiting for valve to ${opening ? "open" : "close"}...',
        color: Colors.blue,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showMessage(result.displayMessage, color: Colors.red);
    }

    setState(() => _isUpdating = false);
  }

  Future<void> _sendAngleCommand(int angle) async {
    setState(() => _isAngleUpdating = true);

    if (_isDirectMode) {
      _sendDirectAngle(angle);
      _showMessage(
        'Direct command sent! Setting angle to $angle°...',
        color: Colors.blue,
        duration: const Duration(seconds: 2),
      );
      setState(() => _isAngleUpdating = false);
      return;
    }

    final result = await DeviceControlApi.setValveAngle(
      deviceId: _device['id'],
      deviceName: _deviceName,
      angle: angle,
    );

    if (!mounted) return;

    if (result.success) {
      _startConfirmationWait(angle);
      _showMessage(
        'Command sent! Waiting for valve to reach $angle°...',
        color: Colors.blue,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showMessage(result.displayMessage, color: Colors.red);
    }

    setState(() => _isAngleUpdating = false);
  }

  /// Direct mode: straight to the ESP32, no REST round trip.
  void _sendDirectAngle(int angle) {
    _directFeed?.setValveAngle(angle);
    _startConfirmationWait(angle);
  }

  void _startConfirmationWait(int targetAngle) {
    _confirmation.start(
      targetAngle,
      timeoutSeconds: _isDirectMode
          ? kDirectConfirmationTimeoutSeconds
          : kServerConfirmationTimeoutSeconds,
    );
  }

  /// Timeout: do NOT revert the slider — the next WebSocket / ESP push will
  /// carry the real position within ~2 seconds and the UI self-corrects.
  void _onConfirmationTimeout(int targetAngle) {
    if (_actualPosition == targetAngle) {
      _showMessage(
        '✅ Valve position confirmed!',
        color: Colors.green,
        duration: const Duration(seconds: 2),
      );
      return;
    }

    _showMessage(
      '⏳ Valve is still responding. Position will update shortly.',
      color: Colors.orange,
      duration: const Duration(seconds: 3),
    );
  }

  // ===========================================================================
  // SECTION 6: SCHEDULE (add / edit / delete / save)
  // ===========================================================================

  Future<void> _showScheduleDialog({int? editIndex}) async {
    final entry = await showScheduleEntryDialog(
      context,
      initial: editIndex != null ? _schedules[editIndex] : null,
    );
    if (entry == null || !mounted) return;

    setState(() {
      _schedulesLocallyEdited = true;
      if (editIndex != null) {
        _schedules[editIndex] = entry;
      } else {
        _schedules.add(entry);
      }
    });
  }

  Future<void> _deleteSchedule(int index) async {
    final confirmed = await showDeleteScheduleDialog(context, _schedules[index]);
    if (!confirmed || !mounted) return;

    setState(() {
      _schedulesLocallyEdited = true;
      _schedules.removeAt(index);
    });
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);

    final result = await DeviceControlApi.saveSchedule(
      deviceId: _device['id'],
      schedules: _schedules,
    );

    if (!mounted) return;

    if (result.success) {
      // Saved — the server is authoritative again.
      setState(() => _schedulesLocallyEdited = false);
      _showMessage('Schedule saved successfully!', color: Colors.green);
    } else {
      _showMessage(result.displayMessage, color: Colors.red);
    }

    setState(() => _isSavingSchedule = false);
  }

  // ===========================================================================
  // SECTION 7: DEVICE NAME
  // ===========================================================================

  Future<void> _showEditNameDialog() async {
    final newName = await showEditDeviceNameDialog(
      context,
      currentName: _device['vwv_name'] ?? _device['device_name'],
      onSave: _saveDeviceName,
    );
    if (newName == null || !mounted) return;

    setState(() {
      _device['vwv_name'] = newName;
      _device['device_name'] = newName;
    });
    _showMessage('Device name updated!', color: Colors.green);
  }

  Future<bool> _saveDeviceName(String newName) async {
    final result = await DeviceControlApi.renameDevice(
      deviceId: _device['id'],
      newName: newName,
      angle: _actualPosition,
      scheduleMode: _isScheduleMode,
    );

    if (!result.success) {
      _showMessage(result.displayMessage, color: Colors.red);
    }
    return result.success;
  }

  // ===========================================================================
  // SECTION 8: SNACKBAR HELPER
  // ===========================================================================

  void _showMessage(String message, {Color? color, Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  // ===========================================================================
  // SECTION 9: BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isOnline = _isDirectMode
        ? true
        : isDeviceOnline(_device['vwv_last_seen']?.toString());

    return Scaffold(
      backgroundColor: Colors.grey[100],
      // ─── App bar ───────────────────────────────────────────────────────
      appBar: AppBar(
        title: Text(_isDirectMode ? 'Direct Control' : 'Vortex Labs'),
        backgroundColor:
            _isDirectMode ? Colors.green[700] : const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _wsConnected
                  ? (_isDirectMode ? Icons.settings_remote : Icons.wifi)
                  : Icons.wifi_off,
              color: _wsConnected ? Colors.greenAccent : Colors.red,
            ),
          ),
        ],
      ),
      // ─── Body ──────────────────────────────────────────────────────────
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 9.1  Device info card (always shown)
            DeviceInfoCard(
              productType: _device['vwv_version']?.toString() ?? 'Unknown',
              deviceName: _deviceName,
              isOnline: isOnline,
              isDirectMode: _isDirectMode,
              onEditName: _showEditNameDialog,
            ),

            const SizedBox(height: 16),

            // 9.2  Mode toggle (server mode only)
            if (!_isDirectMode) ...[
              ModeToggleCard(
                isScheduleMode: _isScheduleMode,
                isSwitching: _isSwitchingMode,
                onModeChanged: _sendModeSwitch,
              ),
              const SizedBox(height: 16),
            ],

            // 9.3  Control mode selector (server mode + manual mode only)
            if (!_isScheduleMode && !_isDirectMode) ...[
              ControlModeCard(
                controlMode: _controlMode,
                isDirectMode: _isDirectMode,
                onModeSelected: (mode) => setState(() => _controlMode = mode),
                onDisabledTap: () => _showMessage(
                  'Schedule & Sensor require server connection',
                  duration: const Duration(seconds: 2),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 9.4  Schedule card — either from the mode toggle or the
            //      control-mode buttons
            if (_isScheduleMode || _controlMode == 'schedule')
              ScheduleCard(
                schedules: _schedules,
                isSavingSchedule: _isSavingSchedule,
                onAddPressed: _showScheduleDialog,
                onRowTapped: (i) => _showScheduleDialog(editIndex: i),
                onRowDeleted: _deleteSchedule,
                onSavePressed: _saveSchedule,
              ),

            // 9.5  Manual mode → Valve control card
            if (!_isScheduleMode && _controlMode == 'manual')
              ValveControlCard(
                valveControlEnabled: _valveControlEnabled,
                onValveControlEnabledChanged: (v) =>
                    setState(() => _valveControlEnabled = v),
                isOpen: _isValveOpen,
                actualPosition: _actualPosition,
                isUpdating: _isUpdating,
                onOpenCloseToggled: (open) =>
                    _sendControlCommand(open ? 'Open' : 'Closed'),
                sliderAngle: _sliderAngle,
                isAngleUpdating: _isAngleUpdating,
                onSliderChanged: (v) => setState(() => _sliderAngle = v),
                onSliderEditStart: () {
                  // User started dragging — block WS from overwriting slider
                  _userIsEditingAngle = true;
                  _angleEditDebounce?.cancel();
                },
                onSliderEditEnd: () {
                  // Keep editing flag for 3s so the WS doesn't snap back
                  // before the user taps "Set Angle"
                  _angleEditDebounce?.cancel();
                  _angleEditDebounce = Timer(
                    const Duration(seconds: 3),
                    () {
                      if (mounted) {
                        setState(() => _userIsEditingAngle = false);
                      }
                    },
                  );
                },
                onSetAnglePressed: (angle) {
                  _angleEditDebounce?.cancel();
                  _userIsEditingAngle = false;
                  _sendAngleCommand(angle);
                },
                waitingForConfirmation: _confirmation.isWaiting,
                pendingTargetAngle: _confirmation.targetAngle,
                confirmationCountdown: _confirmation.countdown,
              ),

            // 9.6  Sensor card (placeholder)
            if (!_isScheduleMode && _controlMode == 'sensor')
              const SensorCard(),

            const SizedBox(height: 16),

            // 9.7  Direct-mode action buttons
            if (_isDirectMode) ...[
              ChangeWifiButton(
                onPressed: () => showWifiCredentialsDialog(context),
              ),
              const SizedBox(height: 12),
              MotorCalibrationButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          MotorCalibrationScreen(deviceData: _device),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
