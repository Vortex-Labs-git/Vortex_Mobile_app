import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';

import '../services/esp_direct_service.dart';

/// Sensor Configuration Screen (ESP32 direct mode)
///
/// The unit has a FIXED set of 8 sensor slots (S00..S07), displayed as
/// "Sensor 01".."Sensor 08" (GUI index = slot index + 1; the wire always
/// uses S00..S07). The screen ALWAYS shows all 8 slots:
///   - S00 + S01 are the in-build sensors (temperature + humidity) —
///     read-only, always included in the save payload.
///   - S02..S07 are user-configurable: type dropdown (incl. "-- no type --")
///     and tag name field.
///
/// Architecture Doc v3 - Sensor Configuration Process:
///   - On open, send get_sensor_config → unit replies with the SAME event
///     containing no_sensors + sensor_data ({sensor_id, sensor_type,
///     sensor_name} — no values). Slots absent from the reply are shown
///     as "-- no type --".
///   - On Save, send set_sensor_config containing ONLY the configured
///     sensors: any slot whose type is "-- no type --" is EXCLUDED from
///     the message entirely (e.g. Sensor 03 with no type → no S02 entry),
///     and no_sensors counts only the included ones. sensor_data goes on
///     the wire as a RAW JSON ARRAY (firmware checks cJSON_IsArray).
///
/// ──────────────────────────────────────────────────────────────────────
/// IMPORTANT — Update rules (mirrors MotorCalibrationScreen):
/// ──────────────────────────────────────────────────────────────────────
///   - Fields populate ONLY from the FIRST get_sensor_config reply
///     (_initialConfigLoaded). Any later reply must not overwrite what
///     the user is editing.
///   - NOTE: firmware restarts the unit after a successful
///     set_sensor_config save — the WebSocket connection will drop.
class SensorConfigScreen extends StatefulWidget {
  /// Device data passed in from the detail screen (used for AppBar title etc).
  final Map<String, dynamic> deviceData;

  const SensorConfigScreen({super.key, required this.deviceData});

  @override
  State<SensorConfigScreen> createState() => _SensorConfigScreenState();
}

/// One row of the config form. Holds the wire fields plus a
/// TextEditingController for the name and a locked flag for in-build
/// sensors.
class _SensorConfigEntry {
  final String id;                       // sensor_id  e.g. "S03"
  String type;                           // sensor_type (dropdown value)
  final TextEditingController nameCtrl;  // sensor_name (tag name)
  final bool locked;                     // in-build → read-only

  _SensorConfigEntry({
    required this.id,
    required this.type,
    required String name,
    required this.locked,
  }) : nameCtrl = TextEditingController(text: name);

  Map<String, dynamic> toWireJson() => {
        'sensor_id': id,
        'sensor_type': type,
        'sensor_name': nameCtrl.text.trim(),
      };
}

class _SensorConfigScreenState extends State<SensorConfigScreen> {
  // ── Fixed slot layout ─────────────────────────────────────────────
  /// The unit always has 8 slots: S00..S07 → "Sensor 01".."Sensor 08".
  static const int _totalSlots = 8;

  /// First two slots (S00 temperature, S01 humidity) are in-build →
  /// read-only, always included in the save payload.
  static const int _inBuildCount = 2;

  /// Dropdown value meaning "this slot has no sensor configured".
  /// Slots with this type are EXCLUDED from the set_sensor_config message.
  static const String _noType = '-- no type --';

  // ── Config entries (8 fixed slots, populated from the first reply) ─
  final List<_SensorConfigEntry> _entries = [];

  // ── Sensor type dropdown options (spec: Temperature/Humidity/Moisture
  //    + "-- no type --"). Types reported by the device that aren't
  //    listed are added at parse time so the dropdown never shows an
  //    invalid value. ────────────────────────────────────────────────
  final List<String> _typeOptions = [
    _noType,
    'Temperature',
    'Humidity',
    'Moisture',
  ];

  // ── State flags ───────────────────────────────────────────────────
  /// True after the first get_sensor_config reply populated the form.
  /// Later replies are ignored (user owns the fields until save).
  bool _initialConfigLoaded = false;

  /// True while waiting for the very first reply (loading spinner).
  bool _isLoadingInitial = true;

  /// True while a save is in flight (debounces double-taps).
  bool _isSaving = false;

  // ── ESP stream subscription ───────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _configSub;

  // ── Re-request safety net (same as calibration screen) ───────────
  Timer? _initialRetryTimer;
  int _initialRetryCount = 0;
  static const int _maxInitialRetries = 3;

  // ============================================================
  // LIFECYCLE
  // ============================================================

