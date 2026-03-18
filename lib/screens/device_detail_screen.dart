import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';
import 'manual_control_screen.dart';
import 'wifi_setup_screen.dart';

class DeviceDetailScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData;

  const DeviceDetailScreen({super.key, required this.deviceData});

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late Map<String, dynamic> _device;
  bool _wsConnected = false;

  // Control mode: 'manual', 'schedule', 'sensor'
  String _controlMode = 'manual';

  // Valve control
  bool _isUpdating = false;
  bool _valveControlEnabled = false; // Toggle: ON = state mode, OFF = angle mode

  // ── Valve state confirmation tracking ──
  // When user sends a command, we track the expected angle
  // and wait for vwv_pos in the DB to match within ~10 seconds.
  bool _waitingForConfirmation = false;
  int? _pendingTargetAngle; // 0 or 90
  Timer? _confirmationTimer;
  int _confirmationCountdown = 0; // seconds remaining

  // Angle control (for angle mode)
  double _sliderAngle = 0; // 0-90
  bool _isAngleUpdating = false;
  bool _userIsEditingAngle = false; // True while user is dragging slider
  Timer? _angleEditDebounce; // Debounce timer to reset editing flag

  // Schedule data - format per architecture doc: {day, open, close}
  List<Map<String, dynamic>> _schedules = [];
  bool _isSavingSchedule = false;
  bool _schedulesLoadedFromServer = false; // Track if we've loaded initial data
  bool _schedulesLocallyEdited = false; // Don't overwrite user's local edits

  // Stream subscriptions
  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<Map<String, dynamic>>? _scheduleSub;
  StreamSubscription<bool>? _connectionSub;

  // Day options
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

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);
    _controlMode = _device['control_mode'] ?? 'manual';

    // Initialize slider angle from DB
    final vwvPos = _device['vwv_pos'];
    if (vwvPos != null) {
      _sliderAngle = (int.tryParse(vwvPos.toString()) ?? 0).toDouble();
    }

    _setupWebSocket();
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _scheduleSub?.cancel();
    _connectionSub?.cancel();
    _confirmationTimer?.cancel();
    _angleEditDebounce?.cancel();
    // Switch back to device_list when leaving
    WebSocketService.subscribeTo('device_list');
    super.dispose();
  }

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

        // ── Check confirmation: compare vwv_pos with pending target ──
        if (_waitingForConfirmation && _pendingTargetAngle != null) {
          final actualPos = int.tryParse(
              (_device['vwv_pos'] ?? '').toString()) ?? -1;

          if (actualPos == _pendingTargetAngle) {
            // ✅ Valve reached target position - confirmed!
            _onConfirmationSuccess();
          }
        }

        // Update slider angle from actual position when user is NOT editing
        // and NOT waiting for angle confirmation
        if (!_userIsEditingAngle && !(_waitingForConfirmation && !_valveControlEnabled)) {
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

    // Listen to schedule updates from WebSocket
    _scheduleSub = WebSocketService.scheduleStream.listen((data) {
      if (mounted &&
          data['device_id']?.toString() == _device['id']?.toString() &&
          !_schedulesLocallyEdited) {
        _loadScheduleFromServer(data);
      }
    });

    // Subscribe to this device's detail
    WebSocketService.subscribeTo('device_detail',
        deviceId: _device['id']?.toString());
  }

  // ============================================================
  // VALVE: Get current state from DB fields
  // ============================================================

  /// Check if device is online: compare vwv_last_seen with phone time
  /// If gap > 5 seconds → offline
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

  /// Get the ACTUAL valve position from vwv_pos (physical position)
  int _getActualPosition() {
    return int.tryParse((_device['vwv_pos'] ?? '0').toString()) ?? 0;
  }

  // ============================================================
  // SCHEDULE: Load from WebSocket server data
  // ============================================================
  /// Parse schedule data from WebSocket device_schedule event
  /// Server sends: {"event":"device_schedule","device_id":"...","schedule":{...}}
  /// The schedule field contains: {"device_id":"...","schedule":"[JSON string]","set_schedule":1}
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

      // Parse JSON string — could be a String or already a List
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
        _schedules = parsed
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _schedulesLoadedFromServer = true;
      });

      print("📅 Loaded ${_schedules.length} schedule entries from server");
    } catch (e) {
      print("❌ Error parsing schedule data: $e");
    }
  }

  /// Get the USER-REQUESTED position from user_vwv_pos
  int _getUserRequestedPosition() {
    return int.tryParse((_device['user_vwv_pos'] ?? '0').toString()) ?? 0;
  }

  /// Determine if valve is open based on actual position
  bool _isValveOpen() {
    if (_waitingForConfirmation && _pendingTargetAngle != null) {
      // While waiting, show the pending state
      return _pendingTargetAngle! >= 45;
    }
    return _getActualPosition() >= 45;
  }

  // ============================================================
  // VALVE: Send Open/Close command via REST API
  // ============================================================
  Future<void> _sendControlCommand(String command) async {
    setState(() => _isUpdating = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    int targetAngle = (command == "Open") ? 90 : 0;

    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'device_id': _device['id'],
        'set_controller': {
          'schedule': false,
          'sensor': false,
        },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': targetAngle,
        }
      };

      print("📤 State Request Body: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      print("Control Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          // ── Start confirmation wait ──
          _startConfirmationWait(targetAngle);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Command sent! Waiting for valve to ${command == "Open" ? "open" : "close"}...'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("Control Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ============================================================
  // VALVE: Confirmation Wait Logic
  // ============================================================

  /// Start waiting for vwv_pos to match targetAngle (up to 10 seconds)
  void _startConfirmationWait(int targetAngle) {
    _confirmationTimer?.cancel();

    setState(() {
      _waitingForConfirmation = true;
      _pendingTargetAngle = targetAngle;
      _confirmationCountdown = 10;
    });

    // Check every second
    _confirmationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() => _confirmationCountdown--);

      if (_confirmationCountdown <= 0) {
        // ⏰ Timeout - revert to actual DB position
        timer.cancel();
        _onConfirmationTimeout();
      }
    });
  }

  /// Valve confirmed - position matches target
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

  /// Timeout - revert toggle/slider to actual DB position
  void _onConfirmationTimeout() {
    final actualPos = _getActualPosition();
    final targetWas = _pendingTargetAngle;

    setState(() {
      _waitingForConfirmation = false;
      _pendingTargetAngle = null;
      _confirmationCountdown = 0;
      // Revert slider to actual position
      _sliderAngle = actualPos.toDouble();
    });

    // Check if it partially reached
    if (targetWas != null && actualPos != targetWas) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '⚠️ Valve did not reach target ($targetWas°). Current position: $actualPos°'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } else {
      // It actually reached in the last moment
      _onConfirmationSuccess();
    }
  }

  // ============================================================
  // VALVE: Send Angle command via REST API (angle mode)
  // Uses same confirmation logic as state mode
  // ============================================================
  Future<void> _sendAngleCommand(int angle) async {
    setState(() => _isAngleUpdating = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final requestBody = {
        'event': 'set_valve_basic',
        'device_id': _device['id'],
        'set_controller': {
          'schedule': false,
          'sensor': false,
        },
        'valve_data': {
          'name': _device['vwv_name'] ?? _device['device_name'] ?? 'Unknown',
          'set_angle': true,
          'angle': angle,
        }
      };

      print("📤 Angle Request Body: ${jsonEncode(requestBody)}");

      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(requestBody),
      );

      print("Angle Control Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          // ── Start confirmation wait (same as state mode) ──
          _startConfirmationWait(angle);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Command sent! Waiting for valve to reach $angle°...'),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("Angle Control Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Connection failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isAngleUpdating = false);
    }
  }

  // ============================================================
  // SCHEDULE: Add Entry Dialog (Architecture doc format)
  // Each entry: { "day": "Monday", "open": "08:00", "close": "08:20" }
  // ============================================================
  void _showAddScheduleDialog({int? editIndex}) {
    // Pre-fill if editing
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
                  // Day Picker
                  DropdownButtonFormField<String>(
                    value: selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _dayOptions
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (val) {
                      setDialogState(() => selectedDay = val!);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Open Time Picker
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

                  // Close Time Picker
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

  // ============================================================
  // SCHEDULE: Delete Entry
  // ============================================================
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

  // ============================================================
  // SCHEDULE: Save to Server via REST API
  // ============================================================
  Future<void> _saveSchedule() async {
    setState(() => _isSavingSchedule = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    try {
      final response = await http.post(
        Uri.parse(
            'https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': 'set_valve_control',
          'device_id': _device['id'],
          'set_scheduledata': {
            'set_schedule': _schedules.isNotEmpty,
            'schedule_info': _schedules,
          },
        }),
      );

      print("📅 Schedule Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          setState(() => _schedulesLocallyEdited = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Schedule saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${result['message']}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print("📅 Schedule Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingSchedule = false);
    }
  }

  // ============================================================
  // Time Helpers
  // ============================================================
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

  // ============================================================
  // BUILD UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Vortex Labs'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _wsConnected ? Icons.wifi : Icons.wifi_off,
              color: _wsConnected ? Colors.greenAccent : Colors.red,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoCard(),
            const SizedBox(height: 16),
            _buildControlModeCard(),
            const SizedBox(height: 16),
            if (_controlMode == 'manual') _buildValveControlCard(),
            if (_controlMode == 'schedule') _buildScheduleCard(),
            if (_controlMode == 'sensor') _buildSensorCard(),
            const SizedBox(height: 16),
            _buildWifiButton(),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // INFO CARD
  // ============================================================
  Widget _buildInfoCard() {
    bool isOnline = _isDeviceOnline(_device['vwv_last_seen']?.toString());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow(
                'Product Type', _device['type'] ?? 'WiFi Valve v1'),
            const Divider(),
            _buildInfoRowWithEdit(
                'Name',
                _device['vwv_name'] ??
                    _device['device_name'] ??
                    'Unknown'),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Connection Status',
                    style: TextStyle(color: Colors.grey)),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isOnline ? 'online' : 'offline',
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildInfoRowWithEdit(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Row(
          children: [
            TextButton(
              onPressed: () => _showEditNameDialog(),
              child:
                  const Text('Edit', style: TextStyle(color: Colors.blue)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  // ============================================================
  // CONTROL MODE CARD
  // ============================================================
  Widget _buildControlModeCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Control by',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildModeButton('manual', Icons.pan_tool, 'manual'),
                _buildModeButton('schedule', Icons.schedule, 'schedule'),
                _buildModeButton('sensor', Icons.sensors, 'sensor'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeButton(String mode, IconData icon, String label) {
    bool isSelected = _controlMode == mode;

    return GestureDetector(
      onTap: () {
        setState(() => _controlMode = mode);
      },
      child: Container(
        width: 80,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3F51B5) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[600],
              size: 28,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // VALVE CONTROL CARD (Manual Mode)
  // Toggle ON  → State mode (Open/Close with DB confirmation)
  // Toggle OFF → Angle mode (Slider 0-90°)
  // ============================================================
  Widget _buildValveControlCard() {
    bool isOpen = _isValveOpen();
    int actualPos = _getActualPosition();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: "Valve control" + enable toggle ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Valve control',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Transform.scale(
                  scale: 1.2,
                  child: Switch(
                    value: _valveControlEnabled,
                    onChanged: _waitingForConfirmation
                        ? null // Disable mode switch while waiting
                        : (value) {
                            setState(() => _valveControlEnabled = value);
                          },
                    activeColor: const Color(0xFF3F51B5),
                  ),
                ),
              ],
            ),

            // ── Mode indicator ──
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _valveControlEnabled
                    ? 'Mode: Open / Close'
                    : 'Mode: Angle control',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // ── STATE MODE (when toggle is ON) ──
            if (_valveControlEnabled) ...[
              // Waiting indicator
              if (_waitingForConfirmation) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for valve... ${_confirmationCountdown}s',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        'Target: ${_pendingTargetAngle == 90 ? "Open" : "Close"}',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // By state row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('By state', style: TextStyle(color: Colors.grey)),
                  Row(
                    children: [
                      Text(
                        isOpen ? 'Open' : 'Close',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: isOpen
                              ? Colors.green[700]
                              : Colors.red[700],
                        ),
                      ),
                      const SizedBox(width: 8),
                      (_isUpdating || _waitingForConfirmation)
                          ? SizedBox(
                              width: 48,
                              height: 28,
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _waitingForConfirmation
                                        ? Colors.blue
                                        : null,
                                  ),
                                ),
                              ),
                            )
                          : Switch(
                              value: isOpen,
                              onChanged: (value) {
                                _sendControlCommand(
                                    value ? "Open" : "Closed");
                              },
                              activeColor: Colors.green,
                              inactiveTrackColor: Colors.red.shade200,
                              inactiveThumbColor: Colors.red,
                            ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Show actual position info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Actual position',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '$actualPos°',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: actualPos >= 45
                            ? Colors.green[700]
                            : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── ANGLE MODE (when toggle is OFF) ──
            if (!_valveControlEnabled) ...[
              const Text('By angle', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),

              // Waiting indicator (same style as state mode)
              if (_waitingForConfirmation) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Waiting for valve... ${_confirmationCountdown}s',
                          style: TextStyle(
                            color: Colors.blue.shade700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Text(
                        'Target: ${_pendingTargetAngle}°',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Angle dial visualization
              Center(
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Outer ring
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Colors.grey[300]!, width: 8),
                        ),
                      ),
                      // Angle indicator needle
                      Transform.rotate(
                        angle: (_sliderAngle / 90) * (math.pi / 2),
                        child: Container(
                          width: 4,
                          height: 50,
                          decoration: BoxDecoration(
                            color: _waitingForConfirmation
                                ? Colors.blue
                                : const Color(0xFF3F51B5),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Center dot
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _waitingForConfirmation
                              ? Colors.blue
                              : const Color(0xFF3F51B5),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Angle value display
              Center(
                child: Text(
                  '${_sliderAngle.round()}°',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _waitingForConfirmation
                        ? Colors.blue
                        : const Color(0xFF3F51B5),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Angle slider - disabled during confirmation wait
              Row(
                children: [
                  const Text('0°',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _sliderAngle,
                      min: 0,
                      max: 90,
                      divisions: 90,
                      activeColor: _waitingForConfirmation
                          ? Colors.grey
                          : const Color(0xFF3F51B5),
                      inactiveColor: Colors.grey[300],
                      label: '${_sliderAngle.round()}°',
                      // Disable slider while waiting for confirmation
                      onChanged: _waitingForConfirmation
                          ? null
                          : (value) {
                              setState(() => _sliderAngle = value);
                            },
                      onChangeStart: _waitingForConfirmation
                          ? null
                          : (_) {
                              // User started dragging - stop WebSocket from
                              // overwriting slider value
                              _userIsEditingAngle = true;
                              _angleEditDebounce?.cancel();
                            },
                      onChangeEnd: _waitingForConfirmation
                          ? null
                          : (_) {
                              // User stopped dragging - keep editing flag
                              // for 3 seconds so WebSocket doesn't snap it
                              // back before user taps "Set Angle"
                              _angleEditDebounce?.cancel();
                              _angleEditDebounce = Timer(
                                const Duration(seconds: 3),
                                () {
                                  if (mounted) {
                                    setState(
                                        () => _userIsEditingAngle = false);
                                  }
                                },
                              );
                            },
                    ),
                  ),
                  const Text('90°',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),

              const SizedBox(height: 8),

              // Set angle button - disabled during confirmation wait
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_isAngleUpdating || _waitingForConfirmation)
                      ? null
                      : () {
                          // Cancel the debounce so editing flag resets
                          _angleEditDebounce?.cancel();
                          _userIsEditingAngle = false;
                          _sendAngleCommand(_sliderAngle.round());
                        },
                  icon: (_isAngleUpdating || _waitingForConfirmation)
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send),
                  label: Text(_waitingForConfirmation
                      ? 'Waiting... ${_confirmationCountdown}s'
                      : _isAngleUpdating
                          ? 'Sending...'
                          : 'Set Angle to ${_sliderAngle.round()}°'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        const Color(0xFF3F51B5).withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Actual position info
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Actual position',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    Text(
                      '$actualPos°',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: actualPos >= 45
                            ? Colors.green[700]
                            : Colors.red[700],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SCHEDULE CARD (Working version)
  // ============================================================
  Widget _buildScheduleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Schedule',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Text(
                  '${_schedules.length} entries',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Table Header: Day | Open | Close
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Expanded(
                      flex: 3,
                      child: Center(
                          child: Text('Day',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(
                      flex: 2,
                      child: Center(
                          child: Text('Open',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)))),
                  Expanded(
                      flex: 2,
                      child: Center(
                          child: Text('Close',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)))),
                  SizedBox(width: 40), // Space for delete button
                ],
              ),
            ),

            // Schedule Rows
            if (_schedules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No schedules added yet.\nTap + to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ),
              )
            else
              ..._schedules.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return _buildScheduleRowInteractive(
                  i,
                  s['day'] ?? '',
                  s['open'] ?? '',
                  s['close'] ?? '',
                );
              }),

            const SizedBox(height: 12),

            // Add Schedule Button
            Center(
              child: TextButton.icon(
                onPressed: () => _showAddScheduleDialog(),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Add Schedule'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF3F51B5),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingSchedule ? null : _saveSchedule,
                icon: _isSavingSchedule
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save),
                label:
                    Text(_isSavingSchedule ? 'Saving...' : 'Save Schedule'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF3F51B5).withOpacity(0.6),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleRowInteractive(
      int index, String day, String openTime, String closeTime) {
    return InkWell(
      onTap: () => _showAddScheduleDialog(editIndex: index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  day,
                  style: const TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  openTime,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.green[700]),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Center(
                child: Text(
                  closeTime,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.red[700]),
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red[300],
                onPressed: () => _deleteSchedule(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SENSOR CARD (placeholder - unchanged)
  // ============================================================
  Widget _buildSensorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Sensor Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  '+ Add sensor',
                  style: TextStyle(color: Color(0xFF3F51B5)),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Upper limit')),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '80',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(flex: 2, child: Text('Lower limit')),
                Expanded(
                  flex: 3,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: '60',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Sensor settings saved!')),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text('save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F51B5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WIFI BUTTON
  // ============================================================
  Widget _buildWifiButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const WifiSetupScreen()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text('Change WiFi Connection'),
      ),
    );
  }

  // ============================================================
  // EDIT NAME DIALOG
  // ============================================================
  void _showEditNameDialog() {
    final controller = TextEditingController(
        text: _device['vwv_name'] ?? _device['device_name']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _device['vwv_name'] = controller.text;
                _device['device_name'] = controller.text;
              });
              Navigator.pop(context);
              // TODO: Save name to backend
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}