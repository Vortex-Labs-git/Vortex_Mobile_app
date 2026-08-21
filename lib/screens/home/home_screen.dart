import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/device_repository.dart';
import '../../controllers/esp_session.dart';
import '../../controllers/network_watcher.dart';
import '../../models/device.dart';
import '../../theme/glass_theme.dart';
import '../device_detail/device_detail_screen.dart';
import '../device_detail/sensor_detail_screen.dart';
import 'widgets/connection_status_bar.dart';
import 'widgets/device_card.dart';
import 'widgets/empty_view.dart';
import 'widgets/error_view.dart';

// =============================================================================
// HOME SCREEN  (view only)
// =============================================================================
// Renders the device list. ALL logic lives in the app-lifetime controllers
// (started once in main.dart, in this order):
//
//   NetworkWatcher    → permission / SSID / Vortex AP detect / resume loop
//   EspSession        → direct-connect policy, auth, zombie-socket handling
//   DeviceRepository  → server + cache + ESP overlay → one snapshot stream
//
// This widget only: subscribes, setState-mirrors the snapshots, shows the
// session snackbar, and navigates. It owns no timers, no lifecycle observer,
// no WiFi code, and no ESP streams — do not add logic back here.
//
// Debug terminal: removed from this screen. The controllers each expose a
// logStream; a future standalone debug screen can merge those, use
// EspSession.instance.passkey / connect(overrideIp:, overridePort:) for the
// old panel's inputs, and call EspDirectService directly for the test
// buttons — nothing was lost, it just no longer lives in the view.
// =============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Mirrored controller snapshots — the only state this screen holds.
  DeviceRepositoryState _repo = DeviceRepository.instance.current;
  NetworkState _network = NetworkWatcher.instance.current;

  StreamSubscription<DeviceRepositoryState>? _repoSub;
  StreamSubscription<NetworkState>? _networkSub;
  StreamSubscription<EspSessionState>? _activationSub;

  @override
  void initState() {
    super.initState();

    _repoSub = DeviceRepository.instance.stateStream.listen((s) {
      if (mounted) setState(() => _repo = s);
    });

    _networkSub = NetworkWatcher.instance.stateStream.listen((s) {
      if (mounted) setState(() => _network = s);
    });

    // One event per established direct session → legacy ✅ / ⚠️ snackbar.
    _activationSub = EspSession.instance.activationStream.listen((s) {
      if (!mounted || s.deviceId == null) return;
      _showSnackBar(s.isUserDevice
          ? '✅ Connected to your device: ${s.deviceId}'
          : '⚠️ This device (${s.deviceId}) is not assigned to your account');
    });
  }

  @override
  void dispose() {
    _repoSub?.cancel();
    _networkSub?.cancel();
    _activationSub?.cancel();
    super.dispose();
  }

  // -- Helpers --

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    }
  }

  /// Colors stay in the view layer — the model is pure Dart on purpose.
  Color _statusColor(DeviceStatus status) {
    switch (status) {
      case DeviceStatus.online:
      case DeviceStatus.espConnected:
        return GlassTokens.success;
      case DeviceStatus.offline:
        return GlassTokens.danger;
    }
  }

  void _onDeviceTap(Device device) {
    switch (device.status) {
      case DeviceStatus.espConnected:
        // Direct ESP32 mode (valve: manual control only; sensor: read-only).
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => device.isSensor
                ? SensorDetailScreen(deviceData: device.raw, isDirectMode: true)
                : DeviceDetailScreen(deviceData: device.raw, isDirectMode: true),
          ),
        );
        break;
      case DeviceStatus.online:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => device.isSensor
                ? SensorDetailScreen(deviceData: device.raw)
                : DeviceDetailScreen(deviceData: device.raw),
          ),
        );
        break;
      case DeviceStatus.offline:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => device.isSensor
                ? SensorDetailScreen(deviceData: device.raw)
                : DeviceDetailScreen(deviceData: device.raw),
          ),
        );
        break;
    }
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    // No Scaffold and no background: this is a tab inside MainScreen's
    // GlassScaffold, and the gradient backdrop has to show through.
    if (_repo.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Loading devices...',
              style: TextStyle(color: GlassTokens.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_repo.errorMessage != null && _repo.devices.isEmpty) {
      return ErrorView(
        message: _repo.errorMessage!,
        onRetry: () => DeviceRepository.instance.retry(),
      );
    }

    if (_repo.devices.isEmpty) return const EmptyView();

    return _buildDeviceList();
  }

  Widget _buildDeviceList() {
    // With extendBody on the shell Scaffold, the bottom inset already covers
    // the translucent nav bar — add it so the last card clears the bar while
    // the list still scrolls underneath it.
    final double bottomInset = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        ConnectionStatusBar(
          wsConnected: _repo.wsConnected,
          isEspApMode: _network.isVortexAp,
          connectedSsid: _network.ssid,
        ),
        Expanded(
          child: RefreshIndicator(
            color: GlassTokens.primary,
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            onRefresh: () async {
              // WiFi half first (may trigger EspSession via the watcher),
              // then the server half.
              await NetworkWatcher.instance.checkNow();
              await DeviceRepository.instance.refresh();
            },
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset),
              itemCount: _repo.devices.length,
              itemBuilder: (context, index) {
                final device = _repo.devices[index];
                return DeviceCard(
                  device: device.raw,
                  statusText: device.status.label,
                  statusColor: _statusColor(device.status),
                  isEspConnected:
                      device.status == DeviceStatus.espConnected,
                  onTap: () => _onDeviceTap(device),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
