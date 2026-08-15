import 'dart:async';

import '../models/device.dart';
import '../services/local_storage_service.dart';
import '../services/websocket_service.dart';
import 'esp_session.dart';
import 'network_watcher.dart';

// =============================================================================
// DEVICE REPOSITORY  (controller — single source of truth for the home list)
// =============================================================================
// App-lifetime singleton that owns the device list. Three inputs, one output:
//
//   WebSocketService.deviceListStream ─┐  (server truth, cached verbatim)
//   LocalStorageService.getDeviceList ─┤─▶ _baseDevices ─▶ overlay ─▶ emit
//   EspSession.stateStream ────────────┘  (session-only _esp flags)
//
//   NetworkWatcher.stateStream ───────────▶ server reconnect nudge only
//
// THE OVERLAY — and the flag-wipe bug it fixes:
//   Legacy home_screen mutated _esp_connected flags INTO the list entries,
//   so every server push replaced the list wholesale and silently wiped the
//   green "Direct Connected" state until the next device_info (which may
//   never re-fire). Here the base list NEVER carries flags; the session's
//   (deviceId, isUserDevice) is kept separately and re-applied via
//   Device.copyWith on every emission — server pushes can no longer erase
//   direct-mode state.
//
// CACHING RULE (see models/device.dart header):
//   The raw server payload is cached verbatim — never re-serialized Device
//   objects — so the cache format stays byte-identical to legacy and the
//   session-only flags can never leak into persistence.
//
// ALSO OWNS (moved from home_screen):
//   - Initial load: cache first so the UI isn't blank (legacy Step 4.1)
//   - Server subscription bring-up: subscribe now, or wait 3 s → retry once
//     → offline fallback (legacy Section 5)
//   - "Normal WiFi + server down → nudge reconnect" (legacy Step 6.4),
//     driven by NetworkWatcher emissions. Skipped on Vortex AP and on
//     permission-denied states, matching legacy's early returns.
//
// LEGACY BUGS FIXED (flag for tech-lead review):
//   1. Flag wipe on server push (above).
//   2. ErrorView retry re-ran _initialize(), re-attaching every stream
//      listener each time (duplicate-subscription leak). retry() here
//      re-runs only the data bring-up.
//   3. Cache load can no longer clobber fresher server data: it only seeds
//      an empty base list.
//   4. First-login gap: the repository now subscribes to 'device_list' on
//      every connect event, because the post-login MainScreen rebuild no
//      longer re-runs the subscription (see the connection listener).
//
// SUBSCRIBER CONTRACT (step 5):
//   HomeScreen listens to stateStream and renders the snapshot 1:1
//   (isLoading → spinner, errorMessage → ErrorView, empty → EmptyView,
//   devices → list). Navigation passes device.raw to detail screens.
//   Pull-to-refresh: await NetworkWatcher.checkNow(manual) then refresh().
//
// START ORDER: start() this (and EspSession) BEFORE NetworkWatcher.start().
// =============================================================================

/// Immutable snapshot of everything the home screen needs to render.
class DeviceRepositoryState {
  /// Base list with the ESP overlay already applied. Never mutate entries.
  final List<Device> devices;

  /// True until the first data arrives (cache or server) or bring-up gives
  /// up and falls back to offline.
  final bool isLoading;

  /// Live server WebSocket status (ConnectionStatusBar).
  final bool wsConnected;

  /// True while showing cached data / no server path (legacy _isOfflineMode).
  final bool isOffline;

  /// Set only for the "no server AND no cache" dead end (ErrorView).
  final String? errorMessage;

  const DeviceRepositoryState({
    required this.devices,
    required this.isLoading,
    required this.wsConnected,
    required this.isOffline,
    required this.errorMessage,
  });

  const DeviceRepositoryState.initial()
      : devices = const [],
        isLoading = true,
        wsConnected = false,
        isOffline = false,
        errorMessage = null;

  @override
  String toString() =>
      'DeviceRepositoryState(${devices.length} devices, loading: $isLoading, '
      'ws: $wsConnected, offline: $isOffline'
      '${errorMessage != null ? ', error' : ''})';
}

class DeviceRepository {
  // -- Singleton (same lazy pattern as EspDirectService) --
  static DeviceRepository? _instance;
  static DeviceRepository get instance => _instance ??= DeviceRepository._();
  DeviceRepository._();

