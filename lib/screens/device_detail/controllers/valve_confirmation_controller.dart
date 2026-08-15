import 'dart:async';

// =============================================================================
// VALVE CONFIRMATION CONTROLLER
// =============================================================================
// After a command is sent we wait for the valve's reported position to catch
// up with the target angle. This controller owns that wait: the pending target,
// the countdown timer and the success/timeout decision.
//
// The screen feeds it every position it receives (via [reportPosition]) and
// rebuilds on [onChanged].
// =============================================================================

/// How long to wait for a confirmation when talking straight to the ESP32 over
/// its AP — the valve answers fast on the local network.
const int kDirectConfirmationTimeoutSeconds = 10;

/// How long to wait when the command travels through the cloud.
const int kServerConfirmationTimeoutSeconds = 20;

class ValveConfirmationController {
  /// Called whenever the visible state changes (countdown tick, start, finish).
  final void Function() onChanged;

  /// Called when the reported position reached the target angle.
  final void Function() onSuccess;

  /// Called when the countdown ran out. Receives the angle we were waiting for
  /// so the caller can do a final position check.
  final void Function(int targetAngle) onTimeout;

  ValveConfirmationController({
    required this.onChanged,
    required this.onSuccess,
    required this.onTimeout,
  });

  bool _isWaiting = false;
  int? _targetAngle;
  int _countdown = 0;
  Timer? _timer;

  bool get isWaiting => _isWaiting;
  int? get targetAngle => _targetAngle;
  int get countdown => _countdown;

  /// Begins waiting for the valve to report [target].
  void start(int target, {required int timeoutSeconds}) {
    _timer?.cancel();

    _isWaiting = true;
    _targetAngle = target;
    _countdown = timeoutSeconds;
    onChanged();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _countdown--;
      onChanged();

      if (_countdown <= 0) {
        timer.cancel();
        final expected = _targetAngle;
        _clear();
        onChanged();
        if (expected != null) onTimeout(expected);
      }
    });
  }

  /// Feed every position report here. Confirms the wait when [actualPosition]
  /// matches the pending target; ignored when no wait is in progress.
  void reportPosition(int actualPosition) {
    if (!_isWaiting || _targetAngle == null) return;
    if (actualPosition != _targetAngle) return;

    _timer?.cancel();
    _clear();
    onChanged();
    onSuccess();
  }

  void _clear() {
    _isWaiting = false;
    _targetAngle = null;
    _countdown = 0;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