  @override
  void initState() {
    super.initState();
    _setupEspListener();
    // Deferred one frame: _requestInitialConfig shows a snackbar when the
    // unit isn't authenticated, and ScaffoldMessenger.of(context) cannot be
    // called during initState. Post-frame, the context is fully wired and
    // the listener above is already subscribed, so no reply can be missed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _requestInitialConfig();
    });
  }

  @override
  void dispose() {
    _configSub?.cancel();
    _initialRetryTimer?.cancel();
    for (final e in _entries) {
      e.nameCtrl.dispose();
    }
    super.dispose();
  }

  // ============================================================
  // ESP32 COMMUNICATION
  // ============================================================

  /// Subscribe to the sensor config stream BEFORE sending the initial
  /// request, so we can't miss a fast reply.
  void _setupEspListener() {
    _configSub = EspDirectService.instance.sensorConfigStream.listen(
      _onConfigMessage,
    );
  }

  /// Send the very first get_sensor_config request. Repeats every 1.5s
  /// up to [_maxInitialRetries] until a reply arrives.
  void _requestInitialConfig() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      setState(() => _isLoadingInitial = false);
      _showSnack('Not connected to the sensor unit.', isError: true);
      return;
    }

    esp.requestSensorConfig();
    _initialRetryCount = 0;
    _initialRetryTimer?.cancel();
    _initialRetryTimer =
        Timer.periodic(const Duration(milliseconds: 1500), (t) {
      if (_initialConfigLoaded || !mounted) {
        t.cancel();
        return;
      }
      if (_initialRetryCount >= _maxInitialRetries) {
        t.cancel();
        if (mounted) {
          setState(() => _isLoadingInitial = false);
          _showSnack('No reply from sensor unit. Check connection.',
              isError: true);
        }
        return;
      }
      _initialRetryCount++;
      print(
        '🔁 SensorConfig: retry get_sensor_config ($_initialRetryCount/$_maxInitialRetries)',
      );
      esp.requestSensorConfig();
    });
  }

  /// Create the 8 fixed slots (S00..S07) with placeholder values. The
  /// first reply overlay replaces these with the device-reported config;
  /// slots the device doesn't mention stay "-- no type --".
  void _buildFixedSlots() {
    for (final e in _entries) {
      e.nameCtrl.dispose();
    }
    _entries.clear();
    for (var i = 0; i < _totalSlots; i++) {
      final locked = i < _inBuildCount;
      _entries.add(_SensorConfigEntry(
        id: 'S${i.toString().padLeft(2, '0')}', // S00..S07
        // In-build placeholder types by convention (S00 temp, S01 hum) —
        // the reply overlay below replaces them with device values.
        type: locked ? (i == 0 ? 'Temperature' : 'Humidity') : _noType,
        name: '',
        locked: locked,
      ));
    }
  }

  /// Handle every get_sensor_config reply from the ESP32.
  ///
  /// Rule (see class doc): only the FIRST reply populates the form.
  /// The reply is merged onto the 8 fixed slots by sensor_id — the reply
  /// may contain fewer than 8 entries (unconfigured slots are omitted by
  /// the unit) and the screen must still show all 8.
  void _onConfigMessage(Map<String, dynamic> msg) {
    if (!mounted || _initialConfigLoaded) return;

    final parsed = _parseSensorData(msg['sensor_data']);
    if (parsed.isEmpty) {
      print('⚠️ SensorConfig: reply had no parseable sensor_data: $msg');
      return;
    }

    setState(() {
      _buildFixedSlots();

      // Overlay the device-reported config onto the fixed slots by id.
      for (final m in parsed) {
        final id = m['sensor_id']?.toString() ?? '';
        final idx = _entries.indexWhere((e) => e.id == id);
        if (idx == -1) {
          print('⚠️ SensorConfig: unknown sensor_id "$id" in reply — ignored');
          continue;
        }
        final type = m['sensor_type']?.toString() ?? '';
        // Keep the dropdown valid even for unknown device-reported types.
        if (type.isNotEmpty && !_typeOptions.contains(type)) {
          _typeOptions.add(type);
        }
        final entry = _entries[idx];
        entry.type = type.isNotEmpty ? type : _noType;
        entry.nameCtrl.text = m['sensor_name']?.toString() ?? '';
      }

      _initialConfigLoaded = true;
      _isLoadingInitial = false;
      _initialRetryTimer?.cancel();
      print(
        '✅ SensorConfig: initial config loaded '
        '(${parsed.length} configured of $_totalSlots slots)',
      );
    });
  }

  /// sensor_data may arrive as an escaped JSON STRING (unit → app keeps
  /// the string convention) or a real List. Decode defensively —
  /// malformed input yields an empty list.
  List<Map<String, dynamic>> _parseSensorData(dynamic raw) {
    if (raw == null) return const [];

    dynamic decoded = raw;
    if (raw is String) {
      if (raw.trim().isEmpty) return const [];
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    }
    return const [];
  }

  // ============================================================
  // SAVE
  // ============================================================

  /// Send set_sensor_config with ONLY the configured sensors:
  ///   - in-build entries (S00/S01) always included, unchanged
  ///   - editable entries included only when a type is selected
  ///   - "-- no type --" slots are excluded from the message entirely,
  ///     and no_sensors (computed in EspDirectService from list length)
  ///     therefore counts only the included ones.
  /// The unit doesn't reply to this event — and firmware RESTARTS after
  /// a successful save — so mimic the WiFi dialog: brief sending state +
  /// confirmation snack.
  void _onSavePressed() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      _showSnack('Not connected to the sensor unit.', isError: true);
      return;
    }

    final included =
        _entries.where((e) => e.locked || e.type != _noType).toList();

    // Empty tag names on configured editable sensors would blank out the
    // device-side labels — block save. "-- no type --" slots are exempt
    // (they're not sent at all).
    final hasEmptyName =
        included.any((e) => !e.locked && e.nameCtrl.text.trim().isEmpty);
    if (hasEmptyName) {
      _showSnack('Sensor name cannot be empty.', isError: true);
      return;
    }

    setState(() => _isSaving = true);

    esp.setSensorConfig(
      sensors: included.map((e) => e.toWireJson()).toList(),
    );

    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('Sensor configuration sent to the unit.');
    });
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? GlassTokens.danger : GlassTokens.success,
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final deviceName = widget.deviceData['name']?.toString() ?? 'Sensor Unit';

    return GlassScaffold(
      // Green-tinted chrome: this screen only exists in direct-to-device mode.
      appBar: const GlassAppBar(
        title: 'Sensor Configuration',
        tint: GlassTokens.success,
      ),
      body: SafeArea(
        child: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator())
            : _entries.isEmpty
                ? Center(
                    child: Text(
                      'No sensor configuration received.',
                      style: TextStyle(color: GlassTokens.textMuted),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Device name header
                        Text(
                          deviceName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: GlassTokens.textSecondary),
                        ),
                        const SizedBox(height: 16),

                        // ── One card per slot (always all 8) ────────
                        for (var i = 0; i < _entries.length; i++) ...[
                          _buildSensorCard(i, _entries[i]),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 4),

                        // ── Save button ─────────────────────────────
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _onSavePressed,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isSaving ? 'Saving...' : 'save'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: GlassTokens.success,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              textStyle: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ── One sensor card: header / type dropdown / name field ─────────
  // Header "Sensor 01".."Sensor 08" (GUI index = slot index + 1; the
  // wire id stays S00..S07 — intentional off-by-one per the spec figure).
  Widget _buildSensorCard(int index, _SensorConfigEntry entry) {
    final String header =
        'Sensor ${(index + 1).toString().padLeft(2, '0')}';

    return GlassCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (entry.locked)
                  Row(
                    children: [
                      Icon(Icons.lock, size: 14, color: GlassTokens.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        'In-build',
                        style: TextStyle(
                          fontSize: 12,
                          color: GlassTokens.textMuted,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Sensor type ─────────────────────────────────
            Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('Sensor type',
                      style: TextStyle(color: GlassTokens.textMuted)),
                ),
                Expanded(
                  child: entry.locked
                      ? _buildReadOnlyBox(entry.type)
                      : DropdownButtonFormField<String>(
                          value: entry.type,
                          isDense: true,
                          decoration: _fieldDecoration(),
                          items: _typeOptions
                              .map((t) => DropdownMenuItem(
                                    value: t,
                                    child: Text(t),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => entry.type = v);
                            }
                          },
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Sensor name (tag) ───────────────────────────
            Row(
              children: [
                const SizedBox(
                  width: 110,
                  child: Text('Sensor name',
                      style: TextStyle(color: GlassTokens.textMuted)),
                ),
                Expanded(
                  child: entry.locked
                      ? _buildReadOnlyBox(entry.nameCtrl.text)
                      : TextField(
                          controller: entry.nameCtrl,
                          enabled: entry.type != _noType,
                          decoration: _fieldDecoration(
                            hint: entry.type == _noType
                                ? 'Select a type first'
                                : 'Enter tag name',
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Small UI helpers ────────────────────────────────────────────

  Widget _buildReadOnlyBox(String value) {
    return GlassSurface(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      showShadow: false,
      child: Text(
        value.isNotEmpty ? value : '—',
        style: const TextStyle(
          fontSize: 14,
          color: GlassTokens.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.55),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.75)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: GlassTokens.success, width: 2),
      ),
    );
  }
}