  // -- Tuning (legacy magic numbers, now named) --
  static const Duration serverWaitDelay = Duration(seconds: 3);
  static const String noConnectionMessage =
      'No server connection and no cached devices.\n'
      'Please connect to the internet and login first.';

  // -- Internals --
  final StreamController<DeviceRepositoryState> _stateController =
      StreamController<DeviceRepositoryState>.broadcast();
  final StreamController<String> _logController =
      StreamController<String>.broadcast();

  /// Server/cache truth. NEVER carries ESP flags (see header).
  List<Device> _baseDevices = [];

  /// The session overlay, mirrored from EspSession.
  String? _espDeviceId;
  bool _espIsUserDevice = false;

  bool _isLoading = true;
  bool _wsConnected = false;
  bool _isOffline = false;
  String? _errorMessage;

  DeviceRepositoryState _current = const DeviceRepositoryState.initial();
  bool _started = false;

  StreamSubscription<List<dynamic>>? _deviceListSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<EspSessionState>? _sessionSub;
  StreamSubscription<NetworkState>? _networkSub;

  // -- Public surface --

  /// Every snapshot, in order. Late subscribers read [current] first.
  Stream<DeviceRepositoryState> get stateStream => _stateController.stream;

  /// Debug-terminal log lines (legacy _log texts preserved).
  Stream<String> get logStream => _logController.stream;

  DeviceRepositoryState get current => _current;

  Device? deviceById(String id) {
    for (final d in _current.devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// Call once at app start, BEFORE NetworkWatcher.start(). Idempotent.
  /// Legacy _initialize steps 4.1–4.2 plus the merge subscriptions.
  Future<void> start() async {
    if (_started) return;
    _started = true;

    // ESP overlay: react to session changes, and seed from the current
    // session state for start-order resilience.
    _sessionSub = EspSession.instance.stateStream.listen((s) {
      _applySession(s);
      _emit();
    });
    _applySession(EspSession.instance.current);

    // Server reconnect nudge (legacy Step 6.4).
    _networkSub =
        NetworkWatcher.instance.stateStream.listen(_onNetworkState);

    // 4.1  Cache first so the UI isn't blank. Loaded BEFORE the server
    //      listeners attach (legacy order) and guarded so it can only seed
    //      an empty base — never clobber fresher server data.
    final cached = await LocalStorageService.getDeviceList();
    if (cached.isNotEmpty && _baseDevices.isEmpty) {
      _baseDevices = Device.listFromJson(cached);
      _isLoading = false;
      _isOffline = true;
      _log('Loaded ${cached.length} cached devices');
      _emit();
    } else if (cached.isEmpty) {
      _log('No cached devices found');
    }

    // 4.2 / Section 5  Server WebSocket listeners + bring-up.
    _connectionSub = WebSocketService.connectionStream.listen((connected) {
      _wsConnected = connected;
      if (connected) {
        _isOffline = false;
        // NEW vs legacy — closes the first-login gap: AuthService connects
        // the socket after login, and legacy relied on the post-login
        // MainScreen rebuild re-running HomeScreen._initialize() to
        // subscribe. That rebuild no longer subscribes, so the repository
        // does it on every connect. WebSocketService also self-resubscribes
        // on its internal reconnects, so this can repeat — subscribe is a
        // set operation on the Ratchet side, and repeating it is harmless
        // (confirm idempotency with the tech lead).
        WebSocketService.subscribeTo('device_list');
      }
      _log('Server WS: ${connected ? 'CONNECTED' : 'DISCONNECTED'}');
      _emit();
    });

    _deviceListSub = WebSocketService.deviceListStream.listen((devices) {
      _baseDevices = Device.listFromJson(devices);
      _isLoading = false;
      _isOffline = false;
      _errorMessage = null;
      _log('Server WS: Received ${devices.length} devices');
      // Cache the RAW payload verbatim — never re-serialized Devices.
      LocalStorageService.saveDeviceList(devices);
      _emit();
    });

    _wsConnected = WebSocketService.isConnected;

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
      _isOffline = false;
      _log('Server WS: Already connected, subscribed to device_list');
      _emit();
    } else {
      _log('Server WS: Not connected, waiting...');
      _waitForConnection();
    }
  }

  /// Normally never called — app-lifetime object. For completeness/tests.
  void stop() {
    if (!_started) return;
    _started = false;
    _deviceListSub?.cancel();
    _connectionSub?.cancel();
    _sessionSub?.cancel();
    _networkSub?.cancel();
  }

  /// Pull-to-refresh server half (the WiFi half is
  /// NetworkWatcher.checkNow(manual), called by the screen first).
  /// Legacy onRefresh body, minus the wifi check.
  Future<void> refresh() async {
    if (!WebSocketService.isConnected) {
      final connected = await WebSocketService.connect();
      if (connected) {
        WebSocketService.subscribeTo('device_list');
      }
    }
  }

  /// ErrorView retry. Unlike legacy (which re-ran _initialize and leaked
  /// duplicate listeners), this re-runs only the data bring-up.
  Future<void> retry() async {
    _isLoading = true;
    _errorMessage = null;
    _emit();

    if (_baseDevices.isEmpty) {
      final cached = await LocalStorageService.getDeviceList();
      if (cached.isNotEmpty) {
        _baseDevices = Device.listFromJson(cached);
        _isLoading = false;
        _isOffline = true;
        _log('Loaded ${cached.length} cached devices');
        _emit();
      }
    }

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
      _isOffline = false;
      _emit();
    } else {
      await _waitForConnection();
    }
  }

