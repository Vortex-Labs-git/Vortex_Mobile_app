import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';
import 'package:flutter/services.dart';

import '../services/esp_direct_service.dart';

/// Motor Calibration Screen
///
/// Allows the user (in ESP32 direct mode) to:
///   1. View the live encoder value from the motor
///   2. Manually rotate the motor clockwise / anti-clockwise
///   3. Snapshot the current encoder value as the new "close" or "open" limit
///   4. Save the new limits back to the ESP32
///
/// ──────────────────────────────────────────────────────────────────────
/// IMPORTANT — Update rule for Close_limit / Open_limit fields:
/// ──────────────────────────────────────────────────────────────────────
/// The ESP32 replies with the SAME event (`get_motor_calibration`) in
/// two different situations:
///
///   (a) Right after we send `get_motor_calibration` (initial load).
///       At this moment the ESP32's stored limits are the source of
///       truth and we MUST populate the close/open text fields.
///
///   (b) After every `set_motor_rotation` tap. The ESP32 replies with
///       updated encoder data so we can show the live value as the
///       motor turns. The Close_limit / Open_limit fields in this
///       reply are stale and will OVERWRITE whatever the user has
///       just typed / set with "set close value" / "set open value".
///
/// To avoid that, we track `_initialLimitsLoaded`. Limits are written
/// to the UI fields only on the first reply. Every later reply only
/// updates the live encoder value.
class MotorCalibrationScreen extends StatefulWidget {
  /// Device data passed in from the device list (used for AppBar title etc).
  final Map<String, dynamic> deviceData;

  const MotorCalibrationScreen({super.key, required this.deviceData});

  @override
  State<MotorCalibrationScreen> createState() => _MotorCalibrationScreenState();
}

class _MotorCalibrationScreenState extends State<MotorCalibrationScreen> {
  // ── Live data from ESP32 ──────────────────────────────────────────
  int? _liveEncoderValue; // updates on every get_motor_calibration reply

  // ── User-editable limit fields ────────────────────────────────────
  // Populated ONCE from the first ESP32 reply. After that, the user
  // owns these values until they tap save.
  final TextEditingController _closeValueCtrl = TextEditingController();
  final TextEditingController _openValueCtrl = TextEditingController();

  // ── State flags ───────────────────────────────────────────────────
  /// Becomes true after the first `get_motor_calibration` reply has
  /// been used to populate Close_limit / Open_limit. Subsequent replies
  /// will not touch these fields.
  bool _initialLimitsLoaded = false;

  /// True while we are waiting for the very first reply, used to show
  /// a loading spinner instead of empty fields.
  bool _isLoadingInitial = true;

  /// True while a save is in flight (debounces double-taps).
  bool _isSaving = false;

  // ── ESP stream subscription ───────────────────────────────────────
  StreamSubscription<Map<String, dynamic>>? _calibSub;

