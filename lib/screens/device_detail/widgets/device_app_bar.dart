import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// DEVICE APP BAR
// =============================================================================
// Translucent app bar for the device screens, tinted green while the app is
// talking to the valve directly over its own hotspot.
//
// Requires the screen to use GlassScaffold (extendBodyBehindAppBar) so there
// is something behind the bar to blur.
// =============================================================================

class DeviceAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDirectMode;
  final bool wsConnected;

  const DeviceAppBar({
    super.key,
    required this.isDirectMode,
    required this.wsConnected,
  });

  @override
  Widget build(BuildContext context) {
    return GlassAppBar(
      title: isDirectMode ? 'Direct Control' : 'Vortex Labs',
      tint: isDirectMode ? GlassTokens.success : null,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            wsConnected
                ? (isDirectMode ? Icons.settings_remote : Icons.wifi)
                : Icons.wifi_off,
            color: wsConnected ? GlassTokens.success : GlassTokens.danger,
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
