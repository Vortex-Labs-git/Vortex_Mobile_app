import 'package:flutter/material.dart';
import 'dart:async';
import '../services/esp_direct_service.dart';
import '../services/auth_service.dart';

/// WiFi Setup Screen for ESP32 Direct Communication
/// Message structure follows Vortex_WiFi_Valve_Software_Architecture.pdf
/// Section: Mobile App And ESP32 Communication (WebSocket)
class WifiSetupScreen extends StatefulWidget {
  final Map<String, dynamic>? deviceData; // Optional: pass device info from home screen
  
  const WifiSetupScreen({super.key, this.deviceData});

  @override
  State<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends State<WifiSetupScreen> {
  final EspDirectService _espService = EspDirectService.instance;
  
  bool _isConnecting = false;
  bool _isConnectedToEsp = false;
  bool _isScanning = false;
  bool _isSavingWifi = false;
  
  Map<String, dynamic>? _deviceInfo;
  Map<String, dynamic>? _valveData;
  List<Map<String, dynamic>> _wifiNetworks = [];
  String? _errorMessage;
  
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  
  // Stream subscriptions
  StreamSubscription? _connectionSub;
  StreamSubscription? _deviceInfoSub;
  StreamSubscription? _valveDataSub;
  StreamSubscription? _wifiScanSub;
  StreamSubscription? _wifiSavedSub;
  StreamSubscription? _errorSub;

  @override
  void initState() {
    super.initState();
    _setupListeners();
  }

  @override
  void dispose() {
    _connectionSub?.cancel();
    _deviceInfoSub?.cancel();
    _valveDataSub?.cancel();
    _wifiScanSub?.cancel();
    _wifiSavedSub?.cancel();
    _errorSub?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _setupListeners() {
    // Connection state changes
    _connectionSub = _espService.connectionStream.listen((connected) {
      if (mounted) {
        setState(() => _isConnectedToEsp = connected);
        if (connected) {
          // Request device info when connected
          _requestDeviceInfo();
        }
      }
    });

    // Device info response (Doc Page 10)
    _deviceInfoSub = _espService.deviceInfoStream.listen((data) {
      if (!mounted) return;
      print('📱 Device Info received: $data');
      setState(() {
        _deviceInfo = data;
        _errorMessage = null;
      });
      
      // After getting device info, request valve data
      if (data['device_id'] != null) {
        _requestValveData(data['device_id']);
      }
    });

    // Valve data response (Doc Page 11)
    _valveDataSub = _espService.valveDataStream.listen((data) {
      if (!mounted) return;
      print('📱 Valve Data received: $data');
      setState(() => _valveData = data);
    });

    // WiFi scan results
    _wifiScanSub = _espService.wifiScanStream.listen((networks) {
      if (mounted) {
        setState(() {
          _wifiNetworks = networks;
          _isScanning = false;
        });
      }
    });

    // WiFi saved confirmation
    _wifiSavedSub = _espService.wifiSavedStream.listen((data) {
      if (!mounted) return;
      _showSnackBar('✅ ${data['message'] ?? 'WiFi credentials saved!'}');
      setState(() => _isSavingWifi = false);
    });

    // Error messages
    _errorSub = _espService.errorStream.listen((data) {
      if (!mounted) return;
      setState(() => _errorMessage = data['message'] ?? 'Unknown error');
      _showSnackBar('❌ ${data['message'] ?? 'Error occurred'}');
    });
  }

  /// Request device info from ESP32
  /// Doc Page 10: request_device_info message
  void _requestDeviceInfo() {
    final user = AuthService.currentUser;
    final userId = user?['id']?.toString() ?? 'app_user';
    
    _espService.requestDeviceInfo(
      userId: userId,
      passkey: '', // Optional passkey
    );
  }

  /// Request valve data from ESP32
  /// Doc Page 11: device_basic_info message
  void _requestValveData(String deviceId) {
    final user = AuthService.currentUser;
    final userId = user?['id']?.toString() ?? 'app_user';
    
    _espService.requestValveData(
      userId: userId,
      deviceId: deviceId,
      deviceName: _deviceInfo?['device_name'] ?? 'Unknown',
    );
  }

  Future<void> _connectToEsp() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
    });
    