  // -- Server bring-up fallback (legacy _waitForConnection, verbatim) --

  Future<void> _waitForConnection() async {
    await Future.delayed(serverWaitDelay);

    if (WebSocketService.isConnected) {
      WebSocketService.subscribeTo('device_list');
      _log('Server WS: Connected after wait');
      return;
    }

    if (NetworkWatcher.instance.isVortexAp) {
      _log('Server WS: In AP mode, skipping server');
      _isLoading = false;
      _isOffline = true;
      _emit();
      return;
    }

    _log('Server WS: Trying one more connect...');
    final connected = await WebSocketService.connect();
    if (connected) {
      WebSocketService.subscribeTo('device_list');
      _log('Server WS: Connected!');
    } else {
      _log('Server WS: Failed — offline mode');
      _isLoading = false;
      _isOffline = true;
      if (_baseDevices.isEmpty) {
        _errorMessage = noConnectionMessage;
      }
      _emit();
    }
  }

  // -- Reactions --

  /// Legacy Step 6.4: back on normal WiFi with the server down → nudge a
  /// reconnect. Skips Vortex AP and permission-denied emissions, matching
  /// the paths where legacy never reached 6.4.
  void _onNetworkState(NetworkState net) {
    if (net.isVortexAp) return;
    if (!net.permissionGranted) return;
    if (WebSocketService.isConnected) return;

    _log('WiFi: Normal WiFi detected, trying server reconnect...');
    WebSocketService.resetReconnectAttempts();
    WebSocketService.connect().then((connected) {
      if (connected) {
        WebSocketService.subscribeTo('device_list');
        _log('Server WS: Reconnected after WiFi switch!');
      } else {
        _log("Server WS: Still can't reach server");
      }
    });
  }

  void _applySession(EspSessionState s) {
    if (s.isActive && s.deviceId != null) {
      _espDeviceId = s.deviceId;
      _espIsUserDevice = s.isUserDevice;
    } else {
      _espDeviceId = null;
      _espIsUserDevice = false;
    }
  }

  // -- Emission --

  /// Applies the session overlay onto the base list. Pure — base entries
  /// are never mutated, matching entries are copyWith'd.
  List<Device> _withOverlay(List<Device> base) {
    final id = _espDeviceId;
    if (id == null) return base;
    return [
      for (final d in base)
        d.id == id
            ? d.copyWith(espConnected: true, espIsUserDevice: _espIsUserDevice)
            : d
    ];
  }

  void _emit() {
    _current = DeviceRepositoryState(
      devices: _withOverlay(_baseDevices),
      isLoading: _isLoading,
      wsConnected: _wsConnected,
      isOffline: _isOffline,
      errorMessage: _errorMessage,
    );
    _stateController.add(_current);
  }

  void _log(String message) {
    // ignore: avoid_print
    print('📋 $message'); // console, matching service style
    _logController.add(message); // debug terminal, when re-enabled
  }
}