  // ── Re-request safety net ─────────────────────────────────────────
  /// If the very first reply doesn't arrive (e.g. message lost),
  /// retry the get_motor_calibration request a few times.
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
    _requestInitialCalibration();
  }

  @override
  void dispose() {
    _calibSub?.cancel();
    _initialRetryTimer?.cancel();
    _closeValueCtrl.dispose();
    _openValueCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // ESP32 COMMUNICATION
  // ============================================================

  /// Subscribe to the motor calibration stream BEFORE sending the
  /// initial request, so we can't miss a fast reply.
  void _setupEspListener() {
    _calibSub = EspDirectService.instance.motorCalibrationStream.listen(
      _onCalibrationMessage,
    );
  }

  /// Send the very first `get_motor_calibration` request. Repeats
  /// every 1.5s up to [_maxInitialRetries] until a reply arrives.
  void _requestInitialCalibration() {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      // We can't talk to ESP32 yet — surface a friendly message and
      // bail out. The screen will still render but in disabled state.
      setState(() => _isLoadingInitial = false);
      _showSnack('Not connected to the valve.', isError: true);
      return;
    }

    esp.requestMotorCalibration();
    _initialRetryCount = 0;
    _initialRetryTimer?.cancel();
    _initialRetryTimer = Timer.periodic(const Duration(milliseconds: 1500), (
      t,
    ) {
      if (_initialLimitsLoaded || !mounted) {
        t.cancel();
        return;
      }
      if (_initialRetryCount >= _maxInitialRetries) {
        t.cancel();
        if (mounted) {
          setState(() => _isLoadingInitial = false);
          _showSnack(
            'No reply from valve. Check connection.',
            isError: true,
          );
        }
        return;
      }
      _initialRetryCount++;
      print(
        '🔁 Calibration: retry get_motor_calibration ($_initialRetryCount/$_maxInitialRetries)',
      );
      esp.requestMotorCalibration();
    });
  }

  /// Handle every `get_motor_calibration` message coming from the ESP32.
  ///
  /// Rule (see class doc):
  ///   - First reply  → populate close/open fields AND live value
  ///   - Later replies → live value only, leave close/open alone
  void _onCalibrationMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final encoderData = msg['encoder_data'];
    if (encoderData is! Map) {
      print('⚠️ Calibration: reply missing encoder_data: $msg');
      return;
    }

    final value = _asInt(encoderData['value']);
    final closeLimit = _asInt(encoderData['Close_limit']);
    final openLimit = _asInt(encoderData['Open_limit']);

    setState(() {
      // Live encoder value: ALWAYS update.
      if (value != null) _liveEncoderValue = value;

      // Close / Open limits: ONLY on the very first reply.
      if (!_initialLimitsLoaded) {
        if (closeLimit != null) {
          _closeValueCtrl.text = closeLimit.toString();
        }
        if (openLimit != null) {
          _openValueCtrl.text = openLimit.toString();
        }
        _initialLimitsLoaded = true;
        _isLoadingInitial = false;
        _initialRetryTimer?.cancel();
        print(
          '✅ Calibration: initial limits loaded (close=$closeLimit, open=$openLimit)',
        );
      }
    });
  }

  /// Helper: parse anything that might be int-ish (int, String) → int?
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  // ============================================================
  // BUTTON ACTIONS
  // ============================================================

  /// Send one rotation command. The user is expected to tap repeatedly.
  void _onTurnPressed({required bool clockwise}) {
    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      _showSnack('Not connected to the valve.', isError: true);
      return;
    }
    esp.setMotorRotation(clockwise: clockwise);
  }

  /// Snapshot the current live encoder value into the close-value field.
  /// After applying, warn if the new pair is invalid (close > 0 && open > 0
  /// && close < open). The snapshot is still applied — the user might be
  /// planning to fix the open value next.
  void _onSetCloseValue() {
    if (_liveEncoderValue == null) {
      _showSnack('No encoder value yet.', isError: true);
      return;
    }
    setState(() => _closeValueCtrl.text = _liveEncoderValue.toString());
    _warnIfInvalidPair();
  }

  /// Snapshot the current live encoder value into the open-value field.
  /// Same warning pattern as [_onSetCloseValue].
  void _onSetOpenValue() {
    if (_liveEncoderValue == null) {
      _showSnack('No encoder value yet.', isError: true);
      return;
    }
    setState(() => _openValueCtrl.text = _liveEncoderValue.toString());
    _warnIfInvalidPair();
  }

  /// Read both fields and show an orange warning snackbar if they violate
  /// the rule: close > 0 && open > 0 && close < open. Used by the snapshot
  /// buttons so the user gets early feedback instead of only at Save.
  void _warnIfInvalidPair() {
    final close = int.tryParse(_closeValueCtrl.text.trim());
    final open = int.tryParse(_openValueCtrl.text.trim());

    // If either field is empty / non-numeric, nothing to compare yet
    if (close == null || open == null) return;

    if (close <= 0 || open <= 0) {
      _showSnack(
        '⚠️ Close and open values must both be greater than 0.',
        isWarning: true,
      );
    } else if (close >= open) {
      _showSnack(
        '⚠️ Close ($close) must be less than Open ($open). Did you swap them?',
        isWarning: true,
      );
    }
  }

  /// Save the limit values to the ESP32.
  Future<void> _onSavePressed() async {
    if (_isSaving) return;

    final closeLimit = int.tryParse(_closeValueCtrl.text.trim());
    final openLimit = int.tryParse(_openValueCtrl.text.trim());

    // Both fields must contain valid numbers
    if (closeLimit == null || openLimit == null) {
      _showSnack('Both close and open values must be numbers.', isError: true);
      return;
    }

    // Both values must be greater than zero
    if (closeLimit <= 0 || openLimit <= 0) {
      _showSnack(
        'Close and open values must be greater than 0.',
        isError: true,
      );
      return;
    }

    // Close must be strictly less than Open
    if (closeLimit >= openLimit) {
      _showSnack(
        'Close value must be less than Open value.',
        isError: true,
      );
      return;
    }

    final esp = EspDirectService.instance;
    if (!esp.isAuthenticated) {
      _showSnack('Not connected to the valve.', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    esp.setMotorCalibration(closeLimit: closeLimit, openLimit: openLimit);

    // ESP32 doesn't ack set_motor_calibration with a dedicated reply,
    // so we just give the user a brief visual confirmation.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _isSaving = false);
    _showSnack('Calibration saved.');
  }

  /// Show a snackbar.
  /// Color priority: error (red) > warning (orange) > success (green).
  void _showSnack(
    String text, {
    bool isError = false,
    bool isWarning = false,
  }) {
    if (!mounted) return;

    Color bgColor;
    if (isError) {
      bgColor = GlassTokens.danger;
    } else if (isWarning) {
      bgColor = GlassTokens.warning;
    } else {
      bgColor = GlassTokens.success;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: bgColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final deviceName = (widget.deviceData['vwv_name'] ??
            widget.deviceData['device_name'] ??
            'Valve')
        .toString();

    return GlassScaffold(
      appBar: const GlassAppBar(title: 'Motor Calibration'),
      body: SafeArea(
        child: _isLoadingInitial
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Device name header
                    Text(
                      deviceName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: GlassTokens.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // ── Encoder value (live) ─────────────────────
                    _buildSectionTitle('Encoder Value'),
                    const SizedBox(height: 8),
                    _buildReadOnlyValueBox(
                      _liveEncoderValue?.toString() ?? '—',
                      hint: 'real time value',
                    ),
                    const SizedBox(height: 24),

                    // ── Close / Open limits ──────────────────────
                    Row(
                      children: [
                        Expanded(child: _buildSectionTitle('close value')),
                        const SizedBox(width: 16),
                        Expanded(child: _buildSectionTitle('open value')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _buildLimitField(_closeValueCtrl)),
                        const SizedBox(width: 16),
                        Expanded(child: _buildLimitField(_openValueCtrl)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── set close / set open buttons ─────────────
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _onSetCloseValue,
                            style: _setBtnStyle(),
                            child: const Text('set close value'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _onSetOpenValue,
                            style: _setBtnStyle(),
                            child: const Text('set open value'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ── Save button ──────────────────────────────
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
                          backgroundColor: GlassTokens.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // ── Manual rotation buttons ──────────────────
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                _onTurnPressed(clockwise: false),
                            style: _rotateBtnStyle(),
                            child: const Text(
                              'Turn motor\nAnticlockwise',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () =>
                                _onTurnPressed(clockwise: true),
                            style: _rotateBtnStyle(),
                            child: const Text(
                              'Turn motor\nClockwise',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap repeatedly to step the motor.',
                      style: TextStyle(
                        color: GlassTokens.textMuted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ── Small UI helpers ────────────────────────────────────────────

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        color: GlassTokens.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildReadOnlyValueBox(String value, {String? hint}) {
    return GlassSurface(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      showShadow: false,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value == '—' && hint != null ? hint : value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: value == '—'
                  ? GlassTokens.textMuted
                  : GlassTokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLimitField(TextEditingController ctrl) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
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
          borderSide: const BorderSide(color: GlassTokens.primary, width: 2),
        ),
      ),
    );
  }

  ButtonStyle _setBtnStyle() => ElevatedButton.styleFrom(
        backgroundColor: GlassTokens.primaryBright,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      );

  ButtonStyle _rotateBtnStyle() => ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF7986CB),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      );
}