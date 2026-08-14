import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import '../../services/websocket_service.dart';
import '../../services/esp_direct_service.dart';
import '../../services/device_control_service.dart';
import '../motor_calibration_screen.dart';

// Local card widgets
import 'widgets/device_info_card.dart';
import 'widgets/mode_toggle_card.dart';
import 'widgets/control_mode_card.dart';
import 'widgets/valve_control_card.dart';
import 'widgets/schedule_card.dart';
import 'widgets/sensor_card.dart';
import 'widgets/change_wifi_button.dart';
import 'widgets/motor_calibration_button.dart';

// =============================================================================
// DEVICE DETAIL SCREEN
// =============================================================================
// Screen for one valve. Owns ALL state, REST calls, WebSocket subscriptions,
// ESP32-direct subscriptions, timers, dialogs, and helper logic. The build
// method just composes the card widgets in widgets/ and wires them up via
// callbacks.
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
  // SECTION 1: STATE VARIABLES
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

  // -- Confirmation tracking (waiting for vwv_pos to match target) --
  bool _waitingForConfirmation = false;
  int? _pendingTargetAngle;
  Timer? _confirmationTimer;
  int _confirmationCountdown = 0;

  // -- Angle control (angle mode) --
  double _sliderAngle = 0;
  bool _isAngleUpdating = false;
  bool _userIsEditingAngle = false;
  Timer? _angleEditDebounce;

  // -- Schedule data --
  List<Map<String, dynamic>> _schedules = [];
  bool _isSavingSchedule = false;
  bool _schedulesLoadedFromServer = false;
  bool _schedulesLocallyEdited = false;

  // -- Stream subscriptions (server mode) --
  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<Map<String, dynamic>>? _scheduleSub;
  StreamSubscription<bool>? _connectionSub;

  // -- Stream subscriptions (direct mode) --
  StreamSubscription<Map<String, dynamic>>? _espValveDataSub;
  StreamSubscription<bool>? _espConnectionSub;
  Timer? _espPollTimer;

  // -- Constants --
  static const List<String> _dayOptions = [
    'Every day',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  // -- Shortcut --
  bool get _isDirectMode => widget.isDirectMode;

  // ===========================================================================
  // SECTION 2: LIFECYCLE METHODS
  // ===========================================================================

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);

    // Read initial schedule mode from DB field user_schedule_ctrl
    final scheduleCtrl = _device['user_schedule_ctrl'];
    _isScheduleMode =
        (scheduleCtrl == 1 || scheduleCtrl == '1' || scheduleCtrl == true);

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
    final vwvPos = _device['vwv_pos'];
    if (vwvPos != null) {
      _sliderAngle = (int.tryParse(vwvPos.toString()) ?? 0).toDouble();
    }

    if (_isDirectMode) {
      _setupEspDirect();
    } else {
      _setupWebSocket();
    }
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _scheduleSub?.cancel();
    _connectionSub?.cancel();
    _espValveDataSub?.cancel();
    _espConnectionSub?.cancel();
    _espPollTimer?.cancel();
    _confirmationTimer?.cancel();
    _angleEditDebounce?.cancel();
    if (!_isDirectMode) {
      WebSocketService.subscribeTo('device_list');
    }
    super.dispose();
  }

  // ===========================================================================
  // SECTION 3: WEBSOCKET SETUP (SERVER MODE)
  // ===========================================================================

  void _setupWebSocket() {
    _wsConnected = WebSocketService.isConnected;

    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (mounted && data['id']?.toString() == _device['id']?.toString()) {
        setState(() {
          _device = {..._device, ...data};
        });

        // Sync schedule mode from server (unless we're in the middle of
        // sending a switch ourselves)
        if (!_isSwitchingMode) {
          final scheduleCtrl = _device['user_schedule_ctrl'];
          final serverScheduleMode = (scheduleCtrl == 1 ||
              scheduleCtrl == '1' ||
              scheduleCtrl == true);
          if (serverScheduleMode != _isScheduleMode) {
            setState(() {
              _isScheduleMode = serverScheduleMode;
              _controlMode = serverScheduleMode ? 'schedule' : 'manual';
            });
          }
        }

        // Confirmation check: did vwv_pos catch up to our pending target?
        if (_waitingForConfirmation && _pendingTargetAngle != null) {
          final actualPos =
              int.tryParse((_device['vwv_pos'] ?? '').toString()) ?? -1;
          if (actualPos == _pendingTargetAngle) {
            _onConfirmationSuccess();
          }
        }

        // Update slider from actual position when user is NOT editing and
        // NOT waiting for an angle-mode confirmation
        if (!_userIsEditingAngle &&
            !(_waitingForConfirmation && !_valveControlEnabled)) {
          final vwvPos = _device['vwv_pos'];
          if (vwvPos != null) {
            final parsed = int.tryParse(vwvPos.toString());
            if (parsed != null) {
              setState(() => _sliderAngle = parsed.toDouble());
            }
          }
        }
      }
    });

    _scheduleSub = WebSocketService.scheduleStream.listen((data) {
      if (mounted &&
          data['device_id']?.toString() == _device['id']?.toString() &&
          !_schedulesLocallyEdited) {
        _loadScheduleFromServer(data);
      }
    });

    WebSocketService.subscribeTo(
      'device_detail',
      deviceId: _device['id']?.toString(),
    );
  }

  // ===========================================================================
  // SECTION 4: ESP32 DIRECT SETUP
  // ===========================================================================

  void _setupEspDirect() {
    final esp = EspDirectService.instance;
    _wsConnected = esp.isConnected;

    _espConnectionSub = esp.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    _espValveDataSub = esp.valveDataStream.listen((data) {
      if (!mounted) return;

      final valveData = data['get_valvedata'] ?? {};
      final angle = valveData['angle'];
      final isOpen = valveData['is_open'];
      final isClose = valveData['is_close'];

      // Map ESP32 valve_data fields → server DB-equivalent fields so the
      // rest of this screen's UI logic works the same in both modes.
      if (angle != null) {
        final angleInt =
            angle is int ? angle : int.tryParse(angle.toString()) ?? 0;
        setState(() {
          _device['vwv_pos'] = angleInt.toString();
          _device['vwv_is_open'] = (isOpen == true) ? 1 : 0;
          _device['vwv_is_close'] = (isClose == true) ? 1 : 0;
          if (!_userIsEditingAngle) {
            _sliderAngle = angleInt.toDouble();
          }
        });
      }

      // Confirmation check (same logic as server mode)
      if (_waitingForConfirmation && _pendingTargetAngle != null) {
        final actualPos = _getActualPosition();
        if (actualPos == _pendingTargetAngle) {
          _onConfirmationSuccess();
        }
      }

      print("📱 ESP32 Direct: valve angle=$angle, open=$isOpen, close=$isClose");
    });

    // Initial request, then poll every 2 seconds
    _requestEspValveData();
    _espPollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && esp.isAuthenticated) {
        _requestEspValveData();
      }
    });
  }

  void _requestEspValveData() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) return;

    final userId = _device['user_id']?.toString() ?? 'app_user';
    final deviceId = _device['id']?.toString() ?? '';
    final deviceName =
        _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
    esp.requestValveData(
      userId: userId,
      deviceId: deviceId,
      deviceName: deviceName,
    );
  }

  // ===========================================================================
  // SECTION 5: HELPER METHODS (read-only state queries)
  // ===========================================================================

  /// Single snackbar helper. Default duration matches Flutter's own SnackBar
  /// default (4 s), so callers only pass one when they want the shorter
  /// 2-second confirmation toast.
  void _showSnack(String message, Color color, {Duration? duration}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  bool _isDeviceOnline(String? lastSeen) {
    if (lastSeen == null || lastSeen.isEmpty || lastSeen == 'NULL') {
      return false;
    }
    try {
      final lastSeenTime = DateTime.parse(lastSeen);
      final now = DateTime.now();
      return now.difference(lastSeenTime).inSeconds <= 30;
    } catch (e) {
      print("⚠️ Error parsing vwv_last_seen: $e");
      return false;
    }
  }

  int _getActualPosition() {
    return int.tryParse((_device['vwv_pos'] ?? '0').toString()) ?? 0;
  }

  int _getUserRequestedPosition() {
    return int.tryParse((_device['user_vwv_pos'] ?? '0').toString()) ?? 0;
  }

  bool _isValveOpen() {
    if (_waitingForConfirmation && _pendingTargetAngle != null) {
      return _pendingTargetAngle! >= 45;
    }
    return _getActualPosition() >= 45;
  }

  String _formatTime(TimeOfDay time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  TimeOfDay _parseTime(String timeStr) {
    final parts = timeStr.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  // ===========================================================================
  // SECTION 6: MODE SWITCH (Manual ↔ Schedule)
  // ===========================================================================

  Future<void> _sendModeSwitch(bool scheduleMode) async {
    setState(() => _isSwitchingMode = true);

    final result = await DeviceControlService.instance.setValveBasic(
      deviceId: _device['id'],
      name: _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
      angle: _getActualPosition(),
      scheduleMode: scheduleMode,
      includeMeta: true,
      logLabel: 'Mode Switch',
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isScheduleMode = scheduleMode;
        _controlMode = scheduleMode ? 'schedule' : 'manual';
      });
      _showSnack(
        scheduleMode
            ? 'Switched to Schedule mode — valve follows schedule'
            : 'Switched to Manual mode — you control the valve',
        Colors.blue,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showSnack(result.displayMessage, Colors.red);
    }

    setState(() => _isSwitchingMode = false);
  }

  // ===========================================================================
  // SECTION 7: VALVE COMMANDS (Open/Close + Angle)
  // ===========================================================================

  Future<void> _sendControlCommand(String command) async {
    setState(() => _isUpdating = true);

    final int targetAngle = (command == "Open") ? 90 : 0;

    // ── Direct mode: send straight to ESP32 ──
    if (_isDirectMode) {
      final deviceName =
          _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
      print("📤 ESP32 Direct: set_valve_basic angle=$targetAngle");
      EspDirectService.instance.setValveAngle(
        angle: targetAngle,
        deviceName: deviceName,
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _requestEspValveData();
      });

      if (mounted) {
        _startConfirmationWait(targetAngle);
        _showSnack(
          'Direct command sent! Valve ${command == "Open" ? "opening" : "closing"}...',
          Colors.blue,
          duration: const Duration(seconds: 2),
        );
        setState(() => _isUpdating = false);
      }
      return;
    }

    // ── Server mode: REST via DeviceControlService ──
    final result = await DeviceControlService.instance.setValveBasic(
      deviceId: _device['id'],
      name: _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
      angle: targetAngle,
      scheduleMode: false,
      logLabel: 'State',
    );

    if (!mounted) return;

    if (result.success) {
      _startConfirmationWait(targetAngle);
      _showSnack(
        'Command sent! Waiting for valve to ${command == "Open" ? "open" : "close"}...',
        Colors.blue,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showSnack(result.displayMessage, Colors.red);
    }

    setState(() => _isUpdating = false);
  }

  Future<void> _sendAngleCommand(int angle) async {
    setState(() => _isAngleUpdating = true);

    // ── Direct mode ──
    if (_isDirectMode) {
      final deviceName =
          _device['vwv_name'] ?? _device['device_name'] ?? 'Valve';
      print("📤 ESP32 Direct: set_valve_basic angle=$angle");
      EspDirectService.instance.setValveAngle(
        angle: angle,
        deviceName: deviceName,
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _requestEspValveData();
      });

      if (mounted) {
        _startConfirmationWait(angle);
        _showSnack(
          'Direct command sent! Setting angle to $angle°...',
          Colors.blue,
          duration: const Duration(seconds: 2),
        );
        setState(() => _isAngleUpdating = false);
      }
      return;
    }

    // ── Server mode ──
    final result = await DeviceControlService.instance.setValveBasic(
      deviceId: _device['id'],
      name: _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
      angle: angle,
      scheduleMode: false,
      logLabel: 'Angle',
    );

    if (!mounted) return;

    if (result.success) {
      _startConfirmationWait(angle);
      _showSnack(
        'Command sent! Waiting for valve to reach $angle°...',
        Colors.blue,
        duration: const Duration(seconds: 2),
      );
    } else {
      _showSnack(result.displayMessage, Colors.red);
    }

    setState(() => _isAngleUpdating = false);
  }

  // ===========================================================================
  // SECTION 8: CONFIRMATION WAIT LOGIC
  // ===========================================================================

  void _startConfirmationWait(int targetAngle) {
    _confirmationTimer?.cancel();

    // Direct mode talks straight to the ESP32 over the local AP, so the
    // valve confirms its position much faster — 10s is plenty. Server
    // mode goes through the cloud, so we give it the full 20s.
    final int timeoutSeconds = _isDirectMode ? 10 : 20;

    setState(() {
      _waitingForConfirmation = true;
      _pendingTargetAngle = targetAngle;
      _confirmationCountdown = timeoutSeconds;
    });

    _confirmationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _confirmationCountdown--);

      if (_confirmationCountdown <= 0) {
        timer.cancel();
        _onConfirmationTimeout();
      }
    });
  }

  void _onConfirmationSuccess() {
    _confirmationTimer?.cancel();
    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Valve position confirmed!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Timeout: do NOT revert the slider — the next WebSocket / ESP push will
  /// carry the real position within ~2 seconds and the UI self-corrects.
  void _onConfirmationTimeout() {
    final actualPos = _getActualPosition();
    final targetWas = _pendingTargetAngle;

    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
    });

    if (targetWas != null && actualPos == targetWas) {
      _onConfirmationSuccess();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                '⏳ Valve is still responding. Position will update shortly.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ===========================================================================
  // SECTION 9: SCHEDULE LOGIC (load + save + delete)
  // ===========================================================================

  /// Parse schedule data from WebSocket device_schedule event.
  /// Server sends: {"event":"device_schedule", "device_id":"...",
  ///                "schedule":{ ..., "schedule":"[JSON string]", ... }}
  void _loadScheduleFromServer(Map<String, dynamic> data) {
    try {
      final scheduleData = data['schedule'];
      if (scheduleData == null) return;

      final scheduleJson = scheduleData['schedule'];
      if (scheduleJson == null || scheduleJson.toString().isEmpty) {
        setState(() {
          _schedules = [];
          _schedulesLoadedFromServer = true;
        });
        return;
      }

      List<dynamic> parsed;
      if (scheduleJson is String) {
        parsed = jsonDecode(scheduleJson);
      } else if (scheduleJson is List) {
        parsed = scheduleJson;
      } else {
        print("⚠️ Unexpected schedule format: ${scheduleJson.runtimeType}");
        return;
      }

      setState(() {
        _schedules =
            parsed.map((e) => Map<String, dynamic>.from(e)).toList();
        _schedulesLoadedFromServer = true;
      });

      print("📅 Loaded ${_schedules.length} schedule entries from server");
    } catch (e) {
      print("❌ Error parsing schedule data: $e");
    }
  }

  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);

    final result = await DeviceControlService.instance.setSchedule(
      deviceId: _device['id'],
      schedules: _schedules,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() => _schedulesLocallyEdited = false);
      _showSnack('Schedule saved successfully!', Colors.green);
    } else {
      _showSnack(result.displayMessage, Colors.red);
    }

    setState(() => _isSavingSchedule = false);
  }

  // ===========================================================================
  // SECTION 10: DIALOGS
  // ===========================================================================

  // -------------------------------------------------------------------------
  // 10.1  Add / Edit Schedule Dialog
  // -------------------------------------------------------------------------
  void _showAddScheduleDialog({int? editIndex}) {
    String selectedDay =
        editIndex != null ? _schedules[editIndex]['day'] : 'Every day';
    TimeOfDay openTime = editIndex != null
        ? _parseTime(_schedules[editIndex]['open'] ?? '08:00')
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay closeTime = editIndex != null
        ? _parseTime(_schedules[editIndex]['close'] ?? '08:20')
        : const TimeOfDay(hour: 8, minute: 20);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(editIndex != null ? 'Edit Schedule' : 'Add Schedule'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Day picker
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _dayOptions
                        .map((d) =>
                            DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedDay = val!);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Open time picker
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: openTime,
                      );
                      if (picked != null) {
                        setDialogState(() => openTime = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Open Time',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(openTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          Icon(Icons.access_time, color: Colors.green[600]),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Close time picker
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: closeTime,
                      );
                      if (picked != null) {
                        setDialogState(() => closeTime = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Close Time',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatTime(closeTime),
                            style: const TextStyle(fontSize: 16),
                          ),
                          Icon(Icons.access_time, color: Colors.red[600]),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final entry = {
                      'day': selectedDay,
                      'open': _formatTime(openTime),
                      'close': _formatTime(closeTime),
                    };

                    setState(() {
                      _schedulesLocallyEdited = true;
                      if (editIndex != null) {
                        _schedules[editIndex] = entry;
                      } else {
                        _schedules.add(entry);
                      }
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(editIndex != null ? 'Update' : 'Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // 10.2  Delete Schedule Dialog
  // -------------------------------------------------------------------------
  void _deleteSchedule(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Schedule'),
        content: Text(
            'Delete "${_schedules[index]['day']} — Open: ${_schedules[index]['open']}, Close: ${_schedules[index]['close']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _schedulesLocallyEdited = true;
                _schedules.removeAt(index);
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 10.3  Edit Device Name Dialog
  // -------------------------------------------------------------------------
  void _showEditNameDialog() {
    final controller = TextEditingController(
        text: _device['vwv_name'] ?? _device['device_name']);
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Edit Device Name'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Device Name',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      final newName = controller.text.trim();
                      if (newName.isEmpty) return;

                      setDialogState(() => isSaving = true);

                      final success = await _saveDeviceName(newName);

                      if (success && mounted) {
                        setState(() {
                          _device['vwv_name'] = newName;
                          _device['device_name'] = newName;
                        });
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device name updated!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        setDialogState(() => isSaving = false);
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Save device name via control_device.php (set_valve_basic with valve_data.name)
  Future<bool> _saveDeviceName(String newName) async {
    final result = await DeviceControlService.instance.setValveBasic(
      deviceId: _device['id'],
      name: newName,
      angle: _getActualPosition(),
      scheduleMode: _isScheduleMode,
      includeMeta: true,
      logLabel: 'Name Update',
    );

    if (result.success) return true;

    _showSnack(result.displayMessage, Colors.red);
    return false;
  }

  // -------------------------------------------------------------------------
  // 10.4  WiFi Credentials Dialog (Direct mode)
  // -------------------------------------------------------------------------
  /// Shows a popup to enter home WiFi SSID and password, then sends
  /// set_valve_wifi to the connected ESP32. Architecture Doc Page 13.
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
              Icon(Icons.wifi, color: Color(0xFF3F51B5)),
              SizedBox(width: 10),
              Text('Set Home WiFi'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter your home WiFi credentials. The valve will restart and connect to this network.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                                'Not connected to valve. Go back and reconnect.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }

                      setDialogState(() => isSending = true);

                      EspDirectService.instance.setWifiCredentials(
                        ssid: ssid,
                        password: password,
                      );

                      print("📤 ESP32: set_valve_wifi ssid=$ssid");

                      // ESP32 will restart — connection will be lost
                      Future.delayed(const Duration(seconds: 3), () {
                        if (mounted) {
                          Navigator.pop(dialogContext);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'WiFi credentials sent! Valve will restart and connect to your home WiFi.',
                              ),
                              backgroundColor: Colors.green,
                              duration: Duration(seconds: 5),
                            ),
                          );
                        }
                      });
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.send),
              label: Text(isSending ? 'Sending...' : 'Save & Connect'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 11: BUILD METHOD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    final bool isOnline = _isDirectMode
        ? true
        : _isDeviceOnline(_device['vwv_last_seen']?.toString());

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
            // 11.1  Device info card (always shown)
            DeviceInfoCard(
              productType: _device['vwv_version']?.toString() ?? 'Unknown',
              deviceName: _device['vwv_name'] ??
                  _device['device_name'] ??
                  'Unknown',
              isOnline: isOnline,
              isDirectMode: _isDirectMode,
              onEditName: _showEditNameDialog,
            ),

            const SizedBox(height: 16),

            // 11.2  Mode toggle (server mode only)
            if (!_isDirectMode) ...[
              ModeToggleCard(
                isScheduleMode: _isScheduleMode,
                isSwitching: _isSwitchingMode,
                onModeChanged: _sendModeSwitch,
              ),
              const SizedBox(height: 16),
            ],

            // 11.3  Control mode selector (server mode + manual mode only)
            if (!_isScheduleMode && !_isDirectMode) ...[
              ControlModeCard(
                controlMode: _controlMode,
                isDirectMode: _isDirectMode,
                onModeSelected: (mode) =>
                    setState(() => _controlMode = mode),
                onDisabledTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                          Text('Schedule & Sensor require server connection'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            // 11.4  Schedule card (when schedule mode is on)
            if (_isScheduleMode)
              ScheduleCard(
                schedules: _schedules,
                isSavingSchedule: _isSavingSchedule,
                onAddPressed: _showAddScheduleDialog,
                onRowTapped: (i) => _showAddScheduleDialog(editIndex: i),
                onRowDeleted: _deleteSchedule,
                onSavePressed: _saveSchedule,
              ),

            // 11.5  Manual mode → Valve control card
            if (!_isScheduleMode && _controlMode == 'manual')
              ValveControlCard(
                valveControlEnabled: _valveControlEnabled,
                onValveControlEnabledChanged: (v) =>
                    setState(() => _valveControlEnabled = v),
                isOpen: _isValveOpen(),
                actualPosition: _getActualPosition(),
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
                waitingForConfirmation: _waitingForConfirmation,
                pendingTargetAngle: _pendingTargetAngle,
                confirmationCountdown: _confirmationCountdown,
              ),

            // 11.6  Schedule card (selected from control-mode buttons)
            if (!_isScheduleMode && _controlMode == 'schedule')
              ScheduleCard(
                schedules: _schedules,
                isSavingSchedule: _isSavingSchedule,
                onAddPressed: _showAddScheduleDialog,
                onRowTapped: (i) => _showAddScheduleDialog(editIndex: i),
                onRowDeleted: _deleteSchedule,
                onSavePressed: _saveSchedule,
              ),

            // 11.7  Sensor card (placeholder)
            if (!_isScheduleMode && _controlMode == 'sensor')
              const SensorCard(),

            const SizedBox(height: 16),

            // 11.8  Direct-mode action buttons
            if (_isDirectMode) ...[
              ChangeWifiButton(onPressed: _showWifiCredentialsDialog),
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