    final success = await _espService.connect();
    
    if (mounted) {
      setState(() => _isConnecting = false);
      if (success) {
        _showSnackBar('✅ Connected to ESP32!');
      } else {
        setState(() => _errorMessage = 'Connection failed');
        _showSnackBar('❌ Connection failed. Make sure you are connected to valve WiFi.');
      }
    }
  }

  void _scanWifiNetworks() {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });
    
    _espService.scanWifiNetworks();
    
    // Timeout after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (_isScanning && mounted) {
        setState(() {
          _isScanning = false;
          if (_wifiNetworks.isEmpty) {
            _errorMessage = 'No networks found. Try again.';
          }
        });
      }
    });
  }

  /// Save WiFi credentials to ESP32
  /// Doc Page 13: set_valve_wifi message
  void _saveWifiCredentials() {
    final ssid = _ssidController.text.trim();
    final password = _passwordController.text;
    
    if (ssid.isEmpty) {
      _showSnackBar('Please enter WiFi network name');
      return;
    }
    
    final deviceId = _deviceInfo?['device_id'] ?? _espService.connectedDeviceId;
    if (deviceId == null) {
      _showSnackBar('❌ Device ID not available. Please reconnect.');
      return;
    }
    
    setState(() {
      _isSavingWifi = true;
      _errorMessage = null;
    });
    
    _espService.setWifiCredentials(
      deviceId: deviceId,
      ssid: ssid,
      password: password,
    );
    
    // Timeout after 15 seconds
    Future.delayed(const Duration(seconds: 15), () {
      if (_isSavingWifi && mounted) {
        setState(() => _isSavingWifi = false);
        _showSnackBar('WiFi configuration sent. Device may restart.');
      }
    });
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WiFi Setup'),
        backgroundColor: const Color(0xFF3F51B5),
        foregroundColor: Colors.white,
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Icon(
              _isConnectedToEsp ? Icons.wifi : Icons.wifi_off,
              color: _isConnectedToEsp ? Colors.greenAccent : Colors.red,
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error banner
            if (_errorMessage != null) _buildErrorBanner(),
            
            // Step 1: Connect to valve WiFi
            _buildStep1Card(),
            const SizedBox(height: 16),
            
            // Step 2: Connect to valve via WebSocket
            _buildStep2Card(),
            const SizedBox(height: 16),
            
            // Step 3: Configure home WiFi (only when connected)
            if (_isConnectedToEsp) _buildStep3Card(),
            
            // Device info card (only when we have data)
            if (_deviceInfo != null) ...[
              const SizedBox(height: 16),
              _buildDeviceInfoCard(),
            ],
            
            // Valve data card (only when we have data)
            if (_valveData != null) ...[
              const SizedBox(height: 16),
              _buildValveDataCard(),
            ],
            
            // Debug info (development only)
            const SizedBox(height: 24),
            _buildDebugCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _errorMessage = null),
            color: Colors.red.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildStep1Card() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHeader(1, 'Connect to Valve WiFi'),
            const SizedBox(height: 16),
            const Text('Go to your phone\'s WiFi settings and connect to:'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi, color: Color(0xFF3F51B5), size: 32),
                  SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VortexValve_XXX',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      Text('Password: vortex1234', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The valve creates a WiFi hotspot when in AP mode. '
              'Connect to it first, then tap "Connect to Valve" below.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2Card() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHeader(2, 'Connect to Valve'),
            const SizedBox(height: 16),
            if (_isConnectedToEsp)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connected to ${_deviceInfo?['device_name'] ?? 'ESP32'}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_deviceInfo?['device_id'] != null)
                            Text(
                              'ID: ${_deviceInfo!['device_id']}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _espService.disconnect();
                        setState(() {
                          _deviceInfo = null;
                          _valveData = null;
                        });
                      },
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isConnecting ? null : _connectToEsp,
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.link),
                  label: Text(_isConnecting ? 'Connecting...' : 'Connect to Valve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3F51B5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep3Card() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStepHeader(3, 'Configure Home WiFi'),
            const SizedBox(height: 8),
            Text(
              'Configure the WiFi network the valve should connect to for normal operation.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            const SizedBox(height: 16),
            
            // Scan Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isScanning ? null : _scanWifiNetworks,
                icon: _isScanning
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(_isScanning ? 'Scanning...' : 'Scan for Networks'),
              ),
            ),
            
            // WiFi List
            if (_wifiNetworks.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('Available Networks:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _wifiNetworks.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final network = _wifiNetworks[index];
                    final isSelected = _ssidController.text == network['ssid'];
                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: Colors.blue.shade50,
                      leading: Icon(
                        _getSignalIcon(network['rssi'] ?? -100),
                        color: _getSignalColor(network['rssi'] ?? -100),
                      ),
                      title: Text(network['ssid'] ?? 'Unknown'),
                      trailing: (network['secure'] ?? true)
                          ? const Icon(Icons.lock, size: 16, color: Colors.grey)
                          : const Icon(Icons.lock_open, size: 16, color: Colors.orange),
                      onTap: () => setState(() => _ssidController.text = network['ssid']),
                    );
                  },
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // SSID Field
            TextField(
              controller: _ssidController,
              decoration: const InputDecoration(
                labelText: 'WiFi Network Name (SSID)',
                hintText: 'Enter or select from list above',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.wifi),
              ),
            ),
            const SizedBox(height: 12),
            
            // Password Field
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'WiFi Password',
                hintText: 'Enter WiFi password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSavingWifi ? null : _saveWifiCredentials,
                icon: _isSavingWifi
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save),
                label: Text(_isSavingWifi ? 'Saving...' : 'Save & Connect'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            Text(
              'After saving, the device will restart and connect to your home WiFi.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfoCard() {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Color(0xFF3F51B5)),
                const SizedBox(width: 8),
                const Text(
                  'Device Information',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            _infoRow('Device ID', _deviceInfo?['device_id']),
            _infoRow('Device Name', _deviceInfo?['device_name']),
            _infoRow('Mode', _deviceInfo?['is_ap_mode'] == true ? 'AP Mode (Setup)' : 'Station Mode'),
            _infoRow('IP Address', _deviceInfo?['ip_address']),
            if (_deviceInfo?['timestamp'] != null)
              _infoRow('Last Update', _deviceInfo!['timestamp']),
          ],
        ),
      ),
    );
  }

  Widget _buildValveDataCard() {
    final controller = _valveData?['get_controller'] ?? {};
    final valveData = _valveData?['get_valvedata'] ?? {};
    final limitData = _valveData?['get_limitdata'] ?? {};
    
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'Valve Status',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
            const Divider(),
            _infoRow('Angle', '${valveData['angle'] ?? 0}°'),
            _infoRow('State', valveData['is_open'] == true ? 'Open' : 'Closed'),
            _infoRow('Schedule', controller['schedule'] == true ? 'Enabled' : 'Disabled'),
            _infoRow('Sensor', controller['sensor'] == true ? 'Enabled' : 'Disabled'),
            if (_valveData?['Error']?.isNotEmpty == true)
              _infoRow('Error', _valveData!['Error'], isError: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDebugCard() {
    return ExpansionTile(
      title: const Text('Debug Info', style: TextStyle(fontSize: 14)),
      leading: const Icon(Icons.bug_report, size: 20),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        Text(
          'Connection: ${_isConnectedToEsp ? "Connected" : "Disconnected"}\n'
          'Device ID: ${_espService.connectedDeviceId ?? "N/A"}\n'
          'Device IP: ${_espService.connectedDeviceIp ?? "N/A"}\n'
          'Networks found: ${_wifiNetworks.length}\n'
          'Mock server: ws://192.168.137.1:9090',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildStepHeader(int step, String title) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF3F51B5),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _infoRow(String label, String? value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: isError ? Colors.red : Colors.grey)),
          Text(
            value ?? 'N/A',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isError ? Colors.red : null,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSignalIcon(int rssi) {
    if (rssi > -50) return Icons.signal_wifi_4_bar;
    if (rssi > -60) return Icons.network_wifi_3_bar;
    if (rssi > -70) return Icons.network_wifi_2_bar;
    return Icons.network_wifi_1_bar;
  }

  Color _getSignalColor(int rssi) {
    if (rssi > -50) return Colors.green;
    if (rssi > -60) return Colors.lightGreen;
    if (rssi > -70) return Colors.orange;
    return Colors.red;
  }
}