import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/websocket_service.dart';

class ManualControlScreen extends StatefulWidget {
  final Map<String, dynamic> deviceData;

  const ManualControlScreen({super.key, required this.deviceData});

  @override
  State<ManualControlScreen> createState() => _ManualControlScreenState();
}

class _ManualControlScreenState extends State<ManualControlScreen> {
  late Map<String, dynamic> _device;
  bool _isUpdating = false;
  bool _wsConnected = false;

  // Stream subscriptions
  StreamSubscription<Map<String, dynamic>>? _detailSub;
  StreamSubscription<bool>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _device = Map<String, dynamic>.from(widget.deviceData);
    _setupWebSocket();
  }

  @override
  void dispose() {
    _detailSub?.cancel();
    _connectionSub?.cancel();

    // Switch back to device_list when leaving this screen
    WebSocketService.subscribeTo('device_list');
    super.dispose();
  }

  void _setupWebSocket() {
    _wsConnected = WebSocketService.isConnected;

    // Listen to connection changes
    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) setState(() => _wsConnected = connected);
    });

    // Listen to device detail updates
    _detailSub = WebSocketService.deviceDetailStream.listen((data) {
      if (mounted && data['id']?.toString() == _device['id']?.toString()) {
        setState(() {
          // Update angle/position from server
          final pos = data['user_vwv_pos'];
          if (pos != null) {
            int angle = int.tryParse(pos.toString()) ?? 0;
            _device['status'] = (angle >= 45) ? 'Open' : 'Closed';
            _device['user_vwv_pos'] = pos;
          }
          // Update other fields if available
          _device['vwv_name'] = data['vwv_name'] ?? _device['vwv_name'];
        });
        print("🎛️ ManualControl: UI updated from WebSocket");
      }
    });

    // Subscribe to this device's detail
    WebSocketService.subscribeTo('device_detail', deviceId: _device['id']?.toString());
  }

  // ============================================================
  // HTTP Control Command (sends valve open/close)
  // ============================================================
  Future<void> _sendControlCommand(String command) async {
    setState(() => _isUpdating = true);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    int targetAngle = (command == "Open") ? 90 : 0;

    try {
      final response = await http.post(
        Uri.parse('https://vortexlabsofficial.com/vortex_app/control_device.php'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'event': 'set_valve_basic',
          'device_id': _device['id'],
          'valve_data': {
            'name': _device['vwv_name'],
            'set_angle': true,
            'angle': targetAngle,
          }
        }),
      );

      print("Control Response: ${response.body}");

      final result = jsonDecode(response.body);
      if (result['success'] == true) {
        if (mounted) {
          setState(() => _device['status'] = command);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Success: Valve set to $targetAngle°')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Server Error: ${result['message']}')),
          );
        }
      }
    } catch (e) {
      print("Control Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  // ============================================================
  // UI
  // ============================================================
  @override
  Widget build(BuildContext context) {
    bool isOpen = _device['status'] == 'Open' || _device['status'] == '90';

    return Scaffold(
      appBar: AppBar(
        title: Text(_device['vwv_name'] ?? _device['device_name'] ?? 'Manual Control'),
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
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Connection Warning
            if (!_wsConnected)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Flexible(
                      child: Text("Live updates disconnected",
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),

            // BIG STATUS ICON
            Container(
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: isOpen ? Colors.green.shade50 : Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isOpen ? Icons.lock_open : Icons.lock_outline,
                size: 100,
                color: isOpen ? Colors.green : Colors.red,
              ),
            ),

            const SizedBox(height: 24),

            // STATUS TEXT
            Text(
              isOpen ? "OPEN" : "CLOSED",
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: isOpen ? Colors.green[700] : Colors.red[700],
              ),
            ),

            const SizedBox(height: 8),

            // Device name
            Text(
              _device['vwv_name'] ?? 'Unknown Device',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),

            const SizedBox(height: 60),

            // CONTROL BUTTONS
            if (_isUpdating)
              const CircularProgressIndicator()
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    // OPEN BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        onPressed: isOpen ? null : () => _sendControlCommand("Open"),
                        icon: const Icon(Icons.lock_open, size: 28),
                        label: const Text(
                          "OPEN VALVE",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.green.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // CLOSE BUTTON
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton.icon(
                        onPressed: !isOpen ? null : () => _sendControlCommand("Closed"),
                        icon: const Icon(Icons.lock, size: 28),
                        label: const Text(
                          "CLOSE VALVE",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.red.shade200,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
