import 'package:flutter/material.dart';

import '../../../widgets/glass/glass.dart';

// =============================================================================
// CHANGE WIFI BUTTON
// =============================================================================
// Direct-mode-only button at the bottom of the screen. Tapping it opens the
// WiFi credentials dialog (handled in the parent screen via [onPressed]) so
// the user can push home WiFi credentials to the connected ESP32.
// =============================================================================

class ChangeWifiButton extends StatelessWidget {
  final VoidCallback onPressed;

  const ChangeWifiButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return GlassGhostButton(
      label: 'Change WiFi connection',
      icon: Icons.wifi,
      onPressed: onPressed,
    );
  }
}
