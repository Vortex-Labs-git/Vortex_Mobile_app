import 'package:flutter/material.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// MOTOR CALIBRATION BUTTON
// =============================================================================
// Direct-mode-only button shown under the Change WiFi button. Tapping it
// opens MotorCalibrationScreen — that navigation is handled in the parent
// screen via [onPressed].
// =============================================================================

class MotorCalibrationButton extends StatelessWidget {
  final VoidCallback onPressed;

  const MotorCalibrationButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GlassGhostButton(
      label: 'Motor Calibration',
      icon: Icons.tune,
      onPressed: onPressed,
    );
  }
}
