import 'package:flutter/material.dart';
import 'dart:async';
import '../services/auth_service.dart';
import '../services/websocket_service.dart';
import 'device_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State
  List<dynamic> _devices = [];
  bool _isLoading = true;
  bool _wsConnected = false;
  String? _errorMessage;

  // Stream subscriptions
  StreamSubscription<List<dynamic>>? _deviceListSub;
  StreamSubscription<bool>? _connectionSub;

  @override
  void initState() {
    super.initState();
    _setupWebSocket();
  }

  @override
  void dispose() {
    _deviceListSub?.cancel();
    _connectionSub?.cancel();
    super.dispose();
  }

  void _setupWebSocket() {
    // Listen to connection status
    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() => _wsConnected = connected);
      }
    });

    // Listen to device list updates (pushed every 2 seconds by server)
    _deviceListSub = WebSocketService.deviceListStream.listen((devices) {
      if (mounted) {
        setState(() {
          _devices = devices;
          _isLoading = false;
          _errorMessage = null;
        });
        print("🏠 HomeScreen: Received ${devices.length} devices via WebSocket");
      }
    });

    // Subscribe to device_list
    _wsConnected = WebSocketService.isConnected;

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
    } else {
      // If not yet connected, wait and try
      _waitForConnection();
    }
  }

  void _waitForConnection() async {
    // Give WebSocket time to connect (it was triggered by auth_service)
    await Future.delayed(const Duration(seconds: 2));

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
    } else {
      // Try connecting again
      final connected = await WebSocketService.connect();
      if (connected) {
        WebSocketService.subscribeTo('device_list');
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = "Unable to connect to live server";
          });
        }
      }
    }
  }

  // ============================================================
  // Check if device is online based on vwv_last_seen
  // If the time gap between now and vwv_last_seen > 5 seconds → offline
  // ============================================================
  bool _isDeviceOnline(String? lastSeen) {
    if (lastSeen == null || lastSeen.isEmpty || lastSeen == 'NULL') {
      return false;
    }

    try {
      final lastSeenTime = DateTime.parse(lastSeen);
      final now = DateTime.now();
      final difference = now.difference(lastSeenTime).inSeconds;
      return difference <= 30;
    } catch (e) {
      print("⚠️ Error parsing vwv_last_seen: $e");
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Connecting to live server...",
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off, size: 60, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(_errorMessage!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _errorMessage = null;
                          });
                          _waitForConnection();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retry"),
                      ),
                    ],
                  ),
                )
              : _devices.isEmpty
                  ? const Center(child: Text("No devices found"))
                  : Column(
                      children: [
                        // Connection status bar
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              vertical: 4, horizontal: 16),
                          color: _wsConnected ? Colors.green : Colors.orange,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _wsConnected ? Icons.wifi : Icons.wifi_off,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _wsConnected
                                    ? "Live updates active"
                                    : "Live updates disconnected",
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        // Device list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _devices.length,
                            itemBuilder: (context, index) {
                              final device = _devices[index];
                              bool isOnline = _isDeviceOnline(device['vwv_last_seen']);
                              final statusColor =
                                  isOnline ? Colors.green : Colors.red;

                              return Card(
                                elevation: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            DeviceDetailScreen(
                                          deviceData: device,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      color: Colors.grey[200],
                                    ),
                                    child: Row(
                                      children: [
                                        // Device Icon
                                        Container(
                                          width: 80,
                                          height: 80,
                                          margin: const EdgeInsets.all(12),
                                          decoration: const BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.settings_remote,
                                                size: 40,
                                                color: Colors.indigo),
                                          ),
                                        ),
                                        // Device Details
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                device['vwv_name'] ??
                                                    device['device_name'] ??
                                                    'Unknown Device',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                              Text(
                                                "ID: ${device['id']}",
                                                style: TextStyle(
                                                    color: Colors.grey[700],
                                                    fontSize: 12),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                isOnline
                                                    ? "Online"
                                                    : "Offline",
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    color: statusColor),
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Status Bar Color
                                        Container(
                                          width: 12,
                                          height: 104,
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            borderRadius:
                                                const BorderRadius.only(
                                              topRight: Radius.circular(12),
                                              bottomRight: Radius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}