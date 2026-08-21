import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// AP MODE BANNER
// =============================================================================
// Banner shown when the phone is connected to a Vortex_VA hotspot.
// Currently DISABLED in build() but kept here in case it's re-enabled.
//
// Tinted glass: green once the direct session is up, indigo while the hotspot
// is merely detected.
//
// Reads ESP32 connection state through the parent (passed in via constructor)
// rather than calling EspDirectService.instance directly, so this widget stays
// pure and easy to test.
// =============================================================================

class ApModeBanner extends StatelessWidget {
  final bool espConnected;
  final String? espConnectedDeviceId;
  final bool isEspConnecting;

  const ApModeBanner({
    super.key,
    required this.espConnected,
    required this.espConnectedDeviceId,
    required this.isEspConnecting,
  });

  @override
  Widget build(BuildContext context) {
    final Color tint =
        espConnected ? GlassTokens.success : GlassTokens.primary;

    return GlassCard(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      tint: tint,
      tintStrength: 0.18,
      child: Row(
        children: [
          // ─────────────────────────────────────────────────────────────
          // Left icon (check-circle when connected, remote when not)
          // ─────────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.15),
              border: Border.all(color: Colors.white.withValues(alpha: 0.65)),
            ),
            child: Icon(
              espConnected ? Icons.check_circle : Icons.settings_remote,
              color: tint,
              size: 20,
            ),
          ),

          const SizedBox(width: 12),

          // ─────────────────────────────────────────────────────────────
          // Title + subtitle
          // ─────────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  espConnected
                      ? 'Connected to valve directly'
                      : 'Valve WiFi detected',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: GlassTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  espConnected
                      ? 'Device: ${espConnectedDeviceId ?? "Identifying..."}'
                      : 'Tap a device to set up WiFi or control directly',
                  style: const TextStyle(
                    fontSize: 12,
                    color: GlassTokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // ─────────────────────────────────────────────────────────────
          // Spinner while connecting
          // ─────────────────────────────────────────────────────────────
          if (isEspConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